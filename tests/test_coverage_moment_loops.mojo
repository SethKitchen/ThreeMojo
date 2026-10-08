# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Synthetic mandatory-T and contrary-F controls, never executed-hit credit."""
from coverage.report import parse_manifest, Hits, build_report
from coverage.mcdc import DecisionTrace
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_raises,
)


def test_separate_literal_and_dynamic_moment_masks_require_true() raises:
    for suffix in [
        "92 T literal-range 5",
        "98 T literal-range 5",
        "111 T literal-range 21",
        "119 T literal-range 21",
        "125 T literal-range 11",
        "163 T literal-range 4",
        "97 T reviewed-nonempty-range 1",
    ]:
        var manifest = (
            "P constant-loops-v2"
            " 0000000000000000000000000000000000000000000000000000000000000000\nR"
            " moment "
            + suffix
            + "\n"
        )
        var entries = parse_manifest(manifest)
        var hits = Hits()
        var missing = build_report(entries, hits, List[DecisionTrace]())
        assert_false(missing.is_complete())
        assert_equal(missing.total, 1)
        assert_equal(missing.potential, 2)
        var line = suffix.split(" ")[0]
        hits.add("moment:" + line + ":T")
        var complete = build_report(entries, hits, List[DecisionTrace]())
        assert_true(complete.is_complete())
        hits.add("moment:" + line + ":F")
        with assert_raises(contains="proof contradicted"):
            _ = build_report(entries, hits, List[DecisionTrace]())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
