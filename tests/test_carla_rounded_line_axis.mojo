# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Whole-domain stored-axis proofs for rotated constant LINE evaluators."""

from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.curve_interval import _next_up
from extensions.carla.curve_rounded_line import _rounded_line_axis_context
from extensions.carla.lane_refinement import (
    _rounded_axis_lane_minimum,
    _refine_lane_certificate,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import RoadInfoLaneWidth
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_carla_cross_candidate_certificates import _road


def _minimum(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    location: Vector3,
    max_nodes: Int = 16384,
    max_terms: Int = 2000000,
    max_depth: Int = 96,
) raises -> Optional[Tuple[Float64, Float64, Array[Float64, 3], Int, Int]]:
    var nodes = 0
    var terms = 0
    return _rounded_axis_lane_minimum(
        road,
        section,
        lane,
        low,
        high,
        location,
        nodes,
        terms,
        max_nodes,
        max_terms,
        max_depth,
    )


def _rotated(heading: Float64 = -1.5707963267948966) raises -> Road:
    var road = _road(width=3.5)
    road.length = 30.0
    road.info.geometries[0].geometry.length = road.length
    road.info.geometries[0].geometry.x = 80.0
    road.info.geometries[0].geometry.y = -20.0
    road.info.geometries[0].geometry.heading = heading
    road.info.lane_offsets[0].polynomial = CubicPolynomial.constant(0.0)
    return road^


def test_rotated_vertical_line_preserves_exact_stored_x() raises:
    var road = _rotated()
    var context = _rounded_line_axis_context(road, 0, 0, 0.25, 29.75)
    assert_true(Bool(context))
    assert_equal(context.value().axis, 1)
    assert_equal(context.value().slope, 1.0)
    for y in [
        Float32(22.012512),
        Float32(30.674988),
        Float32(39.337494),
        Float32(48),
    ]:
        var q = Vector3(80, y, 0)
        var result = _minimum(road, 0, 0, 0.25, 29.75, q)
        assert_true(Bool(result))
        ref exact = result.value()
        assert_equal(exact[2][0], 78.25)
        assert_equal(exact[2][1], Float64(y))
        assert_equal(exact[2][2], 0.0)
        assert_equal(exact[3], 2)
        assert_equal(exact[4], 4)
    for i in range(65):
        var s = 0.25 + 29.5 * Float64(i) / 64.0
        assert_equal(road._lane_center(0, 0, s)[0], 78.25)


def test_decreasing_vertical_and_horizontal_axes() raises:
    var vertical = _rotated(1.5707963267948966)
    vertical.info.geometries[0].geometry.y = 20.0
    var one = _minimum(vertical, 0, 0, 0.25, 29.75, Vector3(80, -30, 0))
    assert_true(Bool(one))
    assert_equal(one.value()[2][0], 81.75)
    assert_equal(one.value()[2][1], -30.0)
    var horizontal = _rotated(3.141592653589793)
    horizontal.info.geometries[0].geometry.y = -80.0
    var context = _rounded_line_axis_context(horizontal, 0, 0, 0.25, 29.75)
    assert_true(Bool(context))
    assert_equal(context.value().axis, 0)
    assert_equal(context.value().slope, -1.0)
    var two = _minimum(horizontal, 0, 0, 0.25, 29.75, Vector3(60, 78.25, 0))
    assert_true(Bool(two))
    assert_equal(two.value()[2][0], 60.0)
    assert_equal(two.value()[2][1], 78.25)


def test_proof_uses_rounding_not_a_heading_tolerance() raises:
    var road = _rotated(0.7)
    road.info.geometries[0].geometry.x = 1e20
    road.info.geometries[0].geometry.y = -80.0
    var context = _rounded_line_axis_context(road, 0, 0, 0.25, 29.75)
    assert_true(Bool(context))
    assert_equal(context.value().axis, 1)
    var q = Vector3(1e20, 72, 0)
    var result = _minimum(road, 0, 0, 0.25, 29.75, q)
    assert_true(Bool(result))
    assert_equal(result.value()[2][0], 1e20)
    assert_equal(result.value()[2][1], 72.0)
    road = _rotated(-1.5707963267948966 + 1e-12)
    assert_false(Bool(_rounded_line_axis_context(road, 0, 0, 0.25, 29.75)))


def test_unsupported_profiles_records_and_guard_ranges_fall_back() raises:
    var road = _rotated()
    assert_false(Bool(_rounded_line_axis_context(road, 0, 0, 0.0, 30.0)))
    assert_false(Bool(_rounded_line_axis_context(road, 0, 0, 0.25, 31.0)))
    road.info.elevations[0].polynomial.b = 0.1
    assert_false(Bool(_rounded_line_axis_context(road, 0, 0, 0.25, 29.75)))
    road.info.elevations[0].polynomial.b = 0.0
    road.sections[0].lanes[0].info.widths[0].polynomial.b = 0.1
    assert_false(Bool(_rounded_line_axis_context(road, 0, 0, 0.25, 29.75)))
    road.sections[0].lanes[0].info.widths[0].polynomial.b = 0.0
    road.info.lane_offsets[0].s = 1.0
    assert_false(Bool(_rounded_line_axis_context(road, 0, 0, 0.25, 29.75)))
    road.info.lane_offsets[0].s = 0.0
    road.info.geometries[0].geometry.x = bitcast[DType.float64](UInt64(1))
    assert_false(Bool(_rounded_line_axis_context(road, 0, 0, 0.25, 29.75)))


def test_adjacent_parameter_bracket_uses_exact_full_distance_order() raises:
    var road = _rotated()
    var base = Float64(1e20)
    road.length = base + 81920.0
    road.info.geometries[0].s = base
    road.info.geometries[0].geometry.length = 81920.0
    road.info.geometries[0].geometry.x = 1e20
    road.info.geometries[0].geometry.y = -100000.0
    var low = base + 16384.0
    var high = base + 81920.0
    var q = Vector3(1e20, 150000, 0)
    var query: Array[Float64, 3] = [Float64(q.x), Float64(q.y), 0.0]
    var result = _minimum(road, 0, 0, low, high, q)
    assert_true(Bool(result))
    ref exact = result.value()
    assert_equal(exact[0], base + 49152.0)
    var s = low
    while s <= high:
        var point = road._lane_center(0, 0, s)
        assert_true(_wide_point_order(exact[2], point, query) <= 0)
        s = _next_up(s)
    with assert_raises(contains="interval work limit"):
        _ = _minimum(road, 0, 0, low, high, q, max_nodes=2)
    with assert_raises(contains="quadrature work limit"):
        _ = _minimum(road, 0, 0, low, high, q, max_terms=3)
    with assert_raises(contains="numerical accuracy limit"):
        _ = _minimum(road, 0, 0, low, high, q, max_depth=0)
    q = Vector3(1e20, 157344, 0)
    result = _minimum(road, 0, 0, low, high, q)
    assert_true(Bool(result))
    assert_equal(result.value()[0], base + 49152.0)


def test_active_constant_width_record_allows_exact_horizontal_witness() raises:
    var road = _rotated(0.0)
    road.info.geometries[0].geometry.x = 0.0
    road.info.geometries[0].geometry.y = 0.0
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(20.0, CubicPolynomial.constant(8.0))
    )
    var context = _rounded_line_axis_context(road, 0, 0, 10.0, 19.75)
    assert_true(Bool(context))
    assert_equal(context.value().axis, 0)
    var result = _refine_lane_certificate(
        road, 0, 0, 10.0, 19.75, Vector3(15, 48, 0), 10.0, 0.0
    )
    assert_true(result.exact_witness)
    assert_equal(result.s, 15.0)
    assert_equal(result.point[1], 1.75)
    assert_equal(result.nodes, 2)
    assert_false(Bool(_rounded_line_axis_context(road, 0, 0, 10.0, 20.0)))


def test_declined_optional_proof_keeps_charged_work_for_fallback() raises:
    var road = _rotated(0.7)
    var nodes = 7
    var terms = 11
    var result = _rounded_axis_lane_minimum(
        road,
        0,
        0,
        0.25,
        29.75,
        Vector3(90, 5, 0),
        nodes,
        terms,
        16384,
        2000000,
        96,
    )
    assert_false(Bool(result))
    assert_equal(nodes, 8)
    assert_equal(terms, 12)
    for limit in [0, 1]:
        with assert_raises(contains="interval work limit"):
            _ = _refine_lane_certificate(
                road,
                0,
                0,
                0.25,
                29.75,
                Vector3(90, 5, 0),
                0.25,
                0.0,
                max_nodes=limit,
            )
    road = _rotated()
    for limit in [0, 1]:
        with assert_raises(contains="interval work limit"):
            _ = _minimum(
                road, 0, 0, 0.25, 29.75, Vector3(80, 30, 0), max_nodes=limit
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
