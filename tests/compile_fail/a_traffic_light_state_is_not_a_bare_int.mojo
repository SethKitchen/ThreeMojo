# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A traffic light state must be a `TrafficLightState`, not a bare integer."""

from extensions.carla.actor import ActorId, RED
from extensions.carla.opendrive import load_opendrive
from extensions.carla.world import World


def main() raises:
    var world = World(load_opendrive("<OpenDRIVE></OpenDRIVE>"))
    world.set_traffic_light_state(ActorId(2), 0)
