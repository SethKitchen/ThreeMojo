# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Typed-road controls for the rounded LINE singleton producer contract."""

from extensions.carla.curve_rounded_arc import (
    _RoundedBox,
    _rounded_constant,
    _rounded_madd,
    _rounded_operand,
)
from extensions.carla.curve_rounded_line import (
    _RoundedLineAxis,
    _rounded_line_axis_context,
)
from extensions.carla.curve_trig import _curve_cos, _curve_sin
from extensions.carla.geometry import LINE
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import info_index, LaneId
from std.math import inf
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true, assert_false
from tests.test_carla_rounded_line_axis import _rotated


def _reference_rounded_line_axis_context(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64
) raises -> Optional[_RoundedLineAxis]:
    road._check_lane(section, lane)
    if len(road.info.geometries) != 1:
        return None
    ref record = road.info.geometries[0]
    if record.geometry.kind != LINE:
        return None
    if (
        not _RoundedBox.bounds(low, high).known
        or low < 0.0
        or high > road.length
    ):
        return None
    # One record active at low also covers high: the domain is ordered.
    if info_index(road.info.geometries, low) != 0:
        return None
    var offset_at = info_index(road.info.lane_offsets, low)
    var elevation_at = info_index(road.info.elevations, low)
    if (
        offset_at < 0
        or elevation_at < 0
        or info_index(road.info.lane_offsets, high) != offset_at
        or info_index(road.info.elevations, high) != elevation_at
    ):
        return None
    var lane_offset = _rounded_constant(
        road.info.lane_offsets[offset_at].polynomial
    )
    var elevation = _rounded_constant(
        road.info.elevations[elevation_at].polynomial
    )
    if not lane_offset.known or not elevation.known:
        return None
    ref lanes = road.sections[section].lanes
    var id = lanes[lane].id
    var offset = _RoundedBox.point(0.0)
    if id.value != 0:
        var negative = id.value < 0
        var sign = _RoundedBox.point(1.0 if negative else -1.0)
        for position in range(len(lanes)):
            var i = len(lanes) - 1 - position if negative else position
            if negative:
                if lanes[i].id.value >= 0:
                    continue
            elif lanes[i].id.value < 1:
                continue
            ref widths = lanes[i].info.widths
            var width_at = info_index(widths, low)
            if width_at < 0 or info_index(widths, high) != width_at:
                return None
            var width = _rounded_constant(widths[width_at].polynomial)
            if not width.known:
                return None
            var contribution = sign * width
            if lanes[i].id == id:
                contribution = contribution * _RoundedBox.point(0.5)
            offset = offset + contribution
            if not offset.known:
                return None
            if lanes[i].id == id:
                break
    offset = offset - lane_offset
    if not offset.known or offset.low != offset.high:
        return None
    var start = _RoundedBox.point(record.s)
    var d = _RoundedBox.bounds(low, high) - start
    var length = record.geometry.length
    if not d.known or not _rounded_operand(length) or length < 0.0:
        return None
    d = _RoundedBox.bounds(
        min(max(d.low, 0.0), length), min(max(d.high, 0.0), length)
    )
    if not d.known:
        return None
    # These are the canonical no-inline scalar trig graph's stored outputs.
    # Never substitute ideal sine/cosine or snap a near-axis heading.
    var cosine = _RoundedBox.point(_curve_cos(record.geometry.heading))
    var sine = _RoundedBox.point(_curve_sin(record.geometry.heading))
    var x = _rounded_madd(d, cosine, _RoundedBox.point(record.geometry.x))
    var y = _rounded_madd(d, sine, _RoundedBox.point(record.geometry.y))
    x = _rounded_madd(offset, sine, x)
    y = -_rounded_madd(-offset, cosine, y)
    if not (x.known and y.known and elevation.low == elevation.high):
        return None
    # Subtraction, clamp, constant multiply, rounded addition/FMA, and final
    # sign reversal compose monotonically. Each permitted contraction graph
    # has the indicated direction. The other two stored coordinates must be
    # singleton boxes under every permitted graph over this original domain.
    if y.low == y.high and cosine.low != 0.0:
        return _RoundedLineAxis(0, cosine.low)
    if x.low == x.high and sine.low != 0.0:
        return _RoundedLineAxis(1, -sine.low)
    return None


