# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject raw assignment of the typed motion base offset result."""

from extensions.carla.actor import ActorId
from extensions.carla.opendrive import load_opendrive
from extensions.carla.traffic_manager_collision import CollisionStage
from extensions.carla.traffic_manager_planning import MotionPlanStage
from extensions.carla.traffic_manager_map import SimpleWaypointIndex
from tests.test_carla_traffic_manager import straight_town
from tests.test_carla_traffic_manager_stages import _setup_follow
from units.si import (
    Duration,
    Duration64,
    Length,
    Length64,
    Velocity,
    Velocity64,
)


def main() raises:
    var map = load_opendrive(straight_town())
    var shared = _setup_follow(map, 50, 60, 5)
    var stage = MotionPlanStage()
    var result: Float32 = stage.calculate_base_offset(
        ActorId(1),
        [SimpleWaypointIndex(60), SimpleWaypointIndex(61)],
        False,
        1,
        shared,
    )
    _ = result
