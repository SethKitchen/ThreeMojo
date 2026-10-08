# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent analytic and position-difference controls for issue #485."""

from extensions.carla.geometry import (
    ARC,
    ARC_LENGTH,
    LINE,
    NORMALIZED,
    PARAM_POLY3,
    POLY3,
    SPIRAL,
    RoadGeometry,
    RoadGeometryKind,
    with_arc,
    with_param_poly3,
    with_poly3,
    with_spiral,
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
from std.math import atan2, cos, inf, nan, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)


def _geometry(kind: RoadGeometryKind) raises -> RoadGeometry:
    var base = RoadGeometry(kind, 0.0, 0.0, 0.0, 0.3, 20.0)
    if kind == ARC:
        return with_arc(base^, 0.08)
    if kind == SPIRAL:
        return with_spiral(base^, -0.06, 0.09)
    if kind == POLY3:
        return with_poly3(base^, 0.0, -0.2, 0.05, -0.001)
    if kind == PARAM_POLY3:
        return with_param_poly3(
            base^,
            CubicPolynomial(0, 23, -3, 2, 0),
            CubicPolynomial(0, -4, 9, -2, 0),
            NORMALIZED,
        )
    return base^


def _add_lanes(mut road: Road, section: Int, start: Float64 = 0.0) raises:
    for id in [-2, -1, 0, 1, 2]:
        var lane = road.sections[section].add_lane(LaneId(id))
        road.sections[section].lanes[lane].type = LANE_DRIVING
        if id != 0:
            road.sections[section].lanes[lane].info.widths.append(
                RoadInfoLaneWidth(
                    start, CubicPolynomial(3, 0.12, -0.004, 0.0001, start)
                )
            )


def _road(kind: RoadGeometryKind = LINE, rht: Bool = True) raises -> Road:
    var road = Road(
        RoadId(1), "orientation", 20.0, NO_JUNCTION, RoadId(0), RoadId(0), rht
    )
    _ = road.add_section(SectionId(0), 0.0)
    _add_lanes(road, 0)
    road.info.geometries.append(RoadInfoGeometry(0.0, _geometry(kind)))
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial(0, 0.2, -0.003, 0.0001, 0))
    )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(0.0, CubicPolynomial(0.5, 0.4, -0.012, 0.0002, 0))
    )
    return road^


def _along(road: Road, lane: Int, s: Float64) raises -> Vector3:
    return road.lane_transform(0, lane, s).rotation.forward_vector()


def _assert_direction(
    actual: Vector3,
    x: Float64,
    y: Float64,
    z: Float64,
    sign: Float64 = 1.0,
    tolerance: Float64 = 3e-6,
) raises:
    var size = max(abs(x), max(abs(y), abs(z)))
    var norm = sqrt((x / size) ** 2 + (y / size) ** 2 + (z / size) ** 2)
    assert_almost_equal(
        Float64(actual.x), sign * (x / size) / norm, atol=tolerance
    )
    assert_almost_equal(
        Float64(actual.y), sign * (y / size) / norm, atol=tolerance
    )
    assert_almost_equal(
        Float64(actual.z), sign * (z / size) / norm, atol=tolerance
    )


def _travel(rht: Bool, id: Int) -> Float64:
    if id == 0:
        return 1.0
    if (rht and id < 0) or (not rht and id > 0):
        return 1.0
    return -1.0


def test_unit_offset_slope_is_45_degrees() raises:
    for rht in [True, False]:
        var road = _road(rht=rht)
        road.length = 100
        road.info.geometries[0].geometry = RoadGeometry(
            LINE, 0.0, 0.0, 0.0, 0.0, 100.0
        )
        road.info.elevations[0].polynomial = CubicPolynomial.constant(0)
        for lane in range(5):
            if lane != 2:
                road.sections[0].lanes[lane].info.widths[
                    0
                ].polynomial = CubicPolynomial.constant(3.5)
        for slope in [-1.0, 0.0, 1.0]:
            road.info.lane_offsets[0].polynomial = CubicPolynomial(
                0, slope, 0, 0, 0
            )
            for lane in range(5):
                var id = lane - 2
                var pose = road.lane_transform(0, lane, 50)
                var expected = -45.0 * slope
                if _travel(rht, id) < 0:
                    expected += 180
                assert_almost_equal(
                    Float64(pose.rotation.yaw), expected, atol=1e-5
                )
                assert_equal(pose.rotation.roll, 0.0)
                _assert_direction(
                    pose.rotation.forward_vector(),
                    1,
                    -slope,
                    0,
                    _travel(rht, id),
                )


