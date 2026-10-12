# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject raw input at the road query quantity boundary."""

from extensions.carla.road import Road
from extensions.carla.road_info import RoadId, NO_JUNCTION
from units.si import (
    Length64,
    Angle64,
    InverseLength64,
    InverseArea64,
    Duration64,
    Length,
    Angle,
    InverseLength,
)
from units.quantity import Quantity


def main() raises:
    var road = Road(
        RoadId(1), "road", Length64(10), NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = road.directed_point(Float64(1))
