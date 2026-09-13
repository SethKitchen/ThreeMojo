# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Turns a manifest plus captured probe output into a coverage report.

The manifest lists everything the instrumented code *could* report (the
denominator); the captured stderr lists what it *did* report (the numerator).
Probe records repeat constantly — a statement in a loop emits thousands — so
everything here works on the set of distinct ids.

A decision contributes two outcomes, True and False. Exercising only one of
them is the partial case that line coverage alone would score as complete.
"""

from coverage.mcdc import DecisionTrace, find_trace, is_mcdc_covered
from coverage.runtime import BRANCH_PREFIX, LINE_PREFIX


@fieldwise_init
struct Entry(Copyable, Movable):
    """One measurable item: a statement, or a decision needing both outcomes."""

    var module: String
    var line: Int
    var is_branch: Bool
    # Which operand of a compound decision this is, or -1 for a statement or
    # for the decision as a whole.
    var condition_index: Int
    # An MC-DC obligation: this operand must be shown to independently decide
    # the outcome. One item, not two, since it is a single yes/no property.
    var is_mcdc: Bool

    def id(self) -> String:
        """Return the probe id this entry expects to see."""
        var base = self.module + ":" + String(self.line)
        if self.condition_index < 0:
            return base^
        return base + "." + String(self.condition_index)

    def label(self) -> String:
        """Return how this entry is named in the report."""
        if self.condition_index < 0:
            return "line " + String(self.line) + ": decision"
        return (
            "line "
            + String(self.line)
            + " condition "
            + String(self.condition_index)
            + ":"
        )

    def decision_id(self) -> String:
        """Return the id of the decision this entry belongs to."""
        return self.module + ":" + String(self.line)


struct Hits(Movable):
    """The distinct probe payloads observed during a run."""

    var ids: List[String]

    def __init__(out self):
        """Start with nothing observed."""
        self.ids = List[String]()

    def add(mut self, var id: String):
        """Record `id` if it has not been seen already."""
        if not self.contains(id):
            self.ids.append(id^)

    def contains(self, id: String) -> Bool:
        """Return True if `id` was observed."""
        for seen in self.ids:
            if seen == id:
                return True
        return False


struct Report(Movable):
    """A rendered report and the totals behind it."""

    var text: String
    var covered: Int
    var total: Int

    def __init__(out self, var text: String, covered: Int, total: Int):
        """Store the rendered text alongside its numerator and denominator."""
        self.text = text^
        self.covered = covered
        self.total = total

    def is_complete(self) -> Bool:
        """Return True if every measurable item was covered."""
        return self.covered == self.total


def parse_manifest(text: String) raises -> List[Entry]:
    """Return the entries listed in a manifest file.

    Args:
        text: Manifest contents, one `L`/`B` record per line.

    Returns:
        Every measurable entry, in file order.

    Raises:
        Error: If a record is malformed.
    """
    var entries = List[Entry]()
    for raw in text.splitlines():
        var line = String(raw.strip())
        if line == "":
            continue
        var fields = line.split(" ")
        # `L`/`B` carry a module and line; `C` adds the operand's index.
        if len(fields) == 3 and (fields[0] == "L" or fields[0] == "B"):
            entries.append(
                Entry(
                    String(fields[1]),
                    Int(String(fields[2])),
                    fields[0] == "B",
                    -1,
                    False,
                )
            )
        elif len(fields) == 4 and (fields[0] == "C" or fields[0] == "M"):
            entries.append(
                Entry(
                    String(fields[1]),
                    Int(String(fields[2])),
                    fields[0] == "C",
                    Int(String(fields[3])),
                    fields[0] == "M",
                )
            )
        else:
            raise Error("Malformed manifest record: " + line)
    return entries^


def parse_hits(text: String) raises -> Hits:
    """Return the distinct probe payloads found in captured stderr.

    Args:
        text: Captured stderr, which may also hold unrelated output.

    Returns:
        The set of observed payloads.

    Raises:
        Error: Never; present for symmetry with the other parsers.
    """
    var hits = Hits()
    for raw in text.splitlines():
        var line = String(raw.strip())
        if line.startswith(LINE_PREFIX):
            hits.add(String(line.removeprefix(LINE_PREFIX)))
        elif line.startswith(BRANCH_PREFIX):
            hits.add(String(line.removeprefix(BRANCH_PREFIX)))
    return hits^


def _percent(covered: Int, total: Int) -> Int:
    """Return `covered` as a whole percentage of `total`, or 100 if empty."""
    if total == 0:
        return 100
    return covered * 100 // total


def _pad(text: String, width: Int) -> String:
    """Return `text` padded with spaces to at least `width` characters."""
    var length = 0
    for _ in text.codepoint_slices():
        length += 1
    if length >= width:
        return String(text)
    return text + " " * (width - length)


def _modules_in_order(entries: List[Entry]) raises -> List[String]:
    """Return each distinct module name, in first-seen order."""
    var names = List[String]()
    for entry in entries:
        var seen = False
        for name in names:
            if name == entry.module:
                seen = True
                break
        if not seen:
            names.append(entry.module)
    return names^


def build_report(
    entries: List[Entry], hits: Hits, traces: List[DecisionTrace]
) raises -> Report:
    """Render the coverage report for `entries` against observed `hits`.

    Args:
        entries: Everything measurable, from the manifest.
        hits: The distinct probe payloads observed.
        traces: Per-decision evaluation vectors, for the MC-DC obligations.

    Returns:
        The rendered report with overall numerator and denominator.

    Raises:
        Error: If a module name cannot be resolved.
    """
    var out = String("")
    var grand_covered = 0
    var grand_total = 0

    for module in _modules_in_order(entries):
        var line_covered = 0
        var line_total = 0
        var branch_covered = 0
        var branch_total = 0
        var mcdc_covered = 0
        var mcdc_total = 0
        var missing_lines = List[Int]()
        var partial = String("")

        for entry in entries:
            if entry.module != module:
                continue
            var id = entry.id()
            if entry.is_mcdc:
                mcdc_total += 1
                var slot = find_trace(traces, entry.decision_id())
                var shown = False
                if slot >= 0:
                    shown = is_mcdc_covered(traces[slot], entry.condition_index)
                if shown:
                    mcdc_covered += 1
                else:
                    partial += (
                        "    " + entry.label() + " no MC-DC independence pair\n"
                    )
            elif entry.is_branch:
                # Two outcomes per decision or condition, counted separately.
                branch_total += 2
                var took_true = hits.contains(id + ":T")
                var took_false = hits.contains(id + ":F")
                if took_true:
                    branch_covered += 1
                if took_false:
                    branch_covered += 1
                if took_true != took_false:
                    var never = String("True") if took_false else String(
                        "False"
                    )
                    partial += (
                        "    "
                        + entry.label()
                        + " never evaluated "
                        + never
                        + "\n"
                    )
            else:
                line_total += 1
                if hits.contains(id):
                    line_covered += 1
                else:
                    missing_lines.append(entry.line)

        out += _pad(module, 24)
        out += (
            "lines "
            + _pad(
                String(line_covered) + "/" + String(line_total),
                8,
            )
            + _pad(String(_percent(line_covered, line_total)) + "%", 6)
        )
        out += (
            "branches "
            + _pad(
                String(branch_covered) + "/" + String(branch_total),
                8,
            )
            + _pad(String(_percent(branch_covered, branch_total)) + "%", 6)
        )
        out += (
            "mcdc "
            + _pad(String(mcdc_covered) + "/" + String(mcdc_total), 7)
            + String(_percent(mcdc_covered, mcdc_total))
            + "%"
        )
        out += "\n"

        if len(missing_lines) > 0:
            out += "    never executed: "
            var first = True
            for line in missing_lines:
                if not first:
                    out += ", "
                out += String(line)
                first = False
            out += "\n"
        out += partial

        grand_covered += line_covered + branch_covered + mcdc_covered
        grand_total += line_total + branch_total + mcdc_total

    out += _pad(String("TOTAL"), 24)
    out += (
        _pad(String(grand_covered) + "/" + String(grand_total), 10)
        + String(_percent(grand_covered, grand_total))
        + "%\n"
    )
    return Report(out^, grand_covered, grand_total)
