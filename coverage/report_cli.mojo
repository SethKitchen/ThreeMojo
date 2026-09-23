# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Prints the coverage report for a completed instrumented run.

    mojo run -I . coverage/report_cli.mojo <manifest.txt> <hits.txt>...

Each hits file is one suite's captured stderr, read and parsed on its own
and in pieces: the captures together pass two gigabytes, a single read of
that much fails on macOS with "Invalid argument", and one suite's capture
alone can pass the memory the machine has. The MC-DC traces keep each
suite's order, joined suite after suite, exactly as a concatenation would
hold them.

Exits non-zero when anything measurable went uncovered, so `make coverage` can
act as a gate rather than just a readout.
"""

from coverage.mcdc import DecisionTrace, TraceParser, merge_traces
from coverage.report import (
    Hits,
    absorb_capture,
    build_report,
    parse_manifest,
)
from std.pathlib import Path
from std.sys import argv


def main() raises:
    var args = argv()
    if len(args) < 3:
        raise Error("usage: report_cli <manifest.txt> <hits.txt>...")

    var entries = parse_manifest(Path(String(args[1])).read_text())
    var hits = Hits()
    # MC-DC needs the ordered stream, not the deduplicated set.
    var traces = List[DecisionTrace]()
    for index in range(2, len(args)):
        # A parser per suite, so that an evaluation left open at the end of
        # one capture is not closed by the next suite's records.
        var parser = TraceParser()
        absorb_capture(String(args[index]), hits, parser)
        merge_traces(traces, parser^.finish())
    var report = build_report(entries, hits, traces)

    print(report.text, end="")

    if not report.is_complete():
        raise Error(
            "Coverage is incomplete: "
            + String(report.total - report.covered)
            + " of "
            + String(report.total)
            + " items never covered."
        )
