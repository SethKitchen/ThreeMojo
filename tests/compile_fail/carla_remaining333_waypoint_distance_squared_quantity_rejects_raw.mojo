# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject raw assignment of the typed waypoint distance squared result."""

from extensions.carla.traffic_manager_map import SimpleWaypoint, WaypointId
from extensions.carla.map import Waypoint
from extensions.carla.road_info import RoadId, SectionId, LaneId
from tests.test_carla_world import _world
from math.vector3 import Vector3
from units.si import (
    Duration,
    Duration64,
    Length,
    Length64,
    Angle,
    Angle64,
    Velocity,
    Velocity64,
    Area,
    Area64,
    InverseLength,
    InverseLength64,
)


def main() raises:
    var world = _world()
    var waypoint = Waypoint(RoadId(1), SectionId(0), LaneId(-1), Length64(1))
    var node = SimpleWaypoint(world.map, waypoint, WaypointId(1))
    var result: Float32 = node.distance_squared(Vector3(1, 2, 3))
    _ = result
