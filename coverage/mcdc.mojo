# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Modified Condition/Decision Coverage analysis.

Condition coverage only asks that each operand be seen True and False at some
point. MC-DC additionally asks that each operand be shown to *independently*
change the decision: for condition `i` there must be two evaluations whose
outcomes differ, where `i` differs and no other condition does.

The data for this is already in the probe stream. Because the condition probes
of one evaluation fire in order and are terminated by that decision's own
probe, a run of `COVBRANCH:m:4.k` records followed by `COVBRANCH:m:4` is
exactly one evaluation vector. A short-circuited operand simply never fires,
which is what `MASKED` records.

Short-circuit evaluation makes strict unique-cause MC-DC unachievable for most
compound decisions, so this uses the standard masking variant: an operand that
went unevaluated in either half of a pair is ignored when checking that the
other conditions held still.
"""

from coverage.runtime import BRANCH_PREFIX

comptime MASKED = -1
comptime FALSE = 0
comptime TRUE = 1


@fieldwise_init
struct Evaluation(Copyable, Movable):
    """One evaluation of a decision: each operand's state, and the outcome."""

    var values: List[Int]
    var outcome: Bool

    def value(self, index: Int) -> Int:
        """Return the state of condition `index`, or MASKED if unevaluated."""
        if index < 0 or index >= len(self.values):
            return MASKED
        return self.values[index]

    def matches(self, other: Self) -> Bool:
        """Return True if `other` records the same states and outcome."""
        if self.outcome != other.outcome:
            return False
        var width = max(len(self.values), len(other.values))
        for index in range(width):
            if self.value(index) != other.value(index):
                return False
        return True


struct DecisionTrace(Copyable, Movable):
    """Every distinct way one decision was evaluated."""

    var id: String
    var evaluations: List[Evaluation]

    def __init__(out self, var id: String):
        """Start an empty trace for the decision identified by `id`."""
        self.id = id^
        self.evaluations = List[Evaluation]()

    def add(mut self, var evaluation: Evaluation):
        """Record `evaluation` unless an identical one is already held.

        Deduplicating here keeps the pair search quadratic in the number of
        *distinct* evaluations rather than in the number of executions, which
        matters for a decision inside a loop.
        """
        for seen in self.evaluations:
            if seen.matches(evaluation):
                return
        self.evaluations.append(evaluation^)


def _independence_pair(a: Evaluation, b: Evaluation, index: Int) -> Bool:
    """Return True if `a` and `b` show condition `index` deciding the outcome.

    The pair must flip that condition, flip the outcome, and hold every other
    condition still. Operands masked in either evaluation are skipped, since
    short-circuiting means they could not have contributed.
    """
    if a.value(index) == MASKED or b.value(index) == MASKED:
        return False
    if a.value(index) == b.value(index):
        return False
    if a.outcome == b.outcome:
        return False

    var width = max(len(a.values), len(b.values))
    for other in range(width):
        if other == index:
            continue
        var left = a.value(other)
        var right = b.value(other)
        if left != MASKED and right != MASKED and left != right:
            return False
    return True


def is_mcdc_covered(trace: DecisionTrace, index: Int) -> Bool:
    """Return True if some pair of evaluations isolates condition `index`."""
    for first in range(len(trace.evaluations)):
        for second in range(first + 1, len(trace.evaluations)):
            if _independence_pair(
                trace.evaluations[first], trace.evaluations[second], index
            ):
                return True
    return False


def split_last(text: String, separator: String) -> List[String]:
    """Split `text` at its final `separator` into a base and a suffix.

    Returns one element when the separator is absent, which is how a decision
    record (`m:4`) is told apart from a condition record (`m:4.0`).

    Args:
        text: The probe id or payload to split.
        separator: The single character to split on.

    Returns:
        Either `[text]` or `[base, suffix]`.
    """
    var base = String("")
    var suffix = String("")
    var seen = False
    for cp in text.codepoint_slices():
        if cp == separator:
            if seen:
                base += separator + suffix
                suffix = String("")
            else:
                seen = True
            continue
        if seen:
            suffix += String(cp)
        else:
            base += String(cp)
    var parts = List[String]()
    parts.append(base^)
    if seen:
        parts.append(suffix^)
    return parts^


def parse_traces(text: String) raises -> List[DecisionTrace]:
    """Reconstruct each decision's evaluation vectors from captured stderr.

    Condition records accumulate until the decision's own record closes the
    evaluation. Re-entrant evaluation is handled naturally: an inner call
    completes, and so closes its vector, before the outer one does.

    Args:
        text: Captured stderr, in the order the probes fired.

    Returns:
        One trace per decision that recorded at least one evaluation.

    Raises:
        Error: If a probe payload is malformed.
    """
    var traces = List[DecisionTrace]()
    var pending_ids = List[String]()
    var pending_values = List[List[Int]]()

    for raw in text.splitlines():
        var line = String(raw.strip())
        if not line.startswith(BRANCH_PREFIX):
            continue

        var payload = String(line.removeprefix(BRANCH_PREFIX))
        var halves = split_last(payload, String(":"))
        if len(halves) != 2:
            raise Error("Malformed branch record: " + line)
        var state = TRUE if halves[1] == "T" else FALSE
        var parts = split_last(halves[0], String("."))
        var base = parts[0].copy()

        var slot = -1
        for index in range(len(pending_ids)):
            if pending_ids[index] == base:
                slot = index
                break
        if slot < 0:
            pending_ids.append(base.copy())
            pending_values.append(List[Int]())
            slot = len(pending_ids) - 1

        if len(parts) == 2:
            # A condition: remember its state until the decision closes.
            var position = Int(parts[1])
            while len(pending_values[slot]) <= position:
                pending_values[slot].append(MASKED)
            pending_values[slot][position] = state
            continue

        # The decision itself: close and file this evaluation.
        var trace_slot = -1
        for index in range(len(traces)):
            if traces[index].id == base:
                trace_slot = index
                break
        if trace_slot < 0:
            traces.append(DecisionTrace(base.copy()))
            trace_slot = len(traces) - 1
        traces[trace_slot].add(
            Evaluation(pending_values[slot].copy(), state == TRUE)
        )
        pending_values[slot].clear()

    return traces^


def merge_traces(mut into: List[DecisionTrace], more: List[DecisionTrace]):
    """Join one run's traces to another's, decision by decision.

    A decision evaluated by two suites has one trace holding both suites'
    distinct evaluations, as one trace of the two captures joined would
    hold them: an independence pair can span the suites. The report reads
    each suite's capture on its own, because past two gigabytes a single
    read of their concatenation fails on macOS.

    Args:
        into: The traces so far, extended in place.
        more: Another run's traces.
    """
    for trace in more:
        var slot = find_trace(into, trace.id)
        if slot < 0:
            into.append(trace.copy())
            continue
        for evaluation in trace.evaluations:
            into[slot].add(evaluation.copy())


def find_trace(traces: List[DecisionTrace], id: String) -> Int:
    """Return the index of the trace for `id`, or -1 if it was never evaluated.
    """
    for index in range(len(traces)):
        if traces[index].id == id:
            return index
    return -1