def test_inner_width_derivatives_and_grade_are_geometric() raises:
    # The third-order widths are integrated inward, without calling the
    # production width accumulator or its derivative in the expected result.
    for rht in [True, False]:
        var road = _road(rht=rht)
        road.info.geometries[0].geometry.heading = 0
        for lateral_sign in [-1.0, 1.0]:
            road.info.lane_offsets[0].polynomial = CubicPolynomial(
                0.5, lateral_sign * 0.4, 0, 0, 0
            )
            for s in [0.0, 4.0, 13.0, 20.0]:
                for lane in range(5):
                    var id = lane - 2
                    var factor = Float64(abs(id)) - 0.5
                    if id == 0:
                        factor = 0
                    elif id > 0:
                        factor = -factor
                    var slope = (
                        factor * (0.12 - 0.008 * s + 0.0003 * s * s)
                        - lateral_sign * 0.4
                    )
                    var grade = 0.2 - 0.006 * s + 0.0003 * s * s
                    _assert_direction(
                        _along(road, lane, s), 1, slope, grade, _travel(rht, id)
                    )


def test_curvature_changes_horizontal_speed_and_pitch() raises:
    for rht in [True, False]:
        var road = _road(ARC, rht)
        for curvature in [-0.125, 0.125]:
            road.info.geometries[0].geometry = with_arc(
                RoadGeometry(ARC, 0.0, 0.0, 0.0, 0.0, 20.0), curvature
            )
            for s in [0.0, 2.0, 12.0, 20.0]:
                for lane in range(5):
                    var id = lane - 2
                    var factor = Float64(abs(id)) - 0.5
                    if id == 0:
                        factor = 0
                    elif id > 0:
                        factor = -factor
                    # The differential uses the continuous curve before the
                    # existing scalar and output position storage boundaries.
                    var widths = factor * (
                        3 + 0.12 * s - 0.004 * s * s + 0.0001 * s * s * s
                    )
                    var offset = widths - (
                        0.5 + 0.4 * s - 0.012 * s * s + 0.0002 * s * s * s
                    )
                    var slope = factor * (0.12 - 0.008 * s + 0.0003 * s * s) - (
                        0.4 - 0.024 * s + 0.0006 * s * s
                    )
                    var theta = curvature * s
                    var speed = 1 + curvature * offset
                    var grade = 0.2 - 0.006 * s + 0.0003 * s * s
                    _assert_direction(
                        _along(road, lane, s),
                        speed * cos(theta) + slope * sin(theta),
                        -speed * sin(theta) + slope * cos(theta),
                        grade,
                        _travel(rht, id),
                    )


def _position_difference(
    road: Road,
    section: Int,
    lane: Int,
    s: Float64,
    step: Float64,
    side: Int = 0,
) raises:
    # This oracle uses only public positions, never the derivative helper.
    # A one-sided difference stays inside the selected record or sample.
    var before = s - step
    var after = s + step
    if side < 0:
        after = s
    elif side > 0:
        before = s
    var first = road.lane_transform(section, lane, before).location
    var second = road.lane_transform(section, lane, after).location
    var pose = road.lane_transform(section, lane, s)
    var id = road.sections[section].lanes[lane].id.value
    _assert_direction(
        pose.rotation.forward_vector(),
        Float64(second.x) - Float64(first.x),
        Float64(second.y) - Float64(first.y),
        Float64(second.z) - Float64(first.z),
        _travel(road.is_rht, id),
        0.002,
    )


def test_all_geometry_positions_match_finite_differences() raises:
    for kind in [LINE, ARC, SPIRAL, POLY3, PARAM_POLY3]:
        for rht in [True, False]:
            var road = _road(kind, rht)
            for lane in range(5):
                for s in [1.125, 4.375, 12.125, 18.625]:
                    _position_difference(road, 0, lane, s, 0.002)
                _position_difference(road, 0, lane, 0.0, 0.002, 1)
                _position_difference(road, 0, lane, 20.0, 0.002, -1)


