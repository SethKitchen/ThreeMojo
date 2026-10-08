# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Additive controls for complete Road record and center-helper coverage."""

from extensions.carla.geometry import ARC, LINE, RoadGeometry, with_arc
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
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _road() raises -> Road:
    var road = Road(
        RoadId(1), "records", 10, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = road.add_section(SectionId(0), 0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(0, CubicPolynomial.constant(2))
    )
    road.info.geometries.append(
        RoadInfoGeometry(0, RoadGeometry(LINE, 0, 0, 0, 0, 10))
    )
    road.info.elevations.append(
        RoadInfoElevation(0, CubicPolynomial.constant(0))
    )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(0, CubicPolynomial.constant(0))
    )
    return road^


def test_straight_lane_shortcut_requires_single_linear_records() raises:
    var road = _road()
    assert_true(road.lane_is_straight(0))
    road.info.elevations.append(
        RoadInfoElevation(5, CubicPolynomial.constant(0))
    )
    assert_false(road.lane_is_straight(0))
    _ = road.info.elevations.pop()
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(5, CubicPolynomial.constant(0))
    )
    assert_false(road.lane_is_straight(0))
    _ = road.info.lane_offsets.pop()
    road.info.lane_offsets[0].polynomial.d = 1
    assert_false(road.lane_is_straight(0))
    road.info.lane_offsets[0].polynomial.d = 0
    road.sections[0].lanes[0].info.widths[0].polynomial.d = 1
    assert_false(road.lane_is_straight(0))
    road.sections[0].lanes[0].info.widths.clear()
    assert_true(road.lane_is_straight(0))


def test_record_boundaries_handle_each_empty_collection() raises:
    var road = _road()
    assert_equal(len(road._lane_record_boundaries(0)), 4)
    road.info.geometries.clear()
    assert_equal(len(road._lane_record_boundaries(0)), 3)
    road.info.elevations.clear()
    assert_equal(len(road._lane_record_boundaries(0)), 2)
    road.info.lane_offsets.clear()
    assert_equal(len(road._lane_record_boundaries(0)), 1)
    road.sections[0].lanes[0].info.widths.clear()
    assert_equal(len(road._lane_record_boundaries(0)), 0)
    road.sections[0].lanes.clear()
    assert_equal(len(road._lane_record_boundaries(0)), 0)


def test_internal_lane_point_requires_its_own_offset_record() raises:
    var road = _road()
    road.info.lane_offsets.clear()
    with assert_raises(contains="no lane offset record"):
        _ = road._lane_point(0, 0, 5)
    # This requirement belongs to the Map center helper; the fixed-s Road
    # nearest query separately permits an absent offset record.


def test_distance_derivative_refuses_a_non_line_record() raises:
    var road = _road()
    road.info.geometries[0] = RoadInfoGeometry(
        0, with_arc(RoadGeometry(ARC, 0, 0, 0, 0, 10), 0.1)
    )
    assert_equal(
        len(road._lane_distance_derivative(0, 0, 0, 1, Vector3(0, 0, 0))), 0
    )


def test_distance_derivative_keeps_each_lane_sign_and_ignores_outer_lanes() raises:
    var road = _road()
    for id in [-2, 1, 2]:
        var lane = road.sections[0].add_lane(LaneId(id))
        road.sections[0].lanes[lane].type = LANE_DRIVING
        road.sections[0].lanes[lane].info.widths.append(
            RoadInfoLaneWidth(0, CubicPolynomial.constant(2))
        )
    _ = road.sections[0].add_lane(LaneId(0))
    for id in [-1, 1]:
        var lane = road.sections[0].lane_index(LaneId(id))
        var derivative = road._lane_distance_derivative(
            0, lane, 0, 1, Vector3(0, 0, 0)
        )
        # Straight constant-width centers are (s,+/-1,0). Half the derivative
        # of squared distance is s; normalized span and scale are both one.
        assert_equal(len(derivative), 6)
        assert_equal(derivative[0], 0.0)
        assert_equal(derivative[1], 1.0)
        for index in range(2, 6):
            assert_equal(derivative[index], 0.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
