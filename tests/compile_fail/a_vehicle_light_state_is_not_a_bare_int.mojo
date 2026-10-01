# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A vehicle's lights must be a `VehicleLightState`, not a bare integer."""

from extensions.carla.actor import ActorId
from extensions.carla.opendrive import load_opendrive
from extensions.carla.vehicle import LIGHT_BRAKE
from extensions.carla.world import World


def main() raises:
    var world = World(load_opendrive("<OpenDRIVE></OpenDRIVE>"))
    world.set_light_state(ActorId(2), 8)
