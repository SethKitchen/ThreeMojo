# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A light search distance must not be a duration."""

from extensions.carla.map import Waypoint
from extensions.carla.world import World
from units.si import Duration64


def lights(world: World, start: Waypoint) raises:
    _ = world.get_traffic_lights_from_waypoint(start, Duration64(1.0))


def main() raises:
    pass
