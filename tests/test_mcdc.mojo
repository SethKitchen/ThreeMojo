# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `coverage.mcdc`."""

from coverage.mcdc import (
    DecisionTrace,
    Evaluation,
    MASKED,
    find_trace,
    is_mcdc_covered,
    parse_traces,
    split_last,
)
from std.testing import TestSuite, assert_equal, assert_false, assert_true

# `a and b`, evaluated every way the operator allows.
comptime BOTH_TRUE = "COVBRANCH:m:4.0:T\nCOVBRANCH:m:4.1:T\nCOVBRANCH:m:4:T\n"
comptime FIRST_FALSE = "COVBRANCH:m:4.0:F\nCOVBRANCH:m:4:F\n"
comptime SECOND_FALSE = (
    "COVBRANCH:m:4.0:T\nCOVBRANCH:m:4.1:F\nCOVBRANCH:m:4:F\n"
)


def trace_of(stream: String) raises -> DecisionTrace:
    """Return the single decision trace parsed from `stream`.

    Args:
        stream: Captured probe records for exactly one decision.

    Returns:
        That decision's trace.

    Raises:
        Error: If the stream holds no decision.
    """
    var traces = parse_traces(stream)
    if len(traces) == 0:
        raise Error("no decision found in stream")
    return traces[0].copy()


def test_split_last_separates_base_from_suffix() raises:
    var parts = split_last(String("m:4.0"), String("."))
    assert_equal(len(parts), 2)
    assert_equal(parts[0], String("m:4"))
    assert_equal(parts[1], String("0"))


def test_split_last_returns_one_part_when_absent() raises:
    var parts = split_last(String("m:4"), String("."))
    assert_equal(len(parts), 1)
    assert_equal(parts[0], String("m:4"))


def test_split_last_splits_at_the_final_separator() raises:
    var parts = split_last(String("a.b.c"), String("."))
    assert_equal(parts[0], String("a.b"))
    assert_equal(parts[1], String("c"))


def test_a_full_evaluation_records_every_operand() raises:
    var trace = trace_of(String(BOTH_TRUE))
    assert_equal(len(trace.evaluations), 1)
    assert_equal(trace.evaluations[0].values, [1, 1])
    assert_true(trace.evaluations[0].outcome)


def test_short_circuited_operand_is_masked() raises:
    var trace = trace_of(String(FIRST_FALSE))
    # The second operand never ran, so it must not read as False.
    assert_equal(trace.evaluations[0].value(1), MASKED)
    assert_equal(trace.evaluations[0].value(0), 0)


def test_repeated_identical_evaluations_are_collapsed() raises:
    var trace = trace_of(String(BOTH_TRUE) + String(BOTH_TRUE))
    assert_equal(len(trace.evaluations), 1)


def test_distinct_evaluations_are_all_kept() raises:
    var trace = trace_of(
        String(BOTH_TRUE) + String(FIRST_FALSE) + String(SECOND_FALSE)
    )
    assert_equal(len(trace.evaluations), 3)


def test_one_evaluation_proves_nothing() raises:
    var trace = trace_of(String(BOTH_TRUE))
    assert_false(is_mcdc_covered(trace, 0))
    assert_false(is_mcdc_covered(trace, 1))


def test_condition_coverage_without_mcdc_for_the_second_operand() raises:
    # Both operands are seen True and False, satisfying condition coverage,
    # but operand 1 never varies while operand 0 is held fixed.
    var trace = trace_of(String(BOTH_TRUE) + String(FIRST_FALSE))
    assert_true(is_mcdc_covered(trace, 0))
    assert_false(is_mcdc_covered(trace, 1))


def test_adding_the_third_case_completes_mcdc() raises:
    var trace = trace_of(
        String(BOTH_TRUE) + String(FIRST_FALSE) + String(SECOND_FALSE)
    )
    assert_true(is_mcdc_covered(trace, 0))
    assert_true(is_mcdc_covered(trace, 1))


def test_pair_needs_differing_outcomes() raises:
    # Operand 1 flips, but the decision stays False both times.
    var stream = String(
        "COVBRANCH:m:4.0:F\nCOVBRANCH:m:4.1:T\nCOVBRANCH:m:4:F\n"
        "COVBRANCH:m:4.0:F\nCOVBRANCH:m:4.1:F\nCOVBRANCH:m:4:F\n"
    )
    assert_false(is_mcdc_covered(trace_of(stream), 1))


def test_pair_needs_other_conditions_held_still() raises:
    # Both operands flip together, so neither is shown to act alone.
    var stream = String(
        "COVBRANCH:m:4.0:T\nCOVBRANCH:m:4.1:T\nCOVBRANCH:m:4:T\n"
        "COVBRANCH:m:4.0:F\nCOVBRANCH:m:4.1:F\nCOVBRANCH:m:4:F\n"
    )
    var trace = trace_of(stream)
    assert_false(is_mcdc_covered(trace, 0))
    assert_false(is_mcdc_covered(trace, 1))


