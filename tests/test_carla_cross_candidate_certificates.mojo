# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Focused source controls for cross-candidate and strict-cell certificates."""

from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.curve_interval import _Interval, _next_up
from extensions.carla.geometry import LINE, PARAM_POLY3, RoadGeometry, _Sample
from extensions.carla.lane_refinement import (
    _ClosedInterval, _ClosedIntervals, _LaneCertificate,
    _exact_lane_certificate, _finish_lane_certificate,
    _lane_certificate_contains, _lane_certificate_dominates,
    _plan_box_classification, _refine_lane_certificate,
)
from extensions.carla.map import Controller, Junction, Map, Signal
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    LANE_DRIVING, LaneId, NO_JUNCTION, RoadId, RoadInfoElevation,
    RoadInfoGeometry, RoadInfoLaneOffset, RoadInfoLaneWidth, SectionId,
)
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_raises, assert_true


def _road(id: Int = 1, y: Float64 = 0.0, width: Float64 = 2.0) raises -> Road:
    var road = Road(RoadId(id), "certificate", 4.0, NO_JUNCTION, RoadId(0), RoadId(0), True)
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(RoadInfoLaneWidth(0.0, CubicPolynomial.constant(width)))
    road.info.geometries.append(RoadInfoGeometry(0.0, RoadGeometry(LINE, 0.0, 0.0, y, 0.0, 4.0)))
    road.info.elevations.append(RoadInfoElevation(0.0, CubicPolynomial.constant(0.0)))
    road.info.lane_offsets.append(RoadInfoLaneOffset(0.0, CubicPolynomial.constant(width * 0.5)))
    return road^



def _sampled_road(scale: Float64) raises -> Road:
    var road = _road(width=2.0 * scale)
    var geometry = RoadGeometry(PARAM_POLY3, 0.0, 0.0, 0.0, 0.0, 1.0)
    geometry.samples.append(_Sample(-scale, 2.0 * scale, 0.0, 1.0, 0.0))
    geometry.samples.append(_Sample(scale, 2.0 * scale, 1.0, 1.0, 0.0))
    road.length = 1.0
    road.info.geometries[0] = RoadInfoGeometry(0.0, geometry^)
    return road^


def test_general_certificate_exports_cells_and_preserves_extreme_scale_minimum() raises:
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    for scale in [Float64(1e-200), Float64(1e200)]:
        var road = _sampled_road(scale)
        var result = _refine_lane_certificate(road, 0, 0, 0.0, 1.0, Vector3(0, 0, 0), 0.1, 0.0)
        var known = road._lane_center(0, 0, 0.5)
        assert_equal(_wide_point_order(result.point, known, query), 0)
        assert_false(result.exact_witness)
        assert_true(len(result.cells) > 0)
        assert_true(result.lower <= result.upper)
        assert_true(result.nodes <= 16384)
        assert_true(result.terms <= 2000000)


def test_adjacent_float_domain_keeps_discrete_endpoint_cells() raises:
    var road = _sampled_road(1.0)
    var result = _refine_lane_certificate(road, 0, 0, 0.5, _next_up(0.5), Vector3(0, 0, 0), 0.5, 0.0)
    assert_true(result.exact_witness)
    assert_equal(result.s, 0.5)
    assert_true(len(result.cells) > 0)
    for cell in result.cells:
        assert_equal(cell.low, cell.high)
    assert_false(_lane_certificate_contains(road, 0, 0, Vector3(0, 0, 0), result))


def _bounded(
    point: Array[Float64, 3], lower: Float64, upper: Float64,
    scale: Float64 = 1.0, low: Float64 = 0.49, high: Float64 = 0.51,
) -> _LaneCertificate:
    var cells: List[_ClosedInterval] = [_ClosedInterval(low, high, 0, lower, scale)]
    return _LaneCertificate(0.5, point.copy(), scale, lower, upper, False, cells^, 0, 0)


