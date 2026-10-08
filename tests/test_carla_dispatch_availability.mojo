# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Original cheap exact hits must precede optional dispatch setup work."""

from extensions.carla.lane_refinement import (
    _LaneCertificate,
    _LaneExclusionGoal,
    _resume_lane_certificate,
    _ClosedInterval,
    _ClosedIntervals,
    _run_lane_search,
)
from extensions.carla.curve_interval import _next_up
from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.lane_distance import _point_gap_scale, _refinement_square
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_raises,
)
from tests._sample_dispatch_controls import _dispatch_road
from tests._lazy_taylor_controls import _whole_certificate
from tests.test_carla_cross_candidate_certificates import (
    _road as _external_road,
)


def test_midpoint_exact_hit_keeps_original_four_term_availability() raises:
    var road = _dispatch_road()
    var query = Vector3(1, 0, 1)
    # The old midpoint/edge path costs the seed plus three scalar terms.
    # V2's pre-witness optional setup admitted eight terms at cap11, then
    # exhausted the last two terms before the child could evaluate s=1.
    for depth in [0, 96]:
        for budget in [4, 10, 11, 12]:
            var certificate = _whole_certificate(road, query, 0.9, 1.1, 1.1)
            var pending: List[Tuple[Float64, Float64, Int]] = [(0.9, 1.1, 0)]
            _run_lane_search(
                road,
                0,
                0,
                0.9,
                1.1,
                query,
                certificate,
                pending^,
                _ClosedIntervals(),
                List[_ClosedInterval](),
                None,
                100,
                budget,
                depth,
            )
            assert_true(certificate.exact_witness)
            assert_equal(certificate.s, 1.0)
            assert_equal(certificate.nodes, 1)
            assert_equal(certificate.terms, 4)


def _valley_road(reverse: Bool) raises -> Road:
    var road = _dispatch_road()
    road.info.elevations[0].polynomial = CubicPolynomial.constant(0.0)
    var values: Array[Float64, 4] = [2.0, 0.0, 2.0, 3.0]
    if reverse:
        values = [3.0, 1.0, 0.0, 2.0]
    for i in range(4):
        road.info.geometries[0].geometry.samples[i].u = values[i]
    return road^


def _pause_valley(road: Road, reverse: Bool) raises -> _LaneCertificate:
    var location = Vector3(0, 1, 0)
    var query: Array[Float64, 3] = [0.0, 1.0, 0.0]
    var seed = 2.5 if reverse else 0.5
    var marker = 0.3 if reverse else 0.75
    var other = _external_road()
    var external = other._lane_center(0, 0, marker)
    # Prove the fixture reaches the post-bound dispatch path: none of the
    # original midpoint/endpoints can already beat this actual witness.
    for station in [Float64(0.5), Float64(1.5), Float64(2.5)]:
        var point = road._lane_center(0, 0, station)
        assert_true(_wide_point_order(point, external, query) > 0)
    var certificate = _whole_certificate(road, location, 0.5, 2.5, seed)
    var scale = _point_gap_scale(external, query)
    var goal = _LaneExclusionGoal(
        _refinement_square[3](external, query, scale).high, scale, False
    )
    var pending: List[Tuple[Float64, Float64, Int]] = [(0.5, 2.5, 0)]
    _run_lane_search(
        road,
        0,
        0,
        0.5,
        2.5,
        location,
        certificate,
        pending^,
        _ClosedIntervals(),
        List[_ClosedInterval](),
        None,
        100,
        10000,
        96,
        None,
        goal,
        external.copy(),
    )
    assert_false(certificate.exact_witness)
    assert_true(_wide_point_order(certificate.point, external, query) < 0)
    return certificate^


def test_post_bound_dispatch_yield_keeps_both_child_orders_complete() raises:
    for reverse in [False, True]:
        var road = _valley_road(reverse)
        var certificate = _pause_valley(road, reverse)
        assert_equal(len(certificate.cells), 2)
        var left = False
        var right = False
        for cell in certificate.cells:
            assert_equal(cell.depth, 1)
            if cell.low == 0.5 and cell.high == 1.0:
                left = True
            if cell.low == _next_up(Float64(1.0)) and cell.high == 2.5:
                right = True
        assert_true(left and right)
        if reverse:
            assert_true(certificate.s > 1.0)
        else:
            assert_true(certificate.s < 1.0)
        assert_true(certificate.nodes >= 3 and certificate.nodes <= 100)
        assert_true(certificate.terms >= 21 and certificate.terms <= 10000)


def test_post_bound_frontier_survives_exhaustion_and_resumes_original_owner() raises:
    for reverse in [False, True]:
        var road = _valley_road(reverse)
        var certificate = _pause_valley(road, reverse)
        var nodes = certificate.nodes
        var terms = certificate.terms
        with assert_raises():
            _resume_lane_certificate(
                road,
                0,
                0,
                0.5,
                2.5,
                Vector3(0, 1, 0),
                certificate,
                1.0,
                1.0,
                max_nodes=nodes,
            )
        assert_equal(certificate.nodes, nodes)
        assert_equal(certificate.terms, terms)
        assert_equal(len(certificate.cells), 2)
        _resume_lane_certificate(
            road,
            0,
            0,
            0.5,
            2.5,
            Vector3(0, 1, 0),
            certificate,
            1.0,
            1.0,
            max_nodes=1000,
            max_terms=10000,
        )
        var minimum = 2.0 if reverse else 1.0
        var expected = road._lane_center(0, 0, minimum)
        var query: Array[Float64, 3] = [0.0, 1.0, 0.0]
        assert_equal(_wide_point_order(certificate.point, expected, query), 0)
        var covered = False
        for cell in certificate.cells:
            assert_true(cell.low >= 0.5 and cell.high <= 2.5)
            if cell.low <= minimum and minimum <= cell.high:
                covered = True
        assert_true(covered)
        assert_true(certificate.nodes > nodes)
        assert_true(certificate.terms > terms)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
