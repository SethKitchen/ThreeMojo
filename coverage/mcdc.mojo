# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Modified Condition/Decision Coverage analysis.

Condition coverage only asks that each operand be seen True and False at some
point. MC-DC additionally asks that each operand be shown to *independently*
change the decision: for condition `i` there must be two evaluations whose
outcomes differ, where `i` differs and no other condition does.

Version 2 records carry a complete vector assembled in the evaluating function
invocation. No parser state associates operand events with an evaluation.
Incomplete evaluations contribute condition hits, but never MC-DC evidence.
Legacy operand streams cannot distinguish recursion from abandoned evaluations
and are refused. Recapture them with the version 2 instrumenter.

Short-circuit evaluation makes strict unique-cause MC-DC unachievable for most
compound decisions, so this uses the standard masking variant: an operand that
went unevaluated in either half of a pair is ignored when checking that the
other conditions held still.
"""

from coverage.runtime import BRANCH_PREFIX, EVALUATION_PREFIX
from std.collections import Dict

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

    Only complete version 2 vectors certify compound MC-DC. Old unframed
    compound streams raise an error because their boundaries are ambiguous.

    Args:
        text: Captured stderr, in the order the probes fired.

    Returns:
        One trace per decision that recorded at least one evaluation.

    Raises:
        Error: If a probe payload is malformed.
    """
    var records = text.splitlines()
    if len(records) > 0 and not text.endswith("\n"):
        if (
            String(records[len(records) - 1])
            .strip()
            .startswith(EVALUATION_PREFIX)
        ):
            raise Error("Unterminated evaluation record")
    var parser = TraceParser()
    for raw in records:
        parser.feed(String(raw))
    return parser^.finish()


def _validate_decision_id(id: String) raises:
    """Refuse malformed IDs before accepting a complete vector."""
    var parts = split_last(id, String(":"))
    if len(parts) != 2 or parts[0] == "" or parts[1] == "":
        raise Error("Malformed evaluation decision ID: " + id)
    for cp in parts[1].codepoint_slices():
        if cp < "0" or cp > "9":
            raise Error("Malformed evaluation decision ID: " + id)
    if Int(parts[1]) < 1:
        raise Error("Malformed evaluation decision ID: " + id)


struct TraceParser(Movable):
    """Read complete evaluation records with no pending execution state.

    Storage depends on distinct decision vectors, not calls, nesting depth,
    abandoned evaluations, or the number of concurrent function invocations.
    """

    var traces: List[DecisionTrace]
    var trace_slots: Dict[String, Int]

    def __init__(out self):
        """Start with nothing read."""
        self.traces = List[DecisionTrace]()
        self.trace_slots = Dict[String, Int]()

    def _add(mut self, id: String, var values: List[Int], outcome: Bool) raises:
        """Store a valid complete evaluation in first-completion order."""
        var slot = self.trace_slots.get(id, -1)
        if slot < 0:
            slot = len(self.traces)
            self.trace_slots[id.copy()] = slot
            self.traces.append(DecisionTrace(id.copy()))
        self.traces[slot].add(Evaluation(values^, outcome))

    def feed(mut self, raw: String) raises:
        """Read one complete record; reject ambiguous legacy compound data.

        Args:
            raw: One captured stderr line.

        Raises:
            Error: If a record is malformed or needs a version 2 recapture.
        """
        var line = String(raw.strip())
        if line.startswith(EVALUATION_PREFIX):
            if line.byte_length() + 1 > 512 or not line.endswith(";"):
                raise Error("Malformed or truncated evaluation record: " + line)
            var body = String(
                line.removeprefix(EVALUATION_PREFIX).removesuffix(";")
            )
            var vector = split_last(body, String(":"))
            if len(vector) != 2 or vector[1].byte_length() < 2:
                raise Error("Malformed evaluation vector: " + line)
            var head = split_last(vector[0], String(":"))
            if len(head) != 2 or (head[1] != "T" and head[1] != "F"):
                raise Error("Malformed evaluation outcome: " + line)
            _validate_decision_id(head[0])
            var values = List[Int]()
            var observed = False
            for cp in vector[1].codepoint_slices():
                if cp == "T":
                    values.append(TRUE)
                    observed = True
                elif cp == "F":
                    values.append(FALSE)
                    observed = True
                elif cp == "-":
                    values.append(MASKED)
                else:
                    raise Error("Malformed evaluation operand: " + line)
            if not observed:
                raise Error("Evaluation has no observed operand: " + line)
            self._add(head[0], values^, head[1] == "T")
            return
        if not line.startswith(BRANCH_PREFIX):
            return
        var payload = String(line.removeprefix(BRANCH_PREFIX))
        var halves = split_last(payload, String(":"))
        if len(halves) != 2:
            raise Error("Malformed branch record: " + line)
        if halves[1] != "T" and halves[1] != "F":
            raise Error("Malformed branch outcome: " + line)
        var parts = split_last(halves[0], String("."))
        if len(parts) == 2:
            raise Error(
                "Legacy compound coverage is ambiguous; recapture with"
                " protocol 2"
            )
        # Legacy decision-only records have no condition evidence.
        _validate_decision_id(halves[0])
        self._add(halves[0], List[Int](), halves[1] == "T")

    def finish(deinit self) -> List[DecisionTrace]:
        """Return the distinct complete vectors, in first-completion order."""
        return self.traces^


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
