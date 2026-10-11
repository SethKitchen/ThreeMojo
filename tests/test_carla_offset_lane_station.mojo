# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Default nearest-waypoint stations on offset and widening lanes (#302).

CARLA steps by the plan distance along a segment chord, as if it were road
s. A sloped or curved lane offset, or a sloped lane width, makes the chord
longer than its road-s span. The default query now steps by the foot's
plan fraction of the chord times the chord's road-s span. Each query point
is an exact lane center from `compute_transform`.
"""

from extensions.carla.map import Map, Waypoint, _chord_station_delta
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.opendrive import load_opendrive
from extensions.carla.road_info import LANE_DRIVING, LaneId, RoadId, SectionId
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
)


def _width(a: String, b: String = "0", c: String = "0") -> String:
    return (
        '<width sOffset="0" a="' + a + '" b="' + b + '" c="' + c + '" d="0"/>'
    )


def _section(s: String, right_width: String) -> String:
    return (
        '<laneSection s="'
        + s
        + '"><left><lane id="1" type="driving">'
        + _width("3.5")
        + '</lane></left><center><lane id="0" type="none"/></center>'
        + '<right><lane id="-1" type="driving">'
        + right_width
        + '</lane><lane id="-2" type="driving">'
        + _width("3.5")
        + "</lane></right></laneSection>"
    )


def _road(
    offset_b: String,
    offset_c: String,
    sections: String,
) raises -> Map:
    # A 100 m straight reference line along x, as in the issue.
    return load_opendrive(
        '<OpenDRIVE><road id="1" length="100" junction="-1">'
        '<planView><geometry s="0" x="0" y="0" hdg="0" length="100">'
        '<line/></geometry></planView><lanes><laneOffset s="0" a="0" b="'
        + offset_b
        + '" c="'
        + offset_c
        + '" d="0"/>'
        + sections
        + "</lanes></road></OpenDRIVE>"
    )


def _one_section(offset_b: String, offset_c: String) raises -> Map:
    return _road(offset_b, offset_c, _section("0", _width("3.5")))


def _check_center(
    map: Map, section: Int, lane: Int, s: Float64, s_tolerance: Float64
) raises:
    # Query at the exact lane center and require the same lane back.
    var target = Waypoint(RoadId(1), SectionId(section), LaneId(lane), s)
    var query = map.compute_transform(target).location
    var found = map.closest_waypoint_on_road(query)
    assert_true(Bool(found))
    var nearest = found.value()
    assert_equal(nearest.road_id, RoadId(1))
    assert_equal(nearest.section_id, SectionId(section))
    assert_equal(nearest.lane_id, LaneId(lane))
    assert_true(abs(nearest.s - s) <= s_tolerance)
    var under = map.waypoint(query)
    assert_true(Bool(under))
    assert_equal(under.value().lane_id, LaneId(lane))
    var at = map.compute_transform(nearest).location
    var dx = Float64(at.x) - Float64(query.x)
    var dy = Float64(at.y) - Float64(query.y)
    # The returned center lies on the query's lane center, in plan.
    assert_true(dx * dx + dy * dy <= s_tolerance * s_tolerance * 4.0)


def test_linear_offset_maps_chord_fraction_to_road_s() raises:
    # Issue comment: laneOffset b=1 gave s=70.71 and no waypoint at s=50.
    var map = _one_section("1", "0")
    assert_true(map.roads[0].lane_is_straight(0))
    for lane in [-2, -1, 1]:
        for s in [5.0, 50.0, 95.0]:
            _check_center(map, 0, lane, s, 1e-3)


def test_curved_offset_returns_the_exact_center_station() raises:
    # The issue's reproduction: laneOffset c=0.01 gave s=53.03.
    var map = _one_section("0", "0.01")
    assert_false(map.roads[0].lane_is_straight(0))
    var target = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 50.0)
    var query = map.compute_transform(target).location
    var nearest = map.closest_waypoint_on_road(query).value()
    assert_equal(nearest.lane_id, LaneId(-1))
    assert_true(abs(nearest.s - 50.0) < 0.05)
    assert_true(Bool(map.waypoint(query)))
    for lane in [-1, 1]:
        for s in [10.0, 50.0, 90.0]:
            _check_center(map, 0, lane, s, 0.05)


def test_low_curvature_offset() raises:
    # A small c still makes the lane curved, so it is not one chord.
    var map = _one_section("0.02", "0.00001")
    assert_false(map.roads[0].lane_is_straight(0))
    for lane in [-1, 1]:
        for s in [20.0, 80.0]:
            _check_center(map, 0, lane, s, 1e-3)


def test_sloped_and_curved_widths() raises:
    # A sloped width keeps lane -1 straight, but it shifts lane -2 too.
    var sloped = _road("0", "0", _section("0", _width("3.5", "0.1")))
    assert_true(sloped.roads[0].lane_is_straight(0))
    for lane in [-2, -1]:
        for s in [10.0, 60.0]:
            _check_center(sloped, 0, lane, s, 1e-3)
    var curved = _road("0", "0", _section("0", _width("3.5", "0", "0.001")))
    assert_false(curved.roads[0].lane_is_straight(0))
    for lane in [-2, -1]:
        for s in [10.0, 60.0]:
            _check_center(curved, 0, lane, s, 0.05)


def test_section_boundaries_keep_section_identity() raises:
    var map = _road(
        "1", "0", _section("0", _width("3.5")) + _section("50", _width("3.5"))
    )
    for lane in [-1, 1]:
        _check_center(map, 0, lane, 25.0, 1e-3)
        _check_center(map, 0, lane, 49.5, 1e-3)
        _check_center(map, 1, lane, 50.5, 1e-3)
        _check_center(map, 1, lane, 75.0, 1e-3)


def test_sign_check_query_uses_the_same_station() raises:
    # The load-time sign check uses the default query's arithmetic.
    var map = _one_section("1", "0")
    var target = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 50.0)
    var query = map.compute_transform(target).location
    var work = _MapBuildWork(MapBuildBudget())
    var found = map._closest_lane_with_build_work(query, LANE_DRIVING, work)
    var expected = map.closest_waypoint_on_road(query).value()
    assert_equal(found.value().lane_id, LaneId(-1))
    assert_equal(found.value().s, expected.s)
    assert_true(abs(found.value().s - 50.0) < 1e-3)


def test_chord_station_delta() raises:
    var start = Vector3(0, 0, 0)
    var end = Vector3(3, 4, 7)
    # The foot is halfway along the plan chord; z does not count.
    assert_equal(_chord_station_delta(Vector3(1.5, 2, -9), start, end, 8), 4)
    # Feet before the start and past the end clamp to the span.
    assert_equal(_chord_station_delta(Vector3(-3, -4, 0), start, end, 8), 0)
    assert_equal(_chord_station_delta(Vector3(6, 8, 0), start, end, 8), 8)
    # A chord with no plan length steps nowhere.
    assert_equal(
        _chord_station_delta(Vector3(1, 1, 0), start, Vector3(0, 0, 5), 8), 0
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