def _compare(road: Road, low: Float64, high: Float64) raises -> Bool:
    var actual = _rounded_line_axis_context(road, 0, 0, low, high)
    var expected = _reference_rounded_line_axis_context(road, 0, 0, low, high)
    assert_equal(Bool(actual), Bool(expected))
    if actual:
        assert_equal(actual.value().axis, expected.value().axis)
        assert_equal(actual.value().slope, expected.value().slope)
    return Bool(actual)


def test_constant_point_producers_and_real_road_refusals() raises:
    var tiny = bitcast[DType.float64](UInt64(1))
    var lower = bitcast[DType.float64](UInt64(623) << UInt64(52))
    var upper = bitcast[DType.float64](UInt64(1423) << UInt64(52))
    for value in [Float64(0.0), -0.0, lower, -lower, 3.5, -3.5, upper, -upper]:
        var point = _rounded_constant(CubicPolynomial.constant(value))
        assert_true(point.known)
        assert_equal(point.low, point.high)
        var road = _rotated(0.0)
        road.sections[0].lanes[0].id = LaneId(0)
        road.info.lane_offsets[0].polynomial = CubicPolynomial.constant(value)
        road.info.elevations[0].polynomial = CubicPolynomial.constant(value)
        assert_true(_compare(road, 0.25, 29.75))
    for value in [
        tiny,
        -tiny,
        lower * 0.5,
        upper * 2.0,
        inf[DType.float64](),
        -inf[DType.float64](),
    ]:
        var road = _rotated(0.0)
        road.info.elevations[0].polynomial = CubicPolynomial.constant(value)
        assert_false(_compare(road, 0.25, 29.75))
        road.info.elevations[0].polynomial = CubicPolynomial.constant(0.0)
        road.info.lane_offsets[0].polynomial = CubicPolynomial.constant(value)
        assert_false(_compare(road, 0.25, 29.75))
    # Each rounded operation still refuses an unsupported result.
    var road = _rotated(0.0)
    road.sections[0].lanes[0].info.widths[
        0
    ].polynomial = CubicPolynomial.constant(lower)
    assert_false(_compare(road, 0.25, 29.75))
    road.sections[0].lanes[0].info.widths[
        0
    ].polynomial = CubicPolynomial.constant(2.0 * upper)
    assert_false(_compare(road, 0.25, 29.75))
    road.sections[0].lanes[0].info.widths[
        0
    ].polynomial = CubicPolynomial.constant(upper)
    road.info.lane_offsets[0].polynomial = CubicPolynomial.constant(-upper)
    assert_false(_compare(road, 0.25, 29.75))


def test_clamp_endpoint_lobes_preserve_known_bounds() raises:
    for length in [Float64(0.0), 0.125, 0.25, 1.0, 30.0]:
        var road = _rotated(0.0)
        road.info.geometries[0].geometry.length = length
        assert_true(_compare(road, 0.25, 29.75))
        assert_true(_compare(road, 0.25, 0.25))
    for length in [
        Float64(-1.0),
        inf[DType.float64](),
        -inf[DType.float64](),
        bitcast[DType.float64](UInt64(1)),
    ]:
        var road = _rotated(0.0)
        road.info.geometries[0].geometry.length = length
        assert_false(_compare(road, 0.25, 29.75))
    var road = _rotated(0.0)
    # A domain that meets zero before clamping is still refused.
    assert_false(_compare(road, 0.0, 29.75))
    road.info.geometries[0].s = 0.25
    assert_false(_compare(road, 0.25, 29.75))


def test_trig_guards_remain_and_singletons_do_not_snap_heading() raises:
    for heading in [
        Float64(0.0),
        -0.0,
        0.7,
        1.5707963267948966,
        -1.5707963267948966,
        3.141592653589793,
        1048577.0,
    ]:
        var road = _rotated(heading)
        _ = _compare(road, 0.25, 29.75)
        _ = _compare(road, 0.25, 0.25)
    var road = _rotated(0.7)
    assert_false(_compare(road, 0.25, 29.75))
    road.info.geometries[0].geometry.x = 1e20
    assert_true(_compare(road, 0.25, 29.75))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
