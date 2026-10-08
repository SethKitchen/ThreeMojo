# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Refusals of the rounded and stored curve-proof helpers at their limits."""

from extensions.carla.curve_frozen_arc import (
    _frozen_arc_center,
    _frozen_arc_context,
)
from extensions.carla.curve_interval import (
    _Interval,
    _ValueJet,
    _stored_blend_error,
    _stored_difference,
    _stored_half,
)
from extensions.carla.curve_rounded_arc import (
    _RoundedArc,
    _RoundedBox,
    _rounded_arc_context,
    _rounded_constant,
    _rounded_madd,
)
from extensions.carla.curve_rounded_line import _rounded_line_axis_context
from extensions.carla.curve_trig import _QUARTER_PI
from extensions.carla.geometry import (
    ARC,
    LINE,
    RoadGeometry,
    RoadGeometryKind,
    with_arc,
)
from extensions.carla.lane_distance import _refinement_square
from extensions.carla.lane_geometry import (
    _lane_arc_offset,
    _lane_arc_offset_derivative,
    _lane_geometry_derivative_at,
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
from std.math import inf, isfinite, nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _pow2(exponent: Int) -> Float64:
    """Return 2 to a normal exponent, exactly."""
    return bitcast[DType.float64](UInt64(1023 + exponent) << UInt64(52))


def _next_up(value: Float64) -> Float64:
    return bitcast[DType.float64](bitcast[DType.uint64](value) + 1)


def _road(
    kind: RoadGeometryKind = ARC,
    curvature: Float64 = 0.1,
    heading: Float64 = 0.0,
    x: Float64 = 0.0,
    y: Float64 = 0.0,
    start: Float64 = 0.0,
    length: Float64 = 10.0,
    road_length: Float64 = 10.0,
    inner: Float64 = 3.5,
    outer: Float64 = 3.5,
    width_start: Float64 = 0.0,
    offset: Float64 = 0.0,
    offset_start: Float64 = 0.0,
    elevation_start: Float64 = 0.0,
    geometries: Int = 1,
    offsets: Int = 1,
    elevations: Int = 1,
) raises -> Road:
    """Build one section with lanes -2 through 2 and constant records."""
    var road = Road(
        RoadId(1), "edge", road_length, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = road.add_section(SectionId(0), 0.0)
    for id in [-2, -1, 0, 1, 2]:
        var lane = road.sections[0].add_lane(LaneId(id))
        road.sections[0].lanes[lane].type = LANE_DRIVING
        if id != 0:
            var width = inner if abs(id) == 1 else outer
            road.sections[0].lanes[lane].info.widths.append(
                RoadInfoLaneWidth(
                    width_start, CubicPolynomial(width, 0, 0, 0, width_start)
                )
            )
    var base = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 10.0)
    var geometry = with_arc(base^, 0.1) if kind == ARC else base^
    geometry.curvature_start = curvature if kind == ARC else 0.0
    geometry.curvature_end = geometry.curvature_start
    geometry.heading = heading
    geometry.x = x
    geometry.y = y
    geometry.length = length
    for i in range(geometries):
        geometry.s = start + Float64(i) * 5.0
        road.info.geometries.append(
            RoadInfoGeometry(start + Float64(i) * 5.0, geometry.copy())
        )
    for i in range(offsets):
        road.info.lane_offsets.append(
            RoadInfoLaneOffset(
                offset_start + Float64(i) * 5.0,
                CubicPolynomial(offset, 0, 0, 0, 0),
            )
        )
    for i in range(elevations):
        road.info.elevations.append(
            RoadInfoElevation(
                elevation_start + Float64(i) * 5.0,
                CubicPolynomial(0, 0, 0, 0, 0),
            )
        )
    return road^


def _lane(road: Road, id: Int) raises -> Int:
    return road.sections[0].lane_index(LaneId(id))


def _arc(road: Road, id: Int, low: Float64, high: Float64) raises -> Bool:
    return Bool(_rounded_arc_context(road, 0, _lane(road, id), low, high))


def _line(road: Road, id: Int, low: Float64, high: Float64) raises -> Bool:
    return Bool(_rounded_line_axis_context(road, 0, _lane(road, id), low, high))


# --- rounded boxes ------------------------------------------------------------


def test_rounded_box_operations_propagate_unknown() raises:
    var unknown = _RoundedBox.unknown()
    var one = _RoundedBox.point(1.0)
    assert_false(unknown.hull(one).known)
    assert_false(one.hull(unknown).known)
    assert_false((one + unknown).known)
    assert_false((unknown * one).known)
    assert_false((one * unknown).known)
    assert_false(_rounded_madd(unknown, one, one).known)
    assert_false(_rounded_madd(one, unknown, one).known)
    assert_false(_rounded_madd(one, one, unknown).known)
    var huge = _RoundedBox.point(_pow2(300))
    assert_false(_rounded_madd(huge, huge, one).known)
    assert_false(_rounded_constant(CubicPolynomial(1, 0, 0, 1, 0)).known)


def _model(
    start: Float64 = 0.0, curvature: Float64 = 1.0, length: Float64 = 10.0
) -> _RoundedArc:
    var zero = _RoundedBox.point(0.0)
    return _RoundedArc(
        _RoundedBox.point(start),
        length,
        _RoundedBox.point(curvature),
        _RoundedBox.point(1.0),
        zero,
        zero,
        zero,
    )


def test_rounded_arc_center_refuses_unstable_branches() raises:
    # A domain before the start, a half turn below the operand range, a
    # selector that crosses or lies below zero, and a turn past a quarter.
    assert_false(_model(start=5.0).center(1.0, 2.0)[0].known)
    assert_false(_model(curvature=_pow2(-399)).center(0.5, 0.5)[0].known)
    assert_false(_model(curvature=-1.0).center(1.4, 1.6)[0].known)
    assert_false(_model(curvature=-1.0).center(1.8, 2.0)[0].known)
    # Just past a negative quarter turn, the selector rounds to exactly zero.
    var half = _next_up(_QUARTER_PI)
    for _ in range(3):
        var turn = _model(curvature=-1.0)
        assert_false(turn.center(2.0 * half, 2.0 * half)[0].known)
        half = _next_up(half)


# --- rounded arc context ------------------------------------------------------


def test_rounded_arc_context_accepts_the_plain_arc() raises:
    var road = _road()
    assert_true(_arc(road, -1, 1.0, 2.0))
    assert_true(_arc(road, 0, 1.0, 2.0))
    assert_true(_arc(road, 2, 1.0, 2.0))


def test_rounded_arc_context_refuses_each_unsupported_record() raises:
    assert_false(_arc(_road(geometries=2), -1, 1.0, 2.0))
    assert_false(_arc(_road(kind=LINE), -1, 1.0, 2.0))
    assert_false(_arc(_road(), -1, 1.0, 11.0))
    assert_false(_arc(_road(start=2.0, road_length=12.0), -1, 1.0, 2.0))
    assert_false(_arc(_road(offsets=2), -1, 1.0, 2.0))
    assert_false(_arc(_road(elevations=2), -1, 1.0, 2.0))
    assert_false(_arc(_road(offset_start=1.5), -1, 1.0, 2.0))
    assert_false(_arc(_road(elevation_start=1.5), -1, 1.0, 2.0))
    assert_false(_arc(_road(width_start=1.5), -1, 1.0, 2.0))
    assert_false(_arc(_road(curvature=0.0), -1, 1.0, 2.0))


def test_rounded_arc_context_refuses_out_of_range_coefficients() raises:
    var big = _pow2(400)
    # Two outer contributions overflow the offset.
    assert_false(_arc(_road(inner=big, outer=big), -2, 1.0, 2.0))
    # The lane offset pushes the total offset out of range.
    assert_false(_arc(_road(inner=big, offset=-big), -1, 1.0, 2.0))
    # Each of speed, x, y and start alone leaves the operand range.
    assert_false(_arc(_road(curvature=_pow2(-400), inner=big), -1, 1.0, 2.0))
    assert_false(_arc(_road(x=1.0e-130), -1, 1.0, 2.0))
    assert_false(_arc(_road(y=1.0e-130), -1, 1.0, 2.0))
    assert_false(_arc(_road(start=1.0e-130), -1, 1.0, 2.0))
    # The geometry length is not an operand.
    assert_false(_arc(_road(length=1.0e-130), -1, 1.0, 2.0))


# --- frozen arc ---------------------------------------------------------------


def test_frozen_arc_refuses_an_unrepresentable_distance() raises:
    var start = _pow2(-399)
    var road = _road(start=start)
    assert_false(
        Bool(
            _frozen_arc_context(road, 0, _lane(road, -1), _next_up(start), 1.0)
        )
    )


def test_frozen_arc_center_outside_its_domain_is_unknown() raises:
    var model = _model(curvature=0.1)
    var origin = Vector3(0, 0, 0)
    var bad = _frozen_arc_center(model, nan[DType.float64](), 1.0, origin)
    assert_false(bad[0].value.is_finite())
    var past = _frozen_arc_center(model, 1.0, 11.0, origin)
    assert_false(past[0].value.is_finite())


# --- rounded line -------------------------------------------------------------


def test_rounded_line_context_refuses_each_unsupported_record() raises:
    assert_false(_line(_road(kind=LINE, geometries=2), -1, 1.0, 2.0))
    assert_false(_line(_road(), -1, 1.0, 2.0))
    assert_false(_line(_road(kind=LINE), -1, -2.0, -1.0))
    assert_false(
        _line(_road(kind=LINE, start=2.0, road_length=12.0), -1, 1.0, 2.0)
    )
    assert_false(_line(_road(kind=LINE, elevation_start=1.5), -1, 1.0, 2.0))
    assert_false(_line(_road(kind=LINE, offsets=2), -1, 1.0, 6.0))
    assert_false(_line(_road(kind=LINE, elevations=2), -1, 1.0, 6.0))
    assert_false(_line(_road(kind=LINE, width_start=1.5), -1, 1.0, 2.0))
    assert_false(_line(_road(kind=LINE, length=1.0e-130), -1, 1.0, 2.0))
    assert_false(_line(_road(kind=LINE, length=-5.0), -1, 1.0, 2.0))


def test_rounded_line_context_lanes_and_overflowing_offsets() raises:
    var road = _road(kind=LINE)
    assert_true(_line(road, 0, 1.0, 2.0))
    assert_true(_line(road, 2, 1.0, 2.0))
    assert_true(_line(road, -2, 1.0, 2.0))
    var big = _pow2(400)
    assert_false(_line(_road(kind=LINE, inner=big, outer=big), -2, 1.0, 2.0))
    assert_false(_line(_road(kind=LINE, inner=big, offset=-big), -1, 1.0, 2.0))
    assert_false(_line(_road(kind=LINE, inner=big, y=-big), -1, 1.0, 2.0))
    # A quarter turn keeps x fixed and moves y.
    assert_true(
        _line(
            _road(kind=LINE, heading=1.5707963267948966, x=100.0), -1, 1.0, 2.0
        )
    )


# --- lane geometry ------------------------------------------------------------


def test_tiny_curvature_arcs_use_the_offset_form() raises:
    var geometry = with_arc(
        RoadGeometry(ARC, 0.0, 0.0, 0.0, 0.0, 10.0), 5.0e-324
    )
    var point = _lane_arc_offset(geometry, 1.0, 0.5)
    assert_true(isfinite(point.x) and isfinite(point.y))
    var derivative = _lane_arc_offset_derivative(geometry, 1.0, 0.5, 0.0)
    assert_true(isfinite(derivative[0]) and isfinite(derivative[1]))


def test_geometry_derivative_guards() raises:
    var geometry = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 10.0)
    with assert_raises(contains="finite distance"):
        _ = _lane_geometry_derivative_at(geometry, nan[DType.float64]())
    var outside = _lane_geometry_derivative_at(geometry, -1.0)
    assert_equal(outside[0], 0.0)


