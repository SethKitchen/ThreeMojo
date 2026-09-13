# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `coverage.report`."""

from coverage.mcdc import parse_traces
from coverage.report import (
    Entry,
    Hits,
    build_report,
    parse_hits,
    parse_manifest,
)
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def report_for(manifest: String, stderr: String) raises -> String:
    """Return the rendered report for a manifest and captured stderr.

    Args:
        manifest: Manifest file contents.
        stderr: Captured probe output.

    Returns:
        The rendered report text.

    Raises:
        Error: If the manifest is malformed.
    """
    return build_report(
        parse_manifest(manifest), parse_hits(stderr), parse_traces(stderr)
    ).text


def test_manifest_records_are_parsed() raises:
    var entries = parse_manifest(String("L math/v 3\nB math/v 7\n"))
    assert_equal(len(entries), 2)
    assert_equal(entries[0].module, String("math/v"))
    assert_equal(entries[0].line, 3)
    assert_false(entries[0].is_branch)
    assert_true(entries[1].is_branch)


def test_blank_manifest_lines_are_ignored() raises:
    assert_equal(len(parse_manifest(String("\nL math/v 3\n\n"))), 1)


def test_malformed_manifest_record_is_rejected() raises:
    var raised = False
    try:
        _ = parse_manifest(String("L math/v\n"))
    except e:
        raised = True
    assert_true(raised)


def test_repeated_hits_are_collapsed() raises:
    var hits = parse_hits(String("COVLINE:m:1\nCOVLINE:m:1\nCOVLINE:m:2\n"))
    assert_equal(len(hits.ids), 2)


def test_unrelated_stderr_output_is_ignored() raises:
    var hits = parse_hits(
        String("Failed to initialize Crashpad\nCOVLINE:m:1\n")
    )
    assert_equal(len(hits.ids), 1)
    assert_true(hits.contains(String("m:1")))


def test_branch_outcomes_are_tracked_separately() raises:
    var hits = parse_hits(String("COVBRANCH:m:4:T\nCOVBRANCH:m:4:F\n"))
    assert_true(hits.contains(String("m:4:T")))
    assert_true(hits.contains(String("m:4:F")))


def test_fully_covered_run_reports_complete() raises:
    var report = build_report(
        parse_manifest(String("L m 1\n")),
        parse_hits(String("COVLINE:m:1\n")),
        parse_traces(String("COVLINE:m:1\n")),
    )
    assert_true(report.is_complete())
    assert_equal(report.covered, 1)
    assert_equal(report.total, 1)


def test_uncovered_line_is_listed() raises:
    var text = report_for(String("L m 1\nL m 2\n"), String("COVLINE:m:1\n"))
    assert_true("never executed: 2" in text)
    assert_true("lines 1/2" in text)


def test_decision_counts_as_two_items() raises:
    var report = build_report(
        parse_manifest(String("B m 4\n")),
        parse_hits(String("COVBRANCH:m:4:T\n")),
        parse_traces(String("COVBRANCH:m:4:T\n")),
    )
    # One of two outcomes seen, so a half-covered decision is not complete.
    assert_equal(report.covered, 1)
    assert_equal(report.total, 2)
    assert_false(report.is_complete())


def test_decision_missing_its_false_outcome_is_named() raises:
    var text = report_for(String("B m 4\n"), String("COVBRANCH:m:4:T\n"))
    assert_true("line 4: decision never evaluated False" in text)


def test_decision_missing_its_true_outcome_is_named() raises:
    var text = report_for(String("B m 4\n"), String("COVBRANCH:m:4:F\n"))
    assert_true("line 4: decision never evaluated True" in text)


def test_decision_taking_both_outcomes_is_not_flagged() raises:
    var text = report_for(
        String("B m 4\n"), String("COVBRANCH:m:4:T\nCOVBRANCH:m:4:F\n")
    )
    assert_true("never evaluated" not in text)
    assert_true("branches 2/2" in text)


