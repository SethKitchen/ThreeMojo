# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Native protocol controls for one named nonempty-loop outcome mask.

Synthetic manifests and contrary hits below are negative protocol fixtures.
They are not source generation receipts or coverage qualification evidence.
"""
from coverage.report import parse_manifest, Hits, build_report
from coverage.mcdc import DecisionTrace
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_raises,
)


def _header() -> String:
    return (
        "P constant-loops-v2"
        " 0000000000000000000000000000000000000000000000000000000000000000\n"
    )


def test_reviewed_nonempty_requires_true_and_renders_lower_bound() raises:
    var entries = parse_manifest(
        _header()
        + "L dispatch 126\nR dispatch 126 T reviewed-nonempty-range 1\n"
    )
    var hits = Hits()
    hits.add("dispatch:126")
    var missing = build_report(entries, hits, List[DecisionTrace]())
    assert_false(missing.is_complete())
    assert_equal(missing.covered, 1)
    assert_equal(missing.total, 2)
    assert_equal(missing.potential, 3)
    hits.add("dispatch:126:T")
    var complete = build_report(entries, hits, List[DecisionTrace]())
    assert_true(complete.is_complete())
    assert_equal(complete.covered, 2)
    assert_true(complete.text.find("minimum cardinality 1") >= 0)


def test_reviewed_nonempty_contrary_false_is_fatal() raises:
    var entries = parse_manifest(
        _header() + "R dispatch 126 T reviewed-nonempty-range 1\n"
    )
    var hits = Hits()
    hits.add("dispatch:126:T")
    hits.add("dispatch:126:F")
    with assert_raises(contains="proof contradicted"):
        _ = build_report(entries, hits, List[DecisionTrace]())


def test_other_branch_condition_and_mcdc_remain_required() raises:
    var entries = parse_manifest(
        _header()
        + "R dispatch 126 T reviewed-nonempty-range 1\nB other 7\nC other 7"
        " 0\nM other 7 0\n"
    )
    var hits = Hits()
    hits.add("dispatch:126:T")
    var report = build_report(entries, hits, List[DecisionTrace]())
    assert_false(report.is_complete())
    assert_equal(report.covered, 1)
    assert_equal(report.total, 6)
    assert_equal(report.potential, 7)


def test_new_reason_rejects_wrong_outcome_and_false_cardinality() raises:
    for suffix in [
        "F reviewed-nonempty-range 1",
        "T reviewed-nonempty-range 0",
        "T reviewed-nonempty-range 2",
    ]:
        with assert_raises(contains="Malformed constant-loop outcome mask"):
            _ = parse_manifest(_header() + "R dispatch 126 " + suffix + "\n")
    var entries = parse_manifest(_header() + "R literal 2 T literal-range 2\n")
    var hits = Hits()
    hits.add("literal:2:T")
    var report = build_report(entries, hits, List[DecisionTrace]())
    assert_true(report.is_complete())
    assert_true(report.text.find("literal-range cardinality 2") >= 0)
    assert_true(report.text.find("minimum cardinality") < 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
