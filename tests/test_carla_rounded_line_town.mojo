# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Exact rotated-axis and cross-road tie controls on the unchanged town."""

from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.road_info import LaneId, RoadId
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_false


def test_town_rotated_boundary_and_cross_road_tie_are_resolved() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    for y in [
        Float32(22.012512),
        Float32(30.674988),
        Float32(39.337494),
        Float32(48),
    ]:
        assert_false(Bool(map.certified_waypoint(Vector3(80, y, 0))))
    var query = Vector3(32, 48, 0)
    var nearest = map.certified_closest_waypoint_on_road(query).value()
    assert_equal(nearest.road_id, RoadId(1))
    assert_equal(nearest.lane_id, LaneId(-1))
    assert_equal(nearest.s, 32.0)
    assert_false(Bool(map.certified_waypoint(query)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
