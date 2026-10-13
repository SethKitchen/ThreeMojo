# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject precision target speed at the motion-plan boundary."""

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
    _ = stage.get_turn_target_velocity(
        [SimpleWaypointIndex(60), SimpleWaypointIndex(61)],
        Velocity64(1),
        shared,
    )