def test_sampled_chord_and_offset_frame_are_distinct() raises:
    # For v=u^2, the first poly3 chord joins (0,0) to (0.3,0.09).
    # At its midpoint the stored slope is 0.3, but the chord slope is 0.3
    # throughout the interval. The offset frame still turns within it.
    var road = _road(POLY3)
    road.info.geometries[0].geometry = with_poly3(
        RoadGeometry(POLY3, 0.0, 0.0, 0.0, 0.0, 20.0), 0, 0, 1, 0
    )
    road.info.lane_offsets[0].polynomial = CubicPolynomial.constant(1)
    road.info.elevations[0].polynomial = CubicPolynomial(0, 0.5, 0, 0, 0)
    var span = sqrt(0.3 * 0.3 + 0.09 * 0.09)
    var theta = atan2(0.3, 1.0)
    var turn = (0.6 / span) / (1 + 0.3 * 0.3)
    _assert_direction(
        _along(road, 2, span / 2),
        0.3 / span - turn * cos(theta),
        -0.09 / span + turn * sin(theta),
        0.5,
    )
    # A one-meter normalized paramPoly3 uses five intervals. At p=0.1,
    # u=2p and v=p^2 interpolate between (0,0) and (0.4,0.04).
    road.info.geometries[0].geometry = with_param_poly3(
        RoadGeometry(PARAM_POLY3, 0.0, 0.0, 0.0, 0.0, 1.0),
        CubicPolynomial(0, 2, 0, 0, 0),
        CubicPolynomial(0, 0, 1, 0, 0),
        NORMALIZED,
    )
    span = sqrt(0.4 * 0.4 + 0.04 * 0.04)
    theta = atan2(0.2, 2.0)
    turn = (2 * 0.4 / span) / (4 + 0.2 * 0.2)
    _assert_direction(
        _along(road, 2, span / 2),
        0.4 / span - turn * cos(theta),
        -0.04 / span + turn * sin(theta),
        0.5,
    )


def test_all_geometries_with_negative_width_and_offset_slopes() raises:
    for kind in [LINE, ARC, SPIRAL, POLY3, PARAM_POLY3]:
        for rht in [True, False]:
            var road = _road(kind, rht)
            road.info.lane_offsets[0].polynomial = CubicPolynomial(
                0.5, -0.4, 0.012, -0.0002, 0
            )
            road.info.elevations[0].polynomial = CubicPolynomial(
                0, -0.2, 0.003, -0.0001, 0
            )
            for lane in range(5):
                if lane != 2:
                    road.sections[0].lanes[lane].info.widths[
                        0
                    ].polynomial = CubicPolynomial(6, -0.12, 0.004, -0.0001, 0)
                for at in [1.125, 4.375, 12.125, 18.625]:
                    _position_difference(road, 0, lane, at, 0.002)


def test_sample_intervals_use_the_selected_left_derivative() raises:
    for kind in [POLY3, PARAM_POLY3]:
        for rht in [True, False]:
            var road = _road(kind, rht)
            var boundary = road.info.geometries[0].geometry.samples[8].s
            for lane in range(5):
                _position_difference(road, 0, lane, boundary, 0.001, -1)
                _position_difference(road, 0, lane, boundary + 0.01, 0.001)


def test_spiral_partition_transition_and_constant_curvature() raises:
    for rht in [True, False]:
        var road = _road(SPIRAL, rht)
        # With k=0.25, d*(1+reach)=5 at d=4: the exact point uses
        # the partition from its left, and d>4 selects the next one.
        road.info.geometries[0].geometry = with_spiral(
            RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.2, 20.0), 0.25, 0.25
        )
        for lane in range(5):
            _position_difference(road, 0, lane, 4.0, 0.001, -1)
            _position_difference(road, 0, lane, 4.01, 0.001)
        road.info.geometries[0].geometry = with_spiral(
            RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.2, 20.0), 0.0, 0.0
        )
        for lane in range(5):
            _position_difference(road, 0, lane, 4.0, 0.002)


