# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact terminal ordering strengthens unchanged segment dominance."""

from extensions.carla.curve_interval import _next_down, _next_up
from extensions.carla.lane_refinement import (
    _ClosedInterval,
    _exact_lane_certificate,
    _lane_certificate_dominates,
    _lane_certificate_dominates_cells,
    _refine_lane_certificate,
)
from tests.test_carla_cross_candidate_certificates import _sampled_road
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def test_inexact_witness_can_dominate_an_exact_competitor() raises:
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    for scale in [Float64(1e-200), Float64(1.0), Float64(1e200)]:
        var one = _exact_lane_certificate(0.4, [scale, 0.0, 0.0], query, 3, 5)
        one.exact_witness = False
        var two = _exact_lane_certificate(
            0.6, [2.0 * scale, 0.0, 0.0], query, 7, 11
        )
        assert_true(_lane_certificate_dominates_cells(one, 4, two, 1, query))
        assert_false(_lane_certificate_dominates_cells(two, 1, one, 4, query))
        assert_equal(one.nodes, 3)
        assert_equal(one.terms, 5)
        assert_equal(two.nodes, 7)
        assert_equal(two.terms, 11)
        two = _exact_lane_certificate(0.6, [scale, 0.0, 0.0], query, 7, 11)
        assert_true(_lane_certificate_dominates_cells(one, 0, two, 1, query))
        assert_false(_lane_certificate_dominates_cells(one, 2, two, 1, query))


def test_mixed_cover_uses_exact_terminal_order_and_every_open_bound() raises:
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var one = _exact_lane_certificate(0.4, [1.5, 0.0, 0.0], query, 3, 5)
    one.exact_witness = False
    var two = _exact_lane_certificate(0.6, [1.75, 0.0, 0.0], query, 7, 11)
    two.exact_witness = False
    # These synthetic certificates satisfy the producer invariant: terminal
    # points are no closer than two.point. Their lower score may be loose.
    two.lower = 0.0
    two.cells.clear()
    two.cells.append(_ClosedInterval(0.6, 0.6, 2, 0.0, two.scale))
    two.cells.append(_ClosedInterval(0.7, 0.8, 2, 3.0, two.scale))
    assert_false(_lane_certificate_dominates(one, 0, two, 1, query))
    assert_true(_lane_certificate_dominates_cells(one, 0, two, 1, query))
    two.cells[1].lower = 2.0
    assert_false(_lane_certificate_dominates_cells(one, 0, two, 1, query))
    two.cells[1].lower = one.upper
    assert_true(_lane_certificate_dominates_cells(one, 0, two, 1, query))
    assert_false(_lane_certificate_dominates_cells(one, 2, two, 1, query))
    two.cells[1].scale = 0.5
    two.cells[1].lower = 4.0 * one.upper
    # Downward rebasing must not manufacture equality dominance.
    assert_false(_lane_certificate_dominates_cells(one, 0, two, 1, query))
    two.cells.clear()
    assert_false(_lane_certificate_dominates_cells(one, 0, two, 1, query))


def test_exactly_worse_discrete_points_are_not_possible_minimizers() raises:
    var road = _sampled_road(1.0)
    var low = Float64(0.5)
    var high = _next_up(low)
    var certificate = _refine_lane_certificate(
        road, 0, 0, low, high, Vector3(0, 0, 0), low, 0.0
    )
    assert_true(certificate.exact_witness)
    assert_equal(certificate.s, low)
    for cell in certificate.cells:
        assert_equal(cell.low, low)
        assert_equal(cell.high, low)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
