# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A narrow-lane peak between quarter samples must reach the narrow search."""

from extensions.carla.geometry import LINE, PARAM_POLY3, RoadGeometry, _Sample
from extensions.carla.map import Controller, Junction, Map, Signal
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
from std.testing import TestSuite, assert_equal, assert_true


def _road(id: Int, var geometry: RoadGeometry) raises -> Road:
    var road = Road(
        RoadId(id),
        "unsampled peak",
        1.0,
        NO_JUNCTION,
        RoadId(0),
        RoadId(0),
        True,
    )
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(0.0, CubicPolynomial.constant(0.000001))
    )
    road.info.geometries.append(RoadInfoGeometry(0.0, geometry^))
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial.constant(0.0))
    )
    # Cancel the half-width exactly. The center is the stored reference path.
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(0.0, CubicPolynomial.constant(0.0000005))
    )
    return road^


def test_full_curve_admission_retains_a_narrow_lane_between_quarter_samples() raises:
    var geometry = RoadGeometry(PARAM_POLY3, 0.0, 0.0, 0.0, 0.0, 1.0)
    for s in [0.0, 0.125, 0.25, 0.5, 0.75, 1.0]:
        var height = Float64(0.005) if s == 0.125 else Float64(0.0)
        geometry.samples.append(_Sample(s, height, s, 1.0, 0.0))
    var spike = _road(1, geometry^)
    for s in [0.25, 0.5, 0.75]:
        assert_equal(spike._lane_center(0, 0, s)[1], 0.0)
    assert_equal(spike._lane_center(0, 0, 0.125)[1], -0.005)
    var roads = List[Road]()
    roads.append(spike^)
    # Four straight competitors fill the first index prefix. Their chords
    # are closer to the query than the peak lane's endpoint chord, while
    # every competitor center remains over 1 mm from the query.
    for i in range(4):
        roads.append(
            _road(
                i + 2,
                RoadGeometry(
                    LINE, 0.0, 0.0, 0.002 + Float64(i) * 0.0005, 0.0, 1.0
                ),
            )
        )
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    var query = Vector3(0.125, -0.005, 0.0)
    var nearest = map.certified_closest_waypoint_on_road(query).value()
    assert_equal(nearest.road_id, RoadId(1))
    assert_equal(nearest.lane_id, LaneId(-1))
    assert_true(Bool(map.certified_waypoint(query)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
