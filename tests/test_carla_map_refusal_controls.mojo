# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Map and map-builder refusals that only invalid stored records reach."""

from extensions.carla.geometry import LINE, RoadGeometry
from extensions.carla.map import Controller, Junction, Map, Signal, Waypoint
from extensions.carla.map_builder import MapBuilder
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    JuncId,
    LANE_DRIVING,
    LaneId,
    NO_JUNCTION,
    RoadId,
    RoadInfoElevation,
    RoadInfoGeometry,
    RoadInfoLaneOffset,
    RoadInfoLaneWidth,
    SectionId,
    SignalId,
)
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def _road() raises -> Road:
    # One straight 4 m road with one 2 m driving lane.
    var road = Road._from_si(
        RoadId(1), "refusal", 4.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = road.add_section_meters(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth._from_si(0.0, CubicPolynomial._constant_si(2.0))
    )
    road.info.geometries.append(
        RoadInfoGeometry._from_si(
            0.0, RoadGeometry.from_meters(LINE, 0.0, 0.0, 0.0, 0.0, 4.0)
        )
    )
    road.info.elevations.append(
        RoadInfoElevation._from_si(0.0, CubicPolynomial._constant_si(0.0))
    )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset._from_si(0.0, CubicPolynomial._constant_si(1.0))
    )
    return road^


def _map() raises -> Map:
    var roads = List[Road]()
    roads.append(_road())
    return Map(roads^, List[Junction](), List[Signal](), List[Controller]())


def _waypoint(s: Float64 = 1.0) -> Waypoint:
    return Waypoint._from_si(RoadId(1), SectionId(0), LaneId(-1), s)


def test_lane_width_rejects_a_lane_without_width_records() raises:
    var map = _map()
    assert_equal(map.lane_width_meters(_waypoint()), 2.0)
    map.roads[0].sections[0].lanes[0].info.widths = List[RoadInfoLaneWidth]()
    with assert_raises(contains="no width record at s"):
        _ = map.lane_width_meters(_waypoint())


def test_backward_step_rejects_a_result_before_the_road_start() raises:
    var map = _map()
    # A section that starts before s = 0 leaves room for a backward step
    # that passes the road's start.
    map.roads[0].sections[0].s = -2.0
    with assert_raises(contains="left the road"):
        _ = map.previous_meters(_waypoint(0.5), 1.0)
    var kept = map.previous_meters(_waypoint(2.0), 1.0)
    assert_equal(len(kept), 1)
    assert_true(kept[0].s > 0.0)


def test_waypoint_spacing_rejects_a_station_that_overflows() raises:
    var map = _map()
    # A huge road and spacing make the second station overflow to infinity.
    map.roads[0].length = 1.7976931348623157e308
    with assert_raises(contains="cannot advance at this station"):
        _ = map.generate_waypoints_meters(1e308)


def test_param_poly3_rejects_an_unknown_range() raises:
    var u = CubicPolynomial._from_coefficients(0, 1, 0, 0, 0)
    var v = CubicPolynomial._from_coefficients(0, 0, 0, 0, 0)
    for p_range in ["arcLength", "normalized", ""]:
        var accepted = MapBuilder()
        var r = accepted.add_road_si(
            RoadId(1), "road", 1.0, JuncId(-1), RoadId(0), RoadId(0), True
        )
        accepted.add_road_geometry_param_poly3_si(
            r, 0, 0, 0, 0, 1, u, v, p_range
        )
    var b = MapBuilder()
    var r = b.add_road_si(
        RoadId(1), "road", 1.0, JuncId(-1), RoadId(0), RoadId(0), True
    )
    with assert_raises(contains="range must be arcLength or normalized"):
        b.add_road_geometry_param_poly3_si(r, 0, 0, 0, 0, 1, u, v, "bogus")


def test_signal_transform_rejects_a_road_without_geometry() raises:
    var b = MapBuilder()
    var r = b.add_road_si(
        RoadId(1), "road", 10.0, JuncId(-1), RoadId(0), RoadId(0), True
    )
    _ = b.add_signal_si(
        r,
        SignalId("s"),
        1,
        -5,
        "",
        "",
        "+",
        0,
        "",
        "",
        "",
        0,
        "",
        0,
        0,
        "",
        0,
        0,
        0,
    )
    var index = Dict[Int, Int]()
    index[1] = r
    var signal = b.signals[0].copy()
    with assert_raises(contains="cannot resolve reference quadrature work"):
        _ = b._signal_transform(index, signal)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
