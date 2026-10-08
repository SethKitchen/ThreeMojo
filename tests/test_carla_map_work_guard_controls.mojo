# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Mutable ledger validation, refusal atomicity and signed fee controls."""
from extensions.carla.map_search import (
    MapBuildBudget,
    MapQueryBudget,
    _MapBuildWork,
    _MapQueryWork,
)
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def test_mapbuildbudget_rejects_each_mutated_negative_limit() raises:
    var value0 = MapBuildBudget()
    value0.validate()
    value0.max_segments = -1
    with assert_raises(contains="nonnegative"):
        value0.validate()
    var value1 = MapBuildBudget()
    value1.validate()
    value1.max_steps = -1
    with assert_raises(contains="nonnegative"):
        value1.validate()
    var value2 = MapBuildBudget()
    value2.validate()
    value2.max_terms = -1
    with assert_raises(contains="nonnegative"):
        value2.validate()
    var value3 = MapBuildBudget()
    value3.validate()
    value3.max_records = -1
    with assert_raises(contains="nonnegative"):
        value3.validate()


def test_mapquerybudget_rejects_each_mutated_negative_limit() raises:
    var value0 = MapQueryBudget()
    value0.validate()
    value0.max_candidates = -1
    with assert_raises(contains="nonnegative"):
        value0.validate()
    var value1 = MapQueryBudget()
    value1.validate()
    value1.max_nodes = -1
    with assert_raises(contains="nonnegative"):
        value1.validate()
    var value2 = MapQueryBudget()
    value2.validate()
    value2.max_terms = -1
    with assert_raises(contains="nonnegative"):
        value2.validate()
    var value3 = MapQueryBudget()
    value3.validate()
    value3.max_index_pops = -1
    with assert_raises(contains="nonnegative"):
        value3.validate()
    var value4 = MapQueryBudget()
    value4.validate()
    value4.max_queue_entries = -1
    with assert_raises(contains="nonnegative"):
        value4.validate()
    var value5 = MapQueryBudget()
    value5.validate()
    value5.max_steps = -1
    with assert_raises(contains="nonnegative"):
        value5.validate()


def test_mapbuildwork_rejects_each_mutated_counter() raises:
    for invalid0 in [-1, 3]:
        var value0 = _MapBuildWork(MapBuildBudget(2, 2, 2, 2))
        value0.validate()
        value0.segments = invalid0
        with assert_raises(contains="invalid consumed work"):
            value0.validate()
    for invalid1 in [-1, 3]:
        var value1 = _MapBuildWork(MapBuildBudget(2, 2, 2, 2))
        value1.validate()
        value1.steps = invalid1
        with assert_raises(contains="invalid consumed work"):
            value1.validate()
    for invalid2 in [-1, 3]:
        var value2 = _MapBuildWork(MapBuildBudget(2, 2, 2, 2))
        value2.validate()
        value2.terms = invalid2
        with assert_raises(contains="invalid consumed work"):
            value2.validate()
    for invalid3 in [-1, 3]:
        var value3 = _MapBuildWork(MapBuildBudget(2, 2, 2, 2))
        value3.validate()
        value3.records = invalid3
        with assert_raises(contains="invalid consumed work"):
            value3.validate()


def test_mapquerywork_rejects_each_mutated_counter() raises:
    for invalid0 in [-1, 3]:
        var value0 = _MapQueryWork(MapQueryBudget(2, 2, 2, 2, 2, 2))
        value0.validate()
        value0.steps = invalid0
        with assert_raises(contains="invalid consumed work"):
            value0.validate()
    for invalid1 in [-1, 3]:
        var value1 = _MapQueryWork(MapQueryBudget(2, 2, 2, 2, 2, 2))
        value1.validate()
        value1.candidates = invalid1
        with assert_raises(contains="invalid consumed work"):
            value1.validate()
    for invalid2 in [-1, 3]:
        var value2 = _MapQueryWork(MapQueryBudget(2, 2, 2, 2, 2, 2))
        value2.validate()
        value2.nodes = invalid2
        with assert_raises(contains="invalid consumed work"):
            value2.validate()
    for invalid3 in [-1, 3]:
        var value3 = _MapQueryWork(MapQueryBudget(2, 2, 2, 2, 2, 2))
        value3.validate()
        value3.terms = invalid3
        with assert_raises(contains="invalid consumed work"):
            value3.validate()
    for invalid4 in [-1, 3]:
        var value4 = _MapQueryWork(MapQueryBudget(2, 2, 2, 2, 2, 2))
        value4.validate()
        value4.index_pops = invalid4
        with assert_raises(contains="invalid consumed work"):
            value4.validate()
    for invalid5 in [-1, 3]:
        var value5 = _MapQueryWork(MapQueryBudget(2, 2, 2, 2, 2, 2))
        value5.validate()
        value5.peak_queue_entries = invalid5
        with assert_raises(contains="invalid consumed work"):
            value5.validate()


def test_query_step_limits_validate_each_independent_bound() raises:
    var work = _MapQueryWork(MapQueryBudget(2, 2, 2, 2, 2, 2))
    work.max_total_steps = -1
    with assert_raises(contains="invalid consumed work"):
        work.validate()
    work.max_total_steps = 3
    work.steps = 3
    with assert_raises(contains="invalid consumed work"):
        work.validate()
    work.steps = 2
    work.validate()


