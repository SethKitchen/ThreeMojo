# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Prints the coverage report for a completed instrumented run.

    mojo run -I . coverage/report_cli.mojo <manifest.txt> <hits.txt>

Exits non-zero when anything measurable went uncovered, so `make coverage` can
act as a gate rather than just a readout.
"""

from coverage.mcdc import parse_traces
from coverage.report import build_report, parse_hits, parse_manifest
from std.pathlib import Path
from std.sys import argv


def main() raises:
    var args = argv()
    if len(args) != 3:
        raise Error("usage: report_cli <manifest.txt> <hits.txt>")

    var entries = parse_manifest(Path(String(args[1])).read_text())
    var captured = Path(String(args[2])).read_text()
    var hits = parse_hits(captured)
    # MC-DC needs the ordered stream, not the deduplicated set.
    var traces = parse_traces(captured)
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
