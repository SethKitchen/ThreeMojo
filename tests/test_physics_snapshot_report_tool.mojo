# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The snapshot report reproduces the committed #633 report from its CSVs."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from bench.physics_snapshot_report import Num, break_even, median_of, report

comptime EVIDENCE = "docs/validation/owned-physics-snapshots-633"


def _without_source_hash(text: String) -> String:
    """Drop the final analysis_source_sha256 member."""
    return String(text[byte = : text.find('  "analysis_source_sha256"')])


def test_the_committed_report_is_reproduced() raises:
    var result = report(
        EVIDENCE + "-native.csv",
        EVIDENCE + "-allocations.csv",
        EVIDENCE + "-small-repeat.csv",
        EVIDENCE + "-measured-source.json",
    )
    assert_equal(
        result[1], "Validated 1344 native rows and 456 allocation rows"
    )
    assert_equal(
        _without_source_hash(result[0]),
        _without_source_hash(Path(EVIDENCE + ".json").read_text()),
    )


def test_a_missing_sample_is_refused() raises:
    var text = Path(EVIDENCE + "-native.csv").read_text()
    var path = mkdtemp() + "/native.csv"
    # Drop the last row.
    var body = String(text.rstrip("\n"))
    Path(path).write_text(String(body[byte = : body.rfind("\n") + 1]))
    with assert_raises(contains="Wrong sample set"):
        _ = report(path, EVIDENCE + "-allocations.csv", "", "")


def test_medians_and_break_even_follow_python() raises:
    var odd: List[Int] = [5, 1, 3]
    assert_true(median_of(odd).whole)
    assert_equal(median_of(odd).value, 3.0)
    var even: List[Int] = [1, 2]
    assert_equal(median_of(even).value, 1.5)
    assert_true(
        break_even(
            Num(10.0, True, False), Num(1.0, True, False), Num(2.0, True, False)
        ).none
    )
    assert_equal(
        break_even(
            Num(1024.0, True, False),
            Num(2048.0, True, False),
            Num(0.0, True, False),
        ).value,
        513.0,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
