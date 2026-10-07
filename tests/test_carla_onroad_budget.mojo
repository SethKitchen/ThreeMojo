# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Public default-budget regressions from the frozen on-road workload.

The words are query 355 (driving center) and query 183 (zero-width border).
Containing-ancestor objective reuse exhausted both APIs at these finite inputs.
No custom cap or parameter golden is used; the normal public contract applies.
"""

from extensions.carla.map import Map, Waypoint
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.road_info import LANE_ANY, LaneId, RoadId, SectionId
from math.vector3 import Vector3
from std.math import isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def _driving_center() -> Vector3:
    return Vector3(
        bitcast[DType.float32](UInt32(1112387505)),
        bitcast[DType.float32](UInt32(3270858546)),
        bitcast[DType.float32](UInt32(1074480022)),
    )


def _zero_width_border_center() -> Vector3:
    return Vector3(
        bitcast[DType.float32](UInt32(1086746718)),
        bitcast[DType.float32](UInt32(3267309672)),
        bitcast[DType.float32](UInt32(1066359849)),
    )


def _assert_lane_and_finite_pose(
    map: Map, waypoint: Waypoint, lane: Int
) raises:
    assert_equal(waypoint.road_id, RoadId(5))
    assert_equal(waypoint.section_id, SectionId(0))
    assert_equal(waypoint.lane_id, LaneId(lane))
    assert_true(isfinite(waypoint.s))
    var pose = map.compute_transform(waypoint)
    for component in [
        pose.location.x,
        pose.location.y,
        pose.location.z,
        pose.rotation.pitch,
        pose.rotation.yaw,
        pose.rotation.roll,
    ]:
        assert_true(isfinite(component))


def test_driving_center_strict_query_uses_default_budget() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    var found = map.waypoint(_driving_center())
    assert_true(Bool(found))
    _assert_lane_and_finite_pose(map, found.value(), -1)


def test_driving_center_nearest_query_uses_default_budget() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    var found = map.closest_waypoint_on_road(_driving_center())
    assert_true(Bool(found))
    _assert_lane_and_finite_pose(map, found.value(), -1)


def test_zero_width_border_nearest_query_uses_default_budget() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    var found = map.closest_waypoint_on_road(
        _zero_width_border_center(), LANE_ANY
    )
    assert_true(Bool(found))
    _assert_lane_and_finite_pose(map, found.value(), -3)


def test_zero_width_border_is_outside_under_strict_default_query() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    assert_false(Bool(map.waypoint(_zero_width_border_center(), LANE_ANY)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
