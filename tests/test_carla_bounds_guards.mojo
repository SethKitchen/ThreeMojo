# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Refusals of the junction, value and sampled lane bounds at their limits."""

from extensions.carla.curve_bounds import _reference_jet
from extensions.carla.curve_interval import _Interval, _Jet, _ValueJet
from extensions.carla.geometry import (
    LINE,
    PARAM_POLY3,
    POLY3,
    RoadGeometry,
    _Sample,
)
from extensions.carla.junction_bounds import (
    _monotone_coordinate_enclosure,
    _canonical_endpoint,
    _centered_elevation_enclosure,
    _certify_junction_span,
    _lane_section_box_with_work,
    _outward_float,
    _reserve_reference_point,
)
from extensions.carla.lane_value_bounds import (
    _atan2_value,
    _atan_value,
    _lane_value_bound,
    _reference_sampled_value,
    _sample_value,
)
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
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
from math.bounds import Box3
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

comptime HALF_PI = Float64(1.5707963267948966)
comptime PI = Float64(3.141592653589793)


def _next_up(value: Float64) -> Float64:
    return bitcast[DType.float64](bitcast[DType.uint64](value) + 1)


def _road(
    heading: Float64 = 0.0,
    x: Float64 = 0.0,
    y: Float64 = 0.0,
    length: Float64 = 10.0,
    start: Float64 = 0.0,
    elevation: Float64 = 0.0,
    slope: Float64 = 0.0,
    elevation_start: Float64 = 0.0,
    offset_start: Float64 = 0.0,
    width_start: Float64 = 0.0,
    geometries: Int = 1,
    elevations: Int = 1,
    offsets: Int = 1,
    widths: Int = 1,
    sections: Int = 1,
) raises -> Road:
    """Build a straight road with lanes -1, 0 and 1 and constant records."""
    var road = Road(
        RoadId(1), "bounds", length, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    for i in range(sections):
        _ = road.add_section(SectionId(i), Float64(i) * length / 2.0)
        for id in [-1, 0, 1]:
            var lane = road.sections[i].add_lane(LaneId(id))
            road.sections[i].lanes[lane].type = LANE_DRIVING
            if id != 0:
                for k in range(widths):
                    var s = width_start + Float64(k) * 5.0
                    road.sections[i].lanes[lane].info.widths.append(
                        RoadInfoLaneWidth(s, CubicPolynomial(3.5, 0, 0, 0, s))
                    )
    var geometry = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 10.0)
    geometry.heading = heading
    geometry.x = x
    geometry.y = y
    geometry.length = length if geometries == 1 else 5.0
    for i in range(geometries):
        geometry.s = start + Float64(i) * 5.0
        road.info.geometries.append(
            RoadInfoGeometry(geometry.s, geometry.copy())
        )
    for i in range(elevations):
        road.info.elevations.append(
            RoadInfoElevation(
                elevation_start + Float64(i) * 5.0,
                CubicPolynomial(elevation, slope, 0, 0, 0),
            )
        )
    for i in range(offsets):
        road.info.lane_offsets.append(
            RoadInfoLaneOffset(
                offset_start + Float64(i) * 5.0, CubicPolynomial(0, 0, 0, 0, 0)
            )
        )
    return road^


def _lane(road: Road, id: Int = -1) raises -> Int:
    return road.sections[0].lane_index(LaneId(id))


def _work() raises -> _MapBuildWork:
    return _MapBuildWork(MapBuildBudget())


# --- junction endpoints and outward rounding ----------------------------------


def test_junction_points_need_records_and_finite_storage() raises:
    var work = _work()
    var late = _road(start=2.0, length=12.0)
    with assert_raises(contains="scalar quadrature"):
        _reserve_reference_point(late, 1.0, work)
    for axis in range(3):
        var road = _road(elevation=1.0e39)
        if axis == 0:
            road = _road(x=1.0e39)
        elif axis == 1:
            road = _road(y=1.0e39)
        work = _work()
        with assert_raises(contains="endpoint is not finite"):
            _ = _canonical_endpoint(road, 0, _lane(road), 1.0, work)


