# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject precision input at the cam_interval quantity boundary."""

from extensions.carla.v2x import CaService, CamNoise
from extensions.carla.actor import ActorId
from tests.test_carla_world import _world
from units.si import (
    Acceleration,
    Angle,
    Angle64,
    Duration,
    Duration64,
    Length,
    Length64,
)


def main() raises:
    var world = _world()
    _ = CaService(
        world, ActorId(0), Duration64(0), Duration(1), False, CamNoise()
    )
