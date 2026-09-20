# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Prints the coverage report for a completed instrumented run.

    mojo run -I . coverage/report_cli.mojo <manifest.txt> <hits.txt>...

Each hits file is one suite's captured stderr, read and parsed on its own:
the captures together pass two gigabytes, and a single read of that much
fails on macOS with "Invalid argument". The MC-DC traces keep each suite's
order, joined suite after suite, exactly as a concatenation would hold them.

Exits non-zero when anything measurable went uncovered, so `make coverage` can
act as a gate rather than just a readout.
"""

from coverage.mcdc import DecisionTrace, merge_traces, parse_traces
from coverage.report import Hits, build_report, parse_hits, parse_manifest
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
        var captured = Path(String(args[index])).read_text()
        hits.absorb(parse_hits(captured))
        merge_traces(traces, parse_traces(captured))
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
