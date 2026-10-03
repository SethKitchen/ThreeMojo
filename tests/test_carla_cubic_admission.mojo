# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A smooth cubic exceeds the quarter-point chord target between samples."""

from extensions.carla.geometry import LINE, RoadGeometry
from extensions.carla.map import Controller, Junction, Map, Signal
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import LANE_DRIVING, LaneId, NO_JUNCTION, RoadId, RoadInfoElevation, RoadInfoGeometry, RoadInfoLaneOffset, RoadInfoLaneWidth, SectionId
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_true


def _road(id: Int, center_y: Float64, curved: Bool) raises -> Road:
    var road = Road(RoadId(id), "cubic admission", 1.0, NO_JUNCTION, RoadId(0), RoadId(0), True)
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(RoadInfoLaneWidth(0.0, CubicPolynomial.constant(0.000001)))
    road.info.geometries.append(RoadInfoGeometry(0.0, RoadGeometry(LINE, 0.0, 0.0, -center_y, 0.0, 1.0)))
    road.info.elevations.append(RoadInfoElevation(0.0, CubicPolynomial.constant(0.0)))
    var offset = CubicPolynomial.constant(0.0000005)
    if curved:
        # Center y = 0.021*s*(s-0.5)*(s-1), with one smooth record.
        offset = CubicPolynomial(0.0000005, -0.0105, 0.0315, -0.021, 0.0)
    road.info.lane_offsets.append(RoadInfoLaneOffset(0.0, offset))
    return road^


def test_narrow_cubic_peak_is_admitted_between_quarter_samples() raises:
    var x = Float32(0.21132486540518713)
    var xd = Float64(x)
    var height = Float32(0.021 * xd * (xd - 0.5) * (xd - 1.0))
    var roads = List[Road]()
    roads.append(_road(1, 0.0, True))
    # The first four chord candidates are only 3 to 6 micrometers away.
    for i in range(4):
        roads.append(_road(i + 2, Float64(height) - Float64(i + 3) * 0.000001, False))
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    assert_equal(map.segment_count(), 5)
    var segment = map.segment(0)
    var low = segment[2].s
    var high = segment[3].s
    var first = map.roads[0]._lane_center(0, 0, low)
    var last = map.roads[0]._lane_center(0, 0, high)
    for i in range(1,4):
        var t = Float64(i) * 0.25
        var center = map.roads[0]._lane_center(0, 0, low + t * (high-low))
        var chord_y = first[1] + t * (last[1]-first[1])
        assert_true(abs(center[1]-chord_y) < 0.001)
    var witness = map.roads[0]._lane_center(0, 0, xd)
    var t = (xd-low)/(high-low)
    var chord_y = first[1] + t * (last[1]-first[1])
    assert_true(abs(witness[1]-chord_y) > 0.001009)
    assert_true(abs(witness[1]-Float64(height)) < 0.0000000001)
    var query = Vector3(x, height, 0)
    var nearest = map.closest_waypoint_on_road(query).value()
    assert_equal(nearest.road_id, RoadId(1))
    assert_equal(nearest.lane_id, LaneId(-1))
    assert_true(Bool(map.waypoint(query)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
