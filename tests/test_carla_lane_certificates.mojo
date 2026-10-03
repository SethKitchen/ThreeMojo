# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Controls for enclosure admission, expansion branches, and exact budgets."""

from extensions.carla.curve_bounds import _lane_jet, _scaled_point_distance_jet
from extensions.carla.curve_distance import _normalized_square, _point_gap_scale
from extensions.carla.curve_interval import _Interval
from extensions.carla.geometry import LINE, PARAM_POLY3, RoadGeometry, _Sample
from extensions.carla.lane_refinement import (
    _chord_certificate,
    _expansion_center,
    _global_lower,
    _lane_box_can_improve,
    _midpoint,
    _scaled_accuracy,
    _whole_lane_box,
    _certificate_within_gap,
    _ClosedInterval,
    _ClosedIntervals,
    _rebase_lower,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    LANE_DRIVING,
    LaneId,
    NO_JUNCTION,
    RoadId,
    RoadInfoElevation,
    RoadInfoGeometry,
    RoadInfoLaneOffset,
    RoadInfoLaneWidth,
    SectionId,
)
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def _road(var geometry: RoadGeometry) raises -> Road:
    var road = Road(
        RoadId(1), "certificate", 1.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(0.0, CubicPolynomial.constant(2.0))
    )
    road.info.geometries.append(RoadInfoGeometry(0.0, geometry^))
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial.constant(0.0))
    )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(0.0, CubicPolynomial.constant(1.0))
    )
    return road^


def test_expansion_uses_the_same_interior_clamp_branch() raises:
    var road = _road(RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 1.0))
    var query = Vector3(0.25, 0, 0)
    var domain = _scaled_point_distance_jet(
        _lane_jet(road, 0, 0, 0, 1), query, 0.25
    )
    var endpoint = _scaled_point_distance_jet(
        _lane_jet(road, 0, 0, 0, 0), query, 0.25
    )
    # This deliberately mismatched endpoint jet demonstrates why it must not
    # supply a derivative for the smooth interior domain.
    assert_equal(endpoint.first.low, 0.0)
    assert_true(_global_lower(domain, endpoint, _Interval(0, 1)) > 0.5)
    var center_s = _expansion_center(0, 1, 0)
    assert_equal(center_s, 0.5)
    assert_equal(_expansion_center(0, 1, 1), 0.5)
    assert_equal(_expansion_center(0, 1, 0.25), 0.25)
    var center = _scaled_point_distance_jet(
        _lane_jet(road, 0, 0, center_s, center_s), query, 0.25
    )
    assert_true(_global_lower(domain, center, _Interval(-0.5, 0.5)) <= 0.0)
    assert_equal(road._lane_distance_squared(0, 0, 0.25, query), 0.0)


def test_normalization_does_not_enlarge_the_acceptance_budget() raises:
    var road = _road(RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 1.0))
    var point: Array[Float64, 3] = [3.0, 0.0, 0.0]
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var scale = _point_gap_scale(point, query)
    assert_equal(scale, 2.0)
    var lower = _normalized_square[3](point, query, scale).low
    assert_equal(bitcast[DType.uint64](lower), UInt64(0x4001FFFFFFFFFFFE))
    var budget = _scaled_accuracy(road, 0, 0, 0, 1, 0.5, lower, scale)
    assert_equal(bitcast[DType.uint64](budget), UInt64(0x3D51FFFFFFFFFFFC))
    var ideal_world = bitcast[DType.float64](UInt64(0x3D72000000000000))
    assert_true(budget * 4.0 <= ideal_world)


def test_finite_parameter_midpoint_avoids_span_overflow() raises:
    var limit = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    var eta = bitcast[DType.float64](UInt64(1))
    assert_equal(_midpoint(-limit, limit), 0.0)
    assert_equal(_midpoint(0.0, 1.0), 0.5)
    assert_equal(_midpoint(eta, 2.0 * eta), eta)


def test_full_sampled_box_is_cached_without_quarter_point_assumptions() raises:
    var geometry = RoadGeometry(PARAM_POLY3, 0.0, 0.0, 0.0, 0.0, 1.0)
    for s in [0.0, 0.25, 0.5, 0.75, 1.0]:
        geometry.samples.append(_Sample(2.0 * s - 1.0, 2.0, s, 1.0, 0.0))
    var road = _road(geometry^)
    var certificate = _chord_certificate(
        road, 0, 0, 0, 1, Vector3(-1, -2, 0), Vector3(1, -2, 0)
    )
    var box = certificate[1]
    assert_true(box[0].is_finite())
    assert_true(box[1].is_finite())
    assert_true(box[2].is_finite())
    for i in range(101):
        var center = road._lane_center(0, 0, Float64(i) / 100.0)
        assert_true(box[0].contains(center[0]))
        assert_true(box[1].contains(center[1]))
        assert_true(box[2].contains(center[2]))
    var best: Array[Float64, 3] = [4.0, 0.0, 0.0]
    assert_false(_lane_box_can_improve(box, Vector3(5, 0, 0), best))
    var zero: Array[Float64, 3] = [0.0, -2.0, 0.0]
    assert_true(_lane_box_can_improve(box, Vector3(0, -2, 0), zero))