def test_record_and_section_boundaries_use_the_new_records() raises:
    for rht in [True, False]:
        var road = _road(rht=rht)
        _ = road.add_section(SectionId(9), 10.0)
        _add_lanes(road, 1, 10.0)
        road.info.geometries.append(
            RoadInfoGeometry(
                10.0, RoadGeometry(LINE, 10.0, 16.0, 20.0, -0.7, 10.0)
            )
        )
        road.info.lane_offsets.append(
            RoadInfoLaneOffset(10.0, CubicPolynomial(-2, -0.5, 0.01, 0, 10))
        )
        road.info.elevations.append(
            RoadInfoElevation(10.0, CubicPolynomial(8, -0.3, 0.002, 0, 10))
        )
        for lane in range(5):
            if lane != 2:
                road.sections[1].lanes[lane].info.widths.append(
                    RoadInfoLaneWidth(
                        12.0, CubicPolynomial(4, -0.2, 0.001, 0, 12)
                    )
                )
            _position_difference(road, 0, lane, 9.99, 0.002)
            _position_difference(road, 1, lane, 10.0, 0.002, 1)
            _position_difference(road, 1, lane, 11.99, 0.002)
            _position_difference(road, 1, lane, 12.0, 0.002, 1)


def test_stationary_vertical_and_reversed_curvature_tangents() raises:
    for rht in [True, False]:
        var road = _road(ARC, rht)
        road.info.geometries[0].geometry = with_arc(
            RoadGeometry(ARC, 0.0, 0.0, 0.0, 0.0, 20.0), 0.125
        )
        road.info.lane_offsets[0].polynomial = CubicPolynomial.constant(0)
        for lane in range(5):
            if lane != 2:
                road.sections[0].lanes[lane].info.widths[
                    0
                ].polynomial = CubicPolynomial.constant(16)
        # Left inner lane is the center of the circle: all plan derivatives
        # vanish exactly. Its yaw convention is still reference + traffic.
        for grade in [-0.25, 0.0, 0.25]:
            road.info.elevations[0].polynomial = CubicPolynomial(
                0, grade, 0, 0, 0
            )
            var pose = road.lane_transform(0, 3, 0)
            var sign = _travel(rht, 1)
            var yaw = 180.0 if sign < 0 else 0.0
            assert_equal(Float64(pose.rotation.yaw), yaw)
            var pitch = -90.0 if grade > 0 else 90.0
            if grade == 0:
                pitch = 0.0
            if sign < 0:
                pitch = 360 - pitch
            assert_equal(Float64(pose.rotation.pitch), pitch)
            if grade != 0:
                _assert_direction(
                    pose.rotation.forward_vector(), 0, 0, grade, sign
                )
            # The outer left lane has passed the curvature center. Its
            # tangent reverses even before traffic direction is applied.
            _assert_direction(_along(road, 4, 0), -2, 0, grade, _travel(rht, 2))


def test_winding_is_retained() raises:
    var road = _road()
    road.info.geometries[0].geometry.heading = 4 * 3.141592653589793
    road.info.lane_offsets[0].polynomial = CubicPolynomial(0, 1, 0, 0, 0)
    road.info.elevations[0].polynomial = CubicPolynomial.constant(0)
    assert_almost_equal(
        road.lane_transform(0, 2, 0).rotation.yaw, -765.0, atol=0.0001
    )


def test_nonfinite_and_unrepresentable_inputs_raise() raises:
    var road = _road()
    for s in [
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
        -1.0,
        21.0,
    ]:
        with assert_raises():
            _ = road.lane_transform(0, 0, s)
    for value in [nan[DType.float64](), inf[DType.float64](), 1e100]:
        road.info.lane_offsets[0].polynomial = CubicPolynomial.constant(value)
        with assert_raises():
            _ = road.lane_transform(0, 0, 2)
    road = _road()
    road.info.lane_offsets[0].polynomial = CubicPolynomial(
        0, inf[DType.float64](), 0, 0, 0
    )
    with assert_raises():
        _ = road.lane_transform(0, 2, 0)
    road = _road()
    road.info.elevations[0].polynomial = CubicPolynomial(
        0, inf[DType.float64](), 0, 0, 0
    )
    with assert_raises():
        _ = road.lane_transform(0, 2, 0)
    road = _road()
    for value in [nan[DType.float64](), inf[DType.float64](), 1e100]:
        road.info.geometries[0].geometry.x = value
        with assert_raises():
            _ = road.lane_transform(0, 0, 2)
    road = _road()
    for value in [nan[DType.float64](), inf[DType.float64](), 1e100]:
        road.info.geometries[0].geometry.heading = value
        with assert_raises():
            _ = road.lane_transform(0, 0, 2)


