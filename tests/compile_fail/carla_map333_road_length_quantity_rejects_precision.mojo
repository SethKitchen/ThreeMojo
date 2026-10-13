# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject precision input at the road length quantity boundary."""

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
    _ = Road(
        RoadId(1), "road", Length(1), NO_JUNCTION, RoadId(0), RoadId(0), True
    )
