# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A light search distance must keep Float64, not a Float32 Length."""

from extensions.carla.map import Waypoint
from extensions.carla.world import World
from units.si import Length, METER


def lights(world: World, start: Waypoint) raises:
    _ = world.get_traffic_lights_from_waypoint(start, Length(1.0, METER))


def main() raises:
    pass