def test_unresolved_enclosure_keeps_the_candidate() raises:
    var road = _road(RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 1.0))
    var certificate = _chord_certificate(
        road, 0, 0, 0, 1, Vector3(0, 0, 0), Vector3(1, 0, 0), max_terms=0
    )
    assert_equal(certificate[0], inf[DType.float64]())
    var best: Array[Float64, 3] = [0.0, 0.0, 0.0]
    assert_true(_lane_box_can_improve(certificate[1], Vector3(0, 0, 0), best))
    assert_true(
        _lane_box_can_improve(_whole_lane_box(), Vector3(1000, 0, 0), best)
    )


def test_lower_certificate_is_rechecked_after_the_budget_shrinks() raises:
    var ulp = Float64(2.220446049250313e-16)
    var lower = 1.0 - 40.0 * ulp
    assert_true(
        _certificate_within_gap(lower, 1.0, 1.0, 1.0 + 16.0 * ulp, 64.0 * ulp)
    )
    assert_false(
        _certificate_within_gap(lower, 1.0, 1.0, 1.0 - 0.5 * ulp, 32.0 * ulp)
    )


def test_enclosure_budget_includes_subdivision_and_endpoint_terms() raises:
    var geometry = RoadGeometry(PARAM_POLY3, 0.0, 0.0, 0.0, 0.0, 1.0)
    for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
        geometry.samples.append(_Sample(t, 0.0, t, 1.0, 0.0))
    var sampled = _road(geometry^)
    var unresolved = _chord_certificate(
        sampled, 0, 0, 0, 1, Vector3(0, 0, 0), Vector3(1, 0, 0), max_terms=3
    )
    assert_equal(unresolved[2], 3)
    assert_equal(unresolved[0], inf[DType.float64]())
    var line = _road(RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 1.0))
    var before_endpoints = _chord_certificate(
        line, 0, 0, 0, 1, Vector3(0, 0, 0), Vector3(1, 0, 0), max_terms=2
    )
    var with_endpoints = _chord_certificate(
        line, 0, 0, 0, 1, Vector3(0, 0, 0), Vector3(1, 0, 0), max_terms=3
    )
    assert_equal(before_endpoints[2], 1)
    assert_equal(with_endpoints[2], 3)
    var limit = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    var extreme = _road(RoadGeometry(LINE, 0.0, limit, 0.0, 0.0, 1.0))
    assert_equal(extreme._lane_center(0, 0, 0.0)[0], limit)
    assert_equal(extreme._lane_center(0, 0, 1.0)[0], limit)
    var limited = _chord_certificate(
        extreme, 0, 0, 0, 1, Vector3(0, 0, 0), Vector3(1, 0, 0), max_terms=3
    )
    assert_equal(limited[2], 3)
    assert_equal(limited[0], inf[DType.float64]())


def test_saved_lower_bounds_rebase_conservatively_across_scales() raises:
    var ulp = Float64(2.220446049250313e-16)
    assert_true(_certificate_within_gap(1.0, 2.0, 1.0, 4.0, 8.0 * ulp))
    assert_false(_certificate_within_gap(1.0, 2.0, 1.0, 5.0, 0.5))
    assert_true(_certificate_within_gap(1.0, 1.0, 2.0, 0.25, 8.0 * ulp))
    var eta = bitcast[DType.float64](UInt64(1))
    var limit = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    assert_equal(_rebase_lower(1.0, eta, limit), 0.0)
    assert_false(_certificate_within_gap(1.0, eta, limit, 1.0, 0.0))
    assert_true(_certificate_within_gap(1.0, limit, eta, 1.0, 0.0))
    assert_false(_certificate_within_gap(0.0, limit, eta, 1.0, 0.0))


def test_closed_interval_list_reopens_and_resets_the_actual_prefix() raises:
    var ulp = Float64(2.220446049250313e-16)
    var closed = _ClosedIntervals()
    closed.add(_ClosedInterval(0.0, 0.25, 2, 1.0 - 40.0 * ulp, 1.0))
    closed.add(_ClosedInterval(0.25, 0.5, 2, 1.0, 1.0))
    assert_true(closed.needs_validation())
    assert_false(Bool(closed.recheck(1.0, 1.0 + 16.0 * ulp, 64.0 * ulp)))
    assert_false(Bool(closed.recheck(1.0, 1.0 + 16.0 * ulp, 64.0 * ulp)))
    assert_false(closed.needs_validation())
    closed.reset()
    var reopened = closed.recheck(1.0, 1.0 - 0.5 * ulp, 32.0 * ulp)
    assert_true(Bool(reopened))
    assert_equal(reopened.value()[0], 0.0)
    assert_equal(reopened.value()[1], 0.25)
    assert_equal(reopened.value()[2], 2)
    assert_equal(len(closed.values), 1)
    assert_equal(closed.validated, 0)
    assert_false(Bool(closed.recheck(1.0, 1.0 - 0.5 * ulp, 32.0 * ulp)))
    assert_false(closed.needs_validation())
    closed.add(_ClosedInterval(0.0, 0.25, 3, 1.0 - ulp, 1.0))
    assert_true(closed.needs_validation())
    assert_false(Bool(closed.recheck(1.0, 1.0 - 0.5 * ulp, 32.0 * ulp)))
    assert_false(closed.needs_validation())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
