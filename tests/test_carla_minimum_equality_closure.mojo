# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact minimum closure at equal outward value bounds."""

from extensions.carla.curve_interval import _next_down, _next_up
from extensions.carla.lane_distance import _refinement_square
from extensions.carla.lane_refinement import (
    _ClosedInterval,
    _ClosedIntervals,
    _exact_lane_certificate,
    _finish_lane_certificate,
    _lane_certificate_dominates,
)
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def test_equal_nonterminal_bound_proves_incumbent_without_changing_station() raises:
    var point: Array[Float64, 3] = [2.0, 0.0, 0.0]
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var upper = _refinement_square[3](point, query, 2.0).high
    assert_equal(upper, 1.0)  # Exact rational square: 2^2 / 2^2.
    var closed = _ClosedIntervals()
    closed.add(_ClosedInterval(0.0, 1.0, 3, upper, 2.0))
    var terminal: List[_ClosedInterval] = [
        _ClosedInterval(0.75, 0.75, 4, _next_down(upper), 2.0)
    ]
    var certificate = _finish_lane_certificate(
        0.75, point, query, closed, terminal, 12, 34
    )
    assert_true(certificate.exact_witness)
    assert_equal(certificate.s, 0.75)
    assert_equal(len(certificate.cells), 2)
    assert_equal(certificate.cells[0].low, 0.0)
    assert_equal(certificate.cells[0].high, 1.0)
    assert_equal(certificate.nodes, 12)
    assert_equal(certificate.terms, 34)
    var earlier = _exact_lane_certificate(0.25, point, query, 1, 1)
    assert_true(_lane_certificate_dominates(earlier, 0, certificate, 1, query))
    assert_false(_lane_certificate_dominates(certificate, 1, earlier, 0, query))


def test_nonterminal_bound_below_upper_is_not_an_exact_minimum() raises:
    var point: Array[Float64, 3] = [2.0, 0.0, 0.0]
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var upper = _refinement_square[3](point, query, 2.0).high
    for lower in [_next_down(upper), Float64(0.0)]:
        var closed = _ClosedIntervals()
        closed.add(_ClosedInterval(0.0, 1.0, 3, lower, 2.0))
        var certificate = _finish_lane_certificate(
            0.75, point, query, closed, List[_ClosedInterval](), 12, 34
        )
        assert_false(certificate.exact_witness)
        assert_equal(certificate.s, 0.75)
        assert_equal(certificate.lower, lower)


def test_rebased_equal_mathematical_bound_cannot_skip_outward_rounding() raises:
    var point: Array[Float64, 3] = [2.0, 0.0, 0.0]
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var upper = _refinement_square[3](point, query, 2.0).high
    var closed = _ClosedIntervals()
    # In real arithmetic this is the same bound. Outward rebasing loses a
    # small amount, which must keep the cell unresolved rather than round up.
    closed.add(_ClosedInterval(0.0, 1.0, 3, upper * 4.0, 1.0))
    var certificate = _finish_lane_certificate(
        0.75, point, query, closed, List[_ClosedInterval](), 12, 34
    )
    assert_false(certificate.exact_witness)
    assert_true(certificate.lower < upper)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