def test_equality_dominance_respects_segment_index() raises:
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var one = _bounded([2.0, 0.0, 0.0], 3.0, 4.0)
    var two = _bounded([2.0, 0.0, 0.0], 4.0, 5.0)
    assert_true(_lane_certificate_dominates(one, 0, two, 1, query))
    assert_false(_lane_certificate_dominates(one, 1, two, 0, query))
    one.point = [1.75, 0.0, 0.0]
    one.upper = 3.5
    assert_true(_lane_certificate_dominates(one, 1, two, 0, query))


def test_sample_order_cannot_resolve_overlapping_minimum_bounds() raises:
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var closer_sample = _bounded([1.0, 0.0, 0.0], 0.5, 1.0)
    var farther_sample = _bounded([1.125, 0.0, 0.0], 0.25, 1.265625)
    assert_false(_lane_certificate_dominates(closer_sample, 0, farther_sample, 1, query))
    assert_false(_lane_certificate_dominates(farther_sample, 1, closer_sample, 0, query))


def test_dominance_rebases_power_of_two_units() raises:
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    # One's upper is 4*2^2=16; two's lower is 2*4^2=32.
    var one = _bounded([4.0, 0.0, 0.0], 3.0, 4.0, scale=2.0)
    var two = _bounded([6.0, 0.0, 0.0], 2.0, 3.0, scale=4.0)
    assert_true(_lane_certificate_dominates(one, 1, two, 0, query))
    assert_false(_lane_certificate_dominates(two, 0, one, 1, query))


def test_exact_witness_order_keeps_underflow_overflow_and_true_ties() raises:
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    for scale in [Float64(1e-200), Float64(1e200)]:
        var one = _exact_lane_certificate(0.0, [scale, 0.0, 0.0], query, 1, 1)
        var two = _exact_lane_certificate(0.0, [2.0 * scale, 0.0, 0.0], query, 1, 1)
        assert_true(_lane_certificate_dominates(one, 1, two, 0, query))
        assert_false(_lane_certificate_dominates(two, 0, one, 1, query))
        assert_true(_lane_certificate_dominates(one, 0, one, 1, query))
        assert_false(_lane_certificate_dominates(one, 1, one, 0, query))


def test_finishing_keeps_closed_and_discrete_minimizer_cells() raises:
    var closed = _ClosedIntervals()
    closed.add(_ClosedInterval(0.0, 0.5, 3, 0.75, 2.0))
    closed.add(_ClosedInterval(0.75, 1.0, 3, 6.0, 1.0))
    var terminal: List[_ClosedInterval] = [_ClosedInterval(0.5, 0.5, 4, 0.875, 2.0)]
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var certificate = _finish_lane_certificate(0.5, [2.0, 0.0, 0.0], query, closed, terminal, 12, 34)
    assert_false(certificate.exact_witness)
    assert_equal(certificate.scale, 2.0)
    assert_equal(certificate.lower, 0.75)
    assert_equal(len(certificate.cells), 2)
    assert_equal(certificate.nodes, 12)
    assert_equal(certificate.terms, 34)


def test_strict_box_sign_requires_positive_width_and_resolves_no_ambiguity() raises:
    assert_true(_plan_box_classification(_Interval(1.0, 2.0), _Interval(-2.0, -1.0)).value())
    assert_false(_plan_box_classification(_Interval(1.0, 2.0), _Interval(0.0, 1.0)).value())
    assert_false(_plan_box_classification(_Interval(-2.0, 0.0), _Interval.whole()).value())
    assert_false(Bool(_plan_box_classification(_Interval(0.0, 1.0), _Interval(-2.0, -1.0))))
    assert_false(Bool(_plan_box_classification(_Interval(1.0, 2.0), _Interval(-1.0, 1.0))))
    assert_false(Bool(_plan_box_classification(_Interval.whole(), _Interval(1.0, 2.0))))