def test_outward_float_steps_off_zero_and_refuses_overflow() raises:
    with assert_raises(contains="not finite"):
        _ = _outward_float(1.0e39, True)
    assert_equal(
        _outward_float(1.0e-50, False), bitcast[DType.float32](UInt32(1))
    )
    assert_equal(
        _outward_float(-1.0e-50, True),
        bitcast[DType.float32](UInt32(0x80000001)),
    )
    with assert_raises(contains="not finite"):
        _ = _outward_float(3.4028234663852886e38 + 5.0e30, False)


def test_centered_elevation_keeps_the_original_when_unusable() raises:
    var original = _Interval(-1.0, 1.0)
    var work = _work()
    var road = _road()
    var bad = nan[DType.float64]()
    var kept = _centered_elevation_enclosure(
        road, 1.0, 2.0, original, bad, work
    )
    assert_equal(kept.low, -1.0)
    var late = _road(elevation_start=5.0)
    kept = _centered_elevation_enclosure(late, 1.0, 2.0, original, 0.0, work)
    assert_equal(kept.low, -1.0)
    var split = _road(elevations=2)
    kept = _centered_elevation_enclosure(split, 1.0, 6.0, original, 0.0, work)
    assert_equal(kept.low, -1.0)
    var huge = _road(elevation=1.0e308, slope=1.0e308)
    kept = _centered_elevation_enclosure(huge, 1.0, 2.0, original, 0.0, work)
    assert_equal(kept.low, -1.0)
    var away = _Interval(100.0, 101.0)
    kept = _centered_elevation_enclosure(road, 1.0, 2.0, away, 0.0, work)
    assert_equal(kept.low, 100.0)


def test_monotone_enclosure_keeps_the_original_when_unusable() raises:
    var slope = _Jet(
        _Interval(0.0, 1.0), _Interval(1.0, 2.0), _Interval.whole(), 1.0e308
    )
    var original = _Interval(-1.0, 1.0)
    var huge = _Interval(1.7976931348623157e308, 1.7976931348623157e308)
    var kept = _monotone_coordinate_enclosure(slope, huge, huge, original)
    assert_equal(kept.low, -1.0)
    slope.error = 0.0
    var away = _Interval(100.0, 101.0)
    kept = _monotone_coordinate_enclosure(
        slope, _Interval(0.0, 0.0), _Interval(1.0, 1.0), away
    )
    assert_equal(kept.low, 100.0)


# --- junction span certification ---------------------------------------------


def test_junction_span_certifies_points_and_adjacent_cells() raises:
    var road = _road()
    var lane = _lane(road)
    var box = Box3.empty()
    var work = _work()
    _certify_junction_span(road, 0, lane, 1.0, 1.0, box, work)
    assert_true(isfinite(box.min.x))
    # Adjacent stations: the midpoint rounds to one end or the other.
    var one = _next_up(1.0)
    box = Box3.empty()
    _certify_junction_span(road, 0, lane, 1.0, one, box, work)
    box = Box3.empty()
    _certify_junction_span(road, 0, lane, one, _next_up(one), box, work)
    assert_true(isfinite(box.max.x))


def test_junction_span_refuses_an_unbounded_elevation() raises:
    var road = _road(elevation=1.7976931348623157e308, slope=1.0e308)
    var box = Box3.empty()
    var work = _work()
    with assert_raises(contains="subdivision limit"):
        _certify_junction_span(road, 0, _lane(road), 0.5, 1.0, box, work)


def test_junction_span_splits_only_near_an_elevation_edge() raises:
    # z runs from 0 to 1. Only a 2^-20 sliver at either end leaves the box.
    var road = _road(slope=1.0)
    var lane = _lane(road)
    var edge = Float32(9.5367431640625e-7)
    var work = _work()
    var high = Box3(Vector3(-100, -100, -1), Vector3(100, 100, 1 - edge))
    _certify_junction_span(road, 0, lane, 0.0, 1.0, high, work)
    var low = Box3(Vector3(-100, -100, edge), Vector3(100, 100, 2))
    _certify_junction_span(road, 0, lane, 0.0, 1.0, low, work)


