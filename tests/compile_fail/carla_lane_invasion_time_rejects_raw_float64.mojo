# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A lane invasion time must be a Duration64, not a raw Float64."""

from extensions.carla.lane_invasion import LaneInvasionSensor
from extensions.carla.map import Map
from extensions.carla.transform import CarlaTransform


def tick(mut sensor: LaneInvasionSensor, map: Map, pose: CarlaTransform) raises:
    _ = sensor.tick(map, 1, Float64(1.0), pose)


def main() raises:
    pass