def test_sampled_singular_frame_and_clamped_stationary_geometry() raises:
    var road = _road(PARAM_POLY3)
    road.info.geometries[0].geometry.samples[0].tu = 0
    road.info.geometries[0].geometry.samples[0].tv = 0
    with assert_raises():
        _ = road.lane_transform(0, 2, 0)
    road = _road()
    road.info.geometries[0].geometry.length = 1
    road.info.lane_offsets[0].polynomial = CubicPolynomial.constant(0)
    road.info.elevations[0].polynomial = CubicPolynomial.constant(0)
    var pose = road.lane_transform(0, 2, 2)
    assert_almost_equal(pose.rotation.yaw, -17.188733853924695, atol=1e-5)
    assert_equal(pose.rotation.pitch, 0.0)


def test_geometry_validation_guards() raises:
    var road = _road()
    road.info.geometries[0].geometry.kind = RoadGeometryKind(5)
    with assert_raises(contains="kind"):
        _ = road.lane_transform(0, 2, 0)
    for length in [0.0, -1.0, inf[DType.float64](), nan[DType.float64]()]:
        road = _road()
        road.info.geometries[0].geometry.length = length
        with assert_raises(contains="length"):
            _ = road.lane_transform(0, 2, 0)
    for kind in [ARC, SPIRAL]:
        for which in [0, 1]:
            road = _road(kind)
            if which == 0:
                road.info.geometries[0].geometry.curvature_start = inf[
                    DType.float64
                ]()
            else:
                road.info.geometries[0].geometry.curvature_end = nan[
                    DType.float64
                ]()
            with assert_raises(contains="curvature"):
                _ = road.lane_transform(0, 2, 0)
    road = _road(ARC)
    road.info.geometries[0].geometry.curvature_start = 0
    with assert_raises(contains="nonzero curvature"):
        _ = road.lane_transform(0, 2, 0)
    road = _road(SPIRAL)
    road.info.geometries[0].geometry.curvature_start = 1e308
    road.info.geometries[0].geometry.curvature_end = -1e308
    with assert_raises(contains="work"):
        _ = road.lane_transform(0, 2, 1)
    road.info.geometries[0].geometry.curvature_start = 1e20
    road.info.geometries[0].geometry.curvature_end = 1e20
    with assert_raises(contains="work"):
        _ = road.lane_transform(0, 2, 1)
    var geometry = _geometry(LINE)
    with assert_raises():
        _ = geometry._derivative_at(nan[DType.float64]())
    assert_equal(geometry._derivative_at(-1)[0], 0.0)


def test_sampled_validation_guards() raises:
    var road = _road(POLY3)
    road.info.geometries[0].geometry.samples.clear()
    with assert_raises(contains="two samples"):
        _ = road.lane_transform(0, 2, 0)
    for span in [0.0, -1.0, inf[DType.float64](), nan[DType.float64]()]:
        road = _road(POLY3)
        # Keep just the selected first interval.
        var first_sample = road.info.geometries[0].geometry.samples[0]
        road.info.geometries[0].geometry.samples.resize(2, first_sample)
        road.info.geometries[0].geometry.samples[1].s = span
        with assert_raises(contains="positive length"):
            _ = road.lane_transform(0, 2, 0)
    road = _road(PARAM_POLY3)
    road.info.geometries[0].geometry.samples[0].tu = inf[DType.float64]()
    with assert_raises(contains="no heading"):
        _ = road.lane_transform(0, 2, 0)
    road = _road(POLY3)
    road.info.geometries[0].geometry.samples[1].v = 1e308
    with assert_raises(contains="derivative"):
        _ = road.lane_transform(0, 2, 0)


