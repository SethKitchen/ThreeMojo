# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Controls for precise ideal bounds and origin-local scalar quadrature."""

from extensions.carla.curve_bounds import _expansion_distance_jet, _lane_jet, _reference_work, _scaled_point_distance_jet
from extensions.carla.curve_interval import _Interval, _Jet, _binary_power, _power_product_bound, _power_quotient_bound
from extensions.carla.geometry import LINE, SPIRAL, RoadGeometry
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import LANE_DRIVING, LaneId, NO_JUNCTION, RoadId, RoadInfoElevation, RoadInfoGeometry, RoadInfoLaneOffset, RoadInfoLaneWidth, SectionId
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import TestSuite, assert_almost_equal, assert_equal, assert_false, assert_true


def _road(var geometry: RoadGeometry) raises -> Road:
    var road = Road(RoadId(1), "centered", geometry.length, NO_JUNCTION, RoadId(0), RoadId(0), True)
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(RoadInfoLaneWidth(0.0, CubicPolynomial.constant(2.0)))
    road.info.geometries.append(RoadInfoGeometry(0.0, geometry^))
    road.info.elevations.append(RoadInfoElevation(0.0, CubicPolynomial.constant(0.0)))
    road.info.lane_offsets.append(RoadInfoLaneOffset(0.0, CubicPolynomial.constant(1.0)))
    return road^


def test_binary_power_guard_includes_subnormal_powers_only() raises:
    var eta = bitcast[DType.float64](UInt64(1))
    assert_true(_binary_power(eta))
    assert_true(_binary_power(-2.0))
    assert_true(_binary_power(1.0))
    assert_false(_binary_power(3.0 * eta))
    assert_false(_binary_power(1.5))
    assert_false(_binary_power(0.0))
    assert_false(_binary_power(inf[DType.float64]()))
    assert_false(_binary_power(bitcast[DType.float64](UInt64(0x7FF8000000000001))))


def test_normal_power_scaling_retains_exact_interval_endpoints() raises:
    var one = _Interval(1.25, 1.75)
    var product = _power_product_bound(one, _Interval.point(2.0))
    assert_equal(product.low, 2.5)
    assert_equal(product.high, 3.5)
    var reversed = _power_product_bound(_Interval.point(-2.0), one)
    assert_equal(reversed.low, -3.5)
    assert_equal(reversed.high, -2.5)
    var divided = _power_quotient_bound(product, _Interval.point(2.0))
    assert_equal(divided.low, one.low)
    assert_equal(divided.high, one.high)
    var negative = _power_quotient_bound(product, _Interval.point(-2.0))
    assert_equal(negative.low, -one.high)
    assert_equal(negative.high, -one.low)
    var zero = _power_product_bound(_Interval.point(0.0), _Interval.point(2.0))
    assert_equal(bitcast[DType.uint64](zero.low), UInt64(0x8000000000000000))
    assert_equal(bitcast[DType.uint64](zero.high), UInt64(0))


def test_unproved_scaling_keeps_the_outward_fallback() raises:
    var normal = bitcast[DType.float64](UInt64(0x0010000000000000))
    var eta = bitcast[DType.float64](UInt64(1))
    var limit = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    var under = _power_product_bound(_Interval.point(normal), _Interval.point(0.5))
    assert_true(under.contains(normal * 0.5))
    assert_true(under.low < under.high)
    var lost = _power_quotient_bound(_Interval.point(eta), _Interval.point(2.0))
    assert_true(lost.low <= 0.0)
    assert_true(lost.high >= eta)
    var over = _power_product_bound(_Interval.point(limit), _Interval.point(2.0))
    assert_equal(over.high, inf[DType.float64]())
    assert_true(over.low <= limit)
    assert_true(_power_product_bound(_Interval.point(1.3), _Interval.point(1.1)).contains(1.43))
    assert_true(_power_quotient_bound(_Interval.point(1.0), _Interval(-1, 1)).contains(0.0))


def test_exact_point_metric_does_not_invent_scalar_distance_rounding() raises:
    var zero = _Jet.constant(0.0)
    var point = (_Jet.constant(3.0), zero, zero)
    var metric = _scaled_point_distance_jet(point, Vector3(0, 0, 0), 2.0)
    assert_equal(metric.error, 0.0)
    assert_true(metric.value.contains(2.25))
    var perturbed = _Jet(_Interval.point(3.0), _Interval.point(1.0), _Interval.point(0.0), 0.25)
    metric = _scaled_point_distance_jet((perturbed, zero, zero), Vector3(0, 0, 0), 2.0)
    assert_true(metric.error >= 0.390625)
    assert_true(metric.rounded_value().contains(1.890625))
    assert_true(metric.rounded_value().contains(2.640625))
    assert_true(metric.first.contains(1.5))
    assert_true(metric.second.contains(0.5))


def test_expansion_translation_is_value_only_and_retains_actual_error_separation() raises:
    var road = _road(RoadGeometry(LINE, 0.0, 1000000001.0, 0.0, 0.0, 1.0))
    var expansion = _expansion_distance_jet(road, 0, 0, 0.5, Vector3(1000000000.0, 0, 0), 1.0)
    assert_true(expansion.value.contains(2.25))
    assert_true(expansion.value.width() < 1e-12)
    assert_equal(expansion.error, inf[DType.float64]())
    assert_false(expansion.rounded_value().is_finite())


def test_spiral_accumulates_displacement_before_the_wide_origin() raises:
    var geometry = RoadGeometry(SPIRAL, 0.0, 10000000000000000.0, 123.0, 0.0, 10.0)
    # Zero curvature is independently a straight segment. Each original
    # world-origin accumulation discarded a sub-ULP quadrature contribution.
    var point = geometry.pos_at(4.0)
    assert_equal(point.x - geometry.x, 4.0)
    assert_equal(point.y, geometry.y)
    var road = _road(geometry^)
    assert_equal(_reference_work(road, 4.0, 4.0), 25)
    var bound = _lane_jet(road, 0, 0, 4.0, 4.0)
    assert_true(bound[0].rounded_value().contains(point.x))
    assert_true(bound[1].rounded_value().contains(point.y))


def test_ordinary_arc_query_matches_the_independent_circle_minimum() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    var nearest = map.closest_waypoint_on_road(Vector3(70, 10, 0)).value()
    assert_equal(nearest.road_id, RoadId(11))
    assert_equal(nearest.lane_id, LaneId(-1))
    # Radius20, right offset1.75 and query relative to circle center(60,20)
    # give angle pi/4, hence road s = (pi/4)/0.05.
    assert_almost_equal(nearest.s, 15.707963267948966, atol=1e-6)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