def test_cell_classification_agrees_with_returned_sample() raises:
    var road = _road()
    var location = Vector3(0.5, 0.0, 0.0)
    # A loose valid upper bound retains full-cell fallback coverage.
    var certificate = _bounded([0.5, 0.0, 0.0], 0.0, 10.0)
    assert_true(_lane_certificate_contains(road, 0, 0, location, certificate))
    assert_equal(certificate.nodes, 1)
    assert_equal(certificate.terms, 1)
    # A returned inside sample does not authorize an outside candidate cell.
    certificate = _bounded([0.5, 0.0, 0.0], 0.0, 10.0, low=3.0, high=3.0)
    with assert_raises(contains="disagrees across possible minimizing cells"):
        _ = _lane_certificate_contains(road, 0, 0, location, certificate)


def test_uncertain_boundary_and_exhausted_cells_raise_instead_of_offroad() raises:
    var road = _road()
    var certificate = _bounded([0.5, 0.0, 0.0], 0.9, 1.1)
    with assert_raises(contains="unresolved over a possible minimizing cell"):
        _ = _lane_certificate_contains(road, 0, 0, Vector3(0.5, 1.0, 0.0), certificate)
    # Keep the quadrature-budget assertion on the uncapped fallback.
    certificate = _bounded([0.5, 0.0, 0.0], 0.0, 10.0)
    certificate.nodes = 16384
    with assert_raises(contains="interval work limit"):
        _ = _lane_certificate_contains(road, 0, 0, Vector3(0.5, 0, 0), certificate)
    certificate.nodes = 0
    certificate.terms = 2000000
    with assert_raises(contains="quadrature work limit"):
        _ = _lane_certificate_contains(road, 0, 0, Vector3(0.5, 0, 0), certificate)


def test_exact_axis_certificate_retains_counters_and_strict_boundary() raises:
    var road = _road()
    var location = Vector3(0.5, 1.0, 0.0)
    var result = _refine_lane_certificate(road, 0, 0, 0.0, 4.0, location, 0.25, 0.0)
    assert_true(result.exact_witness)
    assert_equal(result.s, 0.5)
    assert_equal(result.nodes, 1)
    assert_equal(result.terms, 3)
    assert_false(_lane_certificate_contains(road, 0, 0, location, result))
    road = _road(width=1e-200)
    location = Vector3(0.5, 0, 0)
    result = _refine_lane_certificate(road, 0, 0, 0.0, 4.0, location, 0.25, 0.0)
    assert_true(_lane_certificate_contains(road, 0, 0, location, result))


def test_map_exact_lane_ties_keep_first_segment_and_strict_boundary() raises:
    var roads = List[Road]()
    roads.append(_road(1, -1.0))
    roads.append(_road(2, 1.0))
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    var nearest = map.closest_waypoint_on_road(Vector3(0.5, 0, 0)).value()
    assert_equal(nearest.road_id, RoadId(1))
    assert_false(Bool(map.waypoint(Vector3(0.5, 0, 0))))
    nearest = map.closest_waypoint_on_road(Vector3(0.5, -0.5, 0)).value()
    assert_equal(nearest.road_id, RoadId(2))
    assert_true(Bool(map.waypoint(Vector3(0.5, -0.5, 0))))



def test_empty_map_still_rejects_nonfinite_query_coordinates() raises:
    var map = Map(List[Road](), List[Junction](), List[Signal](), List[Controller]())
    assert_false(Bool(map.closest_waypoint_on_road(Vector3(0, 0, 0))))
    var nan = bitcast[DType.float32](UInt32(0x7FC00001))
    for bad in [inf[DType.float32](), -inf[DType.float32](), nan]:
        with assert_raises(contains="finite coordinates"):
            _ = map.closest_waypoint_on_road(Vector3(bad, 0, 0))
        with assert_raises(contains="finite coordinates"):
            _ = map.waypoint(Vector3(0, bad, 0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