def test_a_decision_never_reached_at_all_is_not_reported_as_partial() raises:
    # Both outcomes missing is a plain gap, not a lopsided decision.
    var text = report_for(String("B m 4\n"), String(""))
    assert_true("never evaluated" not in text)
    assert_true("branches 0/2" in text)


def test_modules_are_reported_separately_and_in_order() raises:
    var text = report_for(String("L b 1\nL a 1\n"), String("COVLINE:b:1\n"))
    assert_true(text.find("b ") < text.find("a "))
    assert_true("TOTAL" in text)


def test_totals_combine_lines_and_branches() raises:
    var report = build_report(
        parse_manifest(String("L m 1\nB m 2\n")),
        parse_hits(String("COVLINE:m:1\nCOVBRANCH:m:2:T\n")),
        parse_traces(String("COVLINE:m:1\nCOVBRANCH:m:2:T\n")),
    )
    assert_equal(report.total, 3)
    assert_equal(report.covered, 2)


def test_condition_records_are_parsed() raises:
    var entries = parse_manifest(String("C math/v 7 1\n"))
    assert_equal(len(entries), 1)
    assert_true(entries[0].is_branch)
    assert_equal(entries[0].condition_index, 1)
    assert_equal(entries[0].id(), String("math/v:7.1"))


def test_decision_and_line_records_carry_no_condition_index() raises:
    var entries = parse_manifest(String("L m 1\nB m 2\n"))
    assert_equal(entries[0].condition_index, -1)
    assert_equal(entries[1].condition_index, -1)
    assert_equal(entries[1].id(), String("m:2"))


def test_condition_record_with_wrong_field_count_is_rejected() raises:
    var raised = False
    try:
        _ = parse_manifest(String("C m 7\n"))
    except e:
        raised = True
    assert_true(raised)


def test_unknown_record_kind_is_rejected() raises:
    var raised = False
    try:
        _ = parse_manifest(String("X m 7\n"))
    except e:
        raised = True
    assert_true(raised)


def test_each_condition_counts_as_two_items() raises:
    var report = build_report(
        parse_manifest(String("B m 2\nC m 2 0\nC m 2 1\n")),
        parse_hits(String("")),
        parse_traces(String("")),
    )
    # One decision plus two operands, each needing True and False.
    assert_equal(report.total, 6)


def test_uncovered_condition_is_named_with_its_index() raises:
    var text = report_for(String("C m 2 1\n"), String("COVBRANCH:m:2.1:T\n"))
    assert_true("line 2 condition 1: never evaluated False" in text)


def test_a_covered_condition_is_not_flagged() raises:
    var text = report_for(
        String("C m 2 0\n"), String("COVBRANCH:m:2.0:T\nCOVBRANCH:m:2.0:F\n")
    )
    assert_true("never evaluated" not in text)


def test_decision_and_its_conditions_are_tracked_independently() raises:
    # The decision took both outcomes, but operand 1 never evaluated False.
    var manifest = String("B m 2\nC m 2 0\nC m 2 1\n")
    var stderr = String(
        "COVBRANCH:m:2:T\nCOVBRANCH:m:2:F\n"
        "COVBRANCH:m:2.0:T\nCOVBRANCH:m:2.0:F\n"
        "COVBRANCH:m:2.1:T\n"
    )
    var report = build_report(
        parse_manifest(manifest), parse_hits(stderr), parse_traces(stderr)
    )
    assert_equal(report.covered, 5)
    assert_equal(report.total, 6)
    assert_true("line 2 condition 1: never evaluated False" in report.text)
    assert_true("line 2: decision" not in report.text)


def test_empty_manifest_is_vacuously_complete() raises:
    var report = build_report(
        parse_manifest(String("")),
        parse_hits(String("")),
        parse_traces(String("")),
    )
    assert_true(report.is_complete())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