def test_or_decision_reaches_mcdc() raises:
    # `a or b`: True short-circuits, so the three reachable vectors are
    # [T,-]->T, [F,T]->T and [F,F]->F.
    var stream = String(
        "COVBRANCH:m:9.0:T\nCOVBRANCH:m:9:T\n"
        "COVBRANCH:m:9.0:F\nCOVBRANCH:m:9.1:T\nCOVBRANCH:m:9:T\n"
        "COVBRANCH:m:9.0:F\nCOVBRANCH:m:9.1:F\nCOVBRANCH:m:9:F\n"
    )
    var trace = trace_of(stream)
    assert_true(is_mcdc_covered(trace, 0))
    assert_true(is_mcdc_covered(trace, 1))


def test_three_operand_decision() raises:
    # `a and b and c` with each operand shown to swing the result.
    var stream = String(
        "COVBRANCH:m:7.0:T\nCOVBRANCH:m:7.1:T\nCOVBRANCH:m:7.2:T\n"
        "COVBRANCH:m:7:T\n"
        "COVBRANCH:m:7.0:F\nCOVBRANCH:m:7:F\n"
        "COVBRANCH:m:7.0:T\nCOVBRANCH:m:7.1:F\nCOVBRANCH:m:7:F\n"
        "COVBRANCH:m:7.0:T\nCOVBRANCH:m:7.1:T\nCOVBRANCH:m:7.2:F\n"
        "COVBRANCH:m:7:F\n"
    )
    var trace = trace_of(stream)
    assert_true(is_mcdc_covered(trace, 0))
    assert_true(is_mcdc_covered(trace, 1))
    assert_true(is_mcdc_covered(trace, 2))


def test_full_condition_coverage_can_still_miss_mcdc() raises:
    # `a and b or c`, i.e. (a and b) or c. Every operand is seen both True and
    # False, so condition coverage is complete -- yet operand 1 never changes
    # the outcome while the others are held still, because the only time it is
    # False, operand 2 rescues the decision.
    var stream = String(
        "COVBRANCH:m:5.0:T\nCOVBRANCH:m:5.1:T\nCOVBRANCH:m:5:T\n"
        "COVBRANCH:m:5.0:T\nCOVBRANCH:m:5.1:F\nCOVBRANCH:m:5.2:T\n"
        "COVBRANCH:m:5:T\n"
        "COVBRANCH:m:5.0:F\nCOVBRANCH:m:5.2:F\nCOVBRANCH:m:5:F\n"
        "COVBRANCH:m:5.0:F\nCOVBRANCH:m:5.2:T\nCOVBRANCH:m:5:T\n"
    )
    var trace = trace_of(stream)

    # Condition coverage is satisfied: every operand took both values.
    for index in range(3):
        var saw_true = False
        var saw_false = False
        for evaluation in trace.evaluations:
            if evaluation.value(index) == 1:
                saw_true = True
            elif evaluation.value(index) == 0:
                saw_false = True
        assert_true(saw_true)
        assert_true(saw_false)

    # MC-DC is not: operand 1 has no independence pair.
    assert_true(is_mcdc_covered(trace, 0))
    assert_false(is_mcdc_covered(trace, 1))
    assert_true(is_mcdc_covered(trace, 2))


def test_separate_decisions_get_separate_traces() raises:
    var traces = parse_traces(
        String(BOTH_TRUE + "COVBRANCH:m:9.0:T\nCOVBRANCH:m:9:T\n")
    )
    assert_equal(len(traces), 2)
    assert_equal(traces[0].id, String("m:4"))
    assert_equal(traces[1].id, String("m:9"))


def test_interleaved_nested_decision_does_not_corrupt_the_outer_vector() raises:
    # A nested decision inside an operand fires its own records first.
    var stream = String(
        "COVBRANCH:m:9.0:T\nCOVBRANCH:m:9:T\n"
        "COVBRANCH:m:4.0:T\nCOVBRANCH:m:4.1:T\nCOVBRANCH:m:4:T\n"
    )
    var traces = parse_traces(stream)
    var outer = find_trace(traces, String("m:4"))
    assert_true(outer >= 0)
    assert_equal(traces[outer].evaluations[0].values, [1, 1])


def test_reentrant_evaluation_closes_the_inner_vector_first() raises:
    # Recursion: the inner call completes before the outer one does.
    var stream = String(
        "COVBRANCH:m:4.0:F\nCOVBRANCH:m:4:F\n"
        "COVBRANCH:m:4.0:T\nCOVBRANCH:m:4.1:T\nCOVBRANCH:m:4:T\n"
    )
    var trace = trace_of(stream)
    assert_equal(len(trace.evaluations), 2)
    assert_equal(trace.evaluations[0].value(1), MASKED)
    assert_equal(trace.evaluations[1].values, [1, 1])


def test_line_records_are_ignored() raises:
    var traces = parse_traces(String("COVLINE:m:4\n" + BOTH_TRUE))
    assert_equal(len(traces), 1)


def test_malformed_branch_record_is_rejected() raises:
    var raised = False
    try:
        _ = parse_traces(String("COVBRANCH:nocolonflag\n"))
    except e:
        raised = True
    assert_true(raised)


def test_find_trace_reports_a_missing_decision() raises:
    assert_equal(
        find_trace(parse_traces(String(BOTH_TRUE)), String("m:99")), -1
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