def test_section_boxes_refuse_bad_intervals_and_infinite_proposals() raises:
    var road = _road()
    road.sections[0].s = -1.0
    var work = _work()
    with assert_raises(contains="invalid section interval"):
        _ = _lane_section_box_with_work(road, 0, _lane(road), work)
    # A geometry record that runs past its section adds a break after it.
    var two = _road(sections=2)
    work = _work()
    _ = _lane_section_box_with_work(two, 0, _lane(two), work)
    # A slight elevation curvature over a very long road takes the coarse
    # reference-line proposal, whose far end leaves Float32.
    var far = _road(length=1.0e39)
    far.info.elevations[0].polynomial.c = 1.0e-40
    work = _work()
    with assert_raises(contains="proposal is not finite"):
        _ = _lane_section_box_with_work(far, 0, _lane(far), work)


# --- value bounds ---------------------------------------------------------------


def _value(low: Float64, high: Float64) -> _ValueJet:
    return _ValueJet(
        _Interval(low, high), _Interval.whole(), _Interval.whole(), 0.0
    )


def test_value_atan_and_atan2_cover_each_quadrant_rule() raises:
    _ = _atan_value(_value(1.0, inf[DType.float64]()))
    var unbounded = _value(1.0, inf[DType.float64]())
    _ = _atan2_value(unbounded, _value(1.0, 2.0))
    _ = _atan2_value(_value(1.0, 2.0), unbounded)
    assert_equal(
        _atan2_value(_value(0.0, 0.0), _value(-2.0, -1.0)).value.low, PI
    )
    assert_equal(
        _atan2_value(_value(-0.0, -0.0), _value(-2.0, -1.0)).value.low, -PI
    )
    _ = _atan2_value(_value(0.1, 0.2), _value(-2.0, -1.0))
    _ = _atan2_value(_value(-0.2, -0.1), _value(-2.0, -1.0))
    _ = _atan2_value(_value(-0.1, 0.1), _value(-2.0, -1.0))
    _ = _atan2_value(_value(2.0, 3.0), _value(-1.0, 1.0))
    _ = _atan2_value(_value(-3.0, -2.0), _value(-1.0, 1.0))
    _ = _atan2_value(_value(-1.5, 1.5), _value(1.0, 2.0))


def _sampled(kind: Int, one: _Sample, two: _Sample) raises -> RoadGeometry:
    var geometry = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 1.0)
    geometry.kind = PARAM_POLY3 if kind == 1 else POLY3
    geometry.samples.append(one)
    geometry.samples.append(two)
    return geometry^


def test_sampled_frames_with_backward_or_starting_tangents() raises:
    var origin = Vector3(0, 0, 0)
    var d = _ValueJet.variable(0.2, 0.4)
    var jet = _Jet.variable(0.2, 0.4)
    var backward = _sampled(1, _Sample(0, 0, 0, -1, 0), _Sample(1, 0, 1, -1, 0))
    _ = _sample_value(backward, d, 0, origin)
    _ = _reference_jet(backward, jet, origin)
    var starting = _sampled(1, _Sample(0, 0, 0, 0, 0), _Sample(1, 0, 1, 1, 0))
    _ = _sample_value(starting, d, 0, origin)
    _ = _reference_jet(starting, jet, origin)
    var line = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 1.0)
    assert_false(_reference_sampled_value(line, d, origin)[0].value.is_finite())
    var bare = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 1.0)
    bare.kind = POLY3
    assert_false(_reference_sampled_value(bare, d, origin)[0].value.is_finite())


def test_lane_value_bounds_need_records_on_the_whole_domain() raises:
    var late = _road(start=2.0, length=12.0)
    with assert_raises(contains="geometry, elevation and offset"):
        _ = _lane_value_bound(late, 0, _lane(late), 1.0, 2.0)
    var offset = _road(offset_start=1.5)
    with assert_raises(contains="geometry, elevation and offset"):
        _ = _lane_value_bound(offset, 0, _lane(offset), 1.0, 2.0)
    var split = _road(geometries=2)
    assert_false(
        _lane_value_bound(split, 0, _lane(split), 1.0, 6.0)[0].value.is_finite()
    )
    var offsets = _road(offsets=2)
    assert_false(
        _lane_value_bound(offsets, 0, _lane(offsets), 1.0, 6.0)[
            0
        ].value.is_finite()
    )
    var widths = _road(widths=2)
    assert_false(
        _lane_value_bound(widths, 0, _lane(widths), 1.0, 6.0)[
            0
        ].value.is_finite()
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
