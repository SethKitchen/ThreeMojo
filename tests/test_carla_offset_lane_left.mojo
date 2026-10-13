# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Default nearest-waypoint stations on widening left lanes (#302).

`test_carla_offset_lane_station.mojo` widens the right lanes. These tests
widen the left lanes, so both lane signs carry sloped and curved widths.
They also combine a curved lane offset with a curved width, and put a
curved width on each side of a section boundary. Each query point is an
exact lane center from `compute_transform`.
"""

from extensions.carla.map import Map, Waypoint
from extensions.carla.opendrive import load_opendrive
from extensions.carla.road_info import LaneId, RoadId, SectionId
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


def _section(s: String, left_width: String) -> String:
    # Lane 1 takes the given width; lanes 2 and -1 keep 3.5 m.
    return (
        '<laneSection s="'
        + s
        + '"><left><lane id="2" type="driving">'
        + _width("3.5")
        + '</lane><lane id="1" type="driving">'
        + left_width
        + '</lane></left><center><lane id="0" type="none"/></center>'
        + '<right><lane id="-1" type="driving">'
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


def _check_center(
    map: Map, section: Int, lane: Int, s: Float64, s_tolerance: Float64
) raises:
    # Query at the exact lane center and require the same lane back.
    var target = Waypoint._from_si(
        RoadId(1), SectionId(section), LaneId(lane), s
    )
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


def test_sloped_left_width_stays_straight() raises:
    # A sloped width keeps lane 1 straight, but it shifts lane 2 too.
    var map = _road("0", "0", _section("0", _width("3.5", "0.1")))
    assert_true(map.roads[0].lane_is_straight(0))
    for lane in [1, 2]:
        for s in [10.0, 60.0]:
            _check_center(map, 0, lane, s, 1e-3)


def test_curved_left_width() raises:
    var map = _road("0", "0", _section("0", _width("3.5", "0", "0.001")))
    assert_false(map.roads[0].lane_is_straight(0))
    for lane in [1, 2]:
        for s in [10.0, 60.0, 90.0]:
            _check_center(map, 0, lane, s, 0.05)
    # The right lane does not widen; it keeps its exact station.
    _check_center(map, 0, -1, 60.0, 1e-3)


def test_curved_offset_and_curved_left_width() raises:
    # The offset and lane 1's width both bend, the same way on the left.
    var map = _road("0", "0.005", _section("0", _width("3.5", "0", "0.001")))
    assert_false(map.roads[0].lane_is_straight(0))
    for lane in [-1, 1, 2]:
        for s in [10.0, 50.0, 90.0]:
            _check_center(map, 0, lane, s, 0.05)


def test_curved_left_width_at_a_section_boundary() raises:
    # Each section restarts its width polynomial at its own sOffset 0.
    var curved = _width("3.5", "0", "0.002")
    var map = _road("0", "0", _section("0", curved) + _section("50", curved))
    for lane in [1, 2]:
        _check_center(map, 0, lane, 25.0, 0.05)
        _check_center(map, 0, lane, 49.5, 0.05)
        _check_center(map, 1, lane, 50.5, 0.05)
        _check_center(map, 1, lane, 75.0, 0.05)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
