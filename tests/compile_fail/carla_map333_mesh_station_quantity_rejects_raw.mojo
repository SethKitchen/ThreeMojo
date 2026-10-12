# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject raw input at the mesh station quantity boundary."""

from extensions.carla.road import Road
from extensions.carla.road_info import RoadId, NO_JUNCTION
from extensions.carla.mesh_factory import MeshFactory
from units.si import (
    Length64,
    Length,
    Duration,
    Duration64,
    Velocity,
    Velocity64,
)


def main() raises:
    var road = Road(
        RoadId(1), "road", Length64(10), NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = MeshFactory().generate_lane(road, 0, 0, Float64(1), Length64(5))
