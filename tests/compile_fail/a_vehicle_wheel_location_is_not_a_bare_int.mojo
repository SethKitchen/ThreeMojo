# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A wheel must be a `VehicleWheelLocation`, not a bare integer."""

from extensions.carla.actor import ActorId
from extensions.carla.opendrive import load_opendrive
from extensions.carla.vehicle import FRONT_LEFT_WHEEL
from extensions.carla.world import World


def main() raises:
    var world = World(load_opendrive("<OpenDRIVE></OpenDRIVE>"))
    print(world.get_wheel_steer_angle(ActorId(2), 0).value)