def test_coordinate_and_tangent_range_guards() raises:
    for axis in [0, 1]:
        var road = _road()
        if axis == 0:
            road.info.geometries[0].geometry.y = 1e100
        else:
            road.info.elevations[0].polynomial = CubicPolynomial.constant(1e100)
        with assert_raises(contains="center"):
            _ = road.lane_transform(0, 2, 0)
    var road = _road()
    road.info.geometries[0].geometry.heading = 0
    road.info.lane_offsets[0].polynomial = CubicPolynomial(0, 1e300, 0, 0, 0)
    road.info.elevations[0].polynomial = CubicPolynomial(0, -1e300, 0, 0, 0)
    _assert_direction(_along(road, 2, 0), 1, -1e300, -1e300)
    # Finite components can have an unrepresentable unscaled norm.
    road = _road(POLY3)
    road.info.lane_offsets[0].polynomial = CubicPolynomial.constant(0)
    road.info.elevations[0].polynomial = CubicPolynomial(0, 1.5e308, 0, 0, 0)
    ref geometry = road.info.geometries[0].geometry
    geometry.heading = 0
    geometry.samples[0].u = 0
    geometry.samples[0].v = 0
    geometry.samples[1].u = 1.5e308
    geometry.samples[1].v = 1.5e308
    geometry.samples[1].s = 1
    _assert_direction(_along(road, 2, 0), 1, -1, 1)
    # Subnormal-scale components do not become a stationary center merely
    # because their squares would underflow.
    geometry.samples[1].u = 1e-300
    geometry.samples[1].v = 0
    road.info.elevations[0].polynomial = CubicPolynomial(0, 1e-300, 0, 0, 0)
    _assert_direction(_along(road, 2, 0), 1, 0, 1)


def test_arc_length_parameter_and_extrapolated_sample_tail() raises:
    for rht in [True, False]:
        var road = _road(PARAM_POLY3, rht)
        # A slow parameterized curve ends before its declared distance. The
        # existing position evaluator extrapolates its final chord and frame.
        road.info.geometries[0].geometry = with_param_poly3(
            RoadGeometry(PARAM_POLY3, 0.0, 0.0, 0.0, 0.1, 20.0),
            CubicPolynomial(0, 0.5, 0, 0, 0),
            CubicPolynomial(0, 0.02, 0.001, 0, 0),
            ARC_LENGTH,
        )
        var boundary = road.info.geometries[0].geometry.samples[40].s
        for lane in range(5):
            _position_difference(road, 0, lane, 2.125, 0.002)
            _position_difference(road, 0, lane, boundary, 0.002, -1)
            _position_difference(road, 0, lane, 18.125, 0.002)
            _position_difference(road, 0, lane, 20.0, 0.002, -1)


def test_parametric_heading_wrap_keeps_the_same_direction() raises:
    var road = _road(PARAM_POLY3)
    road.info.geometries[0].geometry = with_param_poly3(
        RoadGeometry(PARAM_POLY3, 0.0, 0.0, 0.0, 0.0, 20.0),
        CubicPolynomial(0, -20, 0, 0, 0),
        CubicPolynomial(0, 2, -2, 0, 0),
        NORMALIZED,
    )
    for lane in range(5):
        for at in [9.5, 10.5]:
            _position_difference(road, 0, lane, at, 0.002)


def test_continuous_tangent_precedes_position_quantization() raises:
    var road = _road(ARC)
    road.info.geometries[0].geometry = with_arc(
        RoadGeometry(ARC, 0.0, 0.0, 0.0, 0.0, 20.0), 0.125
    )
    road.info.lane_offsets[0].polynomial = CubicPolynomial.constant(
        8.0 + 5.960464477539063e-8
    )
    road.info.elevations[0].polynomial = CubicPolynomial.constant(0)
    # The stored offset rounds to 8. The real centerline is a tiny circle
    # past the reference circle's center, with negative increasing-s speed.
    _assert_direction(_along(road, 2, 0), -1, 0, 0)
    road.info.lane_offsets[0].polynomial = CubicPolynomial.constant(
        8.0 - 5.960464477539063e-8
    )
    _assert_direction(_along(road, 2, 0), 1, 0, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
