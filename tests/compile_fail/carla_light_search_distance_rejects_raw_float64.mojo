# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A light search distance must be a Length64, not a raw Float64."""

from extensions.carla.map import Waypoint
from extensions.carla.world import World


def lights(world: World, start: Waypoint) raises:
    _ = world.get_traffic_lights_from_waypoint(start, Float64(1.0))


def main() raises:
    pass