def test_build_negative_fees_poison_without_spending() raises:
    var step_work = _MapBuildWork(MapBuildBudget())
    step_work.step(0)
    with assert_raises(contains="step budget"):
        step_work.step(-1)
    assert_equal(step_work.steps, 0)
    assert_true(step_work.exhausted)
    var term_work = _MapBuildWork(MapBuildBudget())
    term_work.term(0)
    with assert_raises(contains="term budget"):
        term_work.term(-1)
    assert_equal(term_work.terms, 0)
    assert_true(term_work.exhausted)
    var record_work = _MapBuildWork(MapBuildBudget())
    record_work.record(0)
    with assert_raises(contains="record budget"):
        record_work.record(-1)
    assert_equal(record_work.records, 0)
    assert_true(record_work.exhausted)


def test_build_product_checks_both_signed_factors_before_multiply() raises:
    for axis in [0, 1]:
        var work = _MapBuildWork(MapBuildBudget())
        work.step_product(0, 0)
        with assert_raises(contains="nonnegative work factors"):
            work.step_product(-1 if axis == 0 else 1, -1 if axis == 1 else 1)
        assert_equal(work.steps, 0)
        assert_true(work.exhausted)
    var exact = _MapBuildWork(MapBuildBudget(0, max_steps=6))
    exact.step_product(2, 3)
    assert_equal(exact.steps, 6)


def test_query_negative_fees_and_queue_residents_fail_closed() raises:
    var work = _MapQueryWork(MapQueryBudget())
    work._step(0)
    with assert_raises(contains="step budget"):
        work._step(-1)
    assert_equal(work.steps, 0)
    assert_true(work.exhausted)
    var positive_queue = _MapQueryWork(MapQueryBudget())
    positive_queue.queue_push(0)
    assert_equal(positive_queue.peak_queue_entries, 1)
    var queue = _MapQueryWork(MapQueryBudget())
    with assert_raises(contains="queue budget"):
        queue.queue_push(-1)
    assert_equal(queue.peak_queue_entries, 0)
    assert_equal(queue.steps, 0)
    assert_true(queue.exhausted)


def test_query_product_checks_signs_zero_and_exact_room() raises:
    for axis in [0, 1]:
        var work = _MapQueryWork(MapQueryBudget())
        with assert_raises(contains="step budget"):
            work._step_product(-1 if axis == 0 else 1, -1 if axis == 1 else 1)
        assert_equal(work.steps, 0)
        assert_true(work.exhausted)
    var exact = _MapQueryWork(MapQueryBudget(0, max_steps=6))
    exact._step_product(9223372036854775807, 0)
    assert_equal(exact.steps, 0)
    exact._step_product(2, 3)
    assert_equal(exact.steps, 6)
    var overflow = _MapQueryWork(MapQueryBudget(0, max_steps=6))
    with assert_raises(contains="step budget"):
        overflow._step_product(9223372036854775807, 1)
    assert_equal(overflow.steps, 0)
    assert_true(overflow.exhausted)


def test_query_caps_reject_invalid_prior_work_and_nonpositive_price() raises:
    var work = _MapQueryWork(MapQueryBudget())
    for nodes in [-1, 16385]:
        with assert_raises(contains="invalid consumed node work"):
            _ = work.node_cap(nodes)
    with assert_raises(contains="invalid consumed node work"):
        _ = work.node_cap(0, 0)
    for terms in [-1, 2000001]:
        with assert_raises(contains="invalid consumed term work"):
            _ = work.term_cap(terms)
    assert_equal(work.node_cap(0), 16384)
    assert_equal(work.term_cap(0), 2000000)
    assert_equal(work.steps, 0)


def test_query_charge_rejects_each_negative_or_zero_fee_atomically() raises:
    var negative_nodes = _MapQueryWork(MapQueryBudget())
    with assert_raises(contains="node budget"):
        negative_nodes.charge(-1, 0)
    assert_equal(negative_nodes.nodes, 0)
    assert_equal(negative_nodes.terms, 0)
    assert_true(negative_nodes.exhausted)
    var negative_terms = _MapQueryWork(MapQueryBudget())
    with assert_raises(contains="term budget"):
        negative_terms.charge(0, -1)
    assert_equal(negative_terms.nodes, 0)
    assert_equal(negative_terms.terms, 0)
    assert_true(negative_terms.exhausted)
    var invalid_price = _MapQueryWork(MapQueryBudget())
    with assert_raises(contains="step cost must be positive"):
        invalid_price.charge(0, 0, 0)
    assert_equal(invalid_price.nodes, 0)
    assert_equal(invalid_price.terms, 0)
    assert_equal(invalid_price.steps, 0)
    assert_true(invalid_price.exhausted)
    var valid = _MapQueryWork(MapQueryBudget())
    valid.charge(1, 2, 3)
    assert_equal(valid.nodes, 1)
    assert_equal(valid.terms, 2)
    assert_equal(valid.steps, 3)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