# --- stored interval primitives -----------------------------------------------


def _jet(low: Float64, high: Float64, error: Float64 = 0.0) -> _ValueJet:
    return _ValueJet(
        _Interval(low, high), _Interval.whole(), _Interval.whole(), error
    )


def test_stored_difference_keeps_or_drops_its_exact_bound() raises:
    var big = _pow2(400)
    # The right operand exceeds the normal range; the guard does not apply.
    _ = _stored_difference(_jet(0.75 * big, big), _jet(0.8 * big, 1.2 * big))
    # Only one operand carries an error, so the difference keeps one.
    var kept = _stored_difference(_jet(3.0, 3.0), _jet(2.0, 2.0, 1.0e-17))
    assert_true(kept.error >= 1.0e-17)


def test_stored_blend_and_half_refuse_invalid_inputs() raises:
    var rate = _jet(0.0, inf[DType.float64]())
    assert_equal(_stored_blend_error(rate, 1.0, 2.0), inf[DType.float64]())
    assert_equal(
        _stored_blend_error(_jet(0.5, 0.5), 1.0, inf[DType.float64]()),
        inf[DType.float64](),
    )
    for which in range(3):
        var value = _jet(1.0, 2.0)
        if which == 0:
            value = _jet(2.0, 1.0)
        elif which == 1:
            value.error = inf[DType.float64]()
        else:
            value.error = -1.0
        _ = _stored_half(value)


def test_refinement_square_with_an_overflowing_gap() raises:
    var point: Array[Float64, 3] = [1.0e308, 0.0, 0.0]
    var query: Array[Float64, 3] = [-1.0e308, 0.0, 0.0]
    _ = _refinement_square[3](point, query, 1.0e-300)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
