# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject raw input at the map distance quantity boundary."""

from extensions.carla.opendrive import load_opendrive
from extensions.carla.map import Waypoint
from extensions.carla.road_info import RoadId, SectionId, LaneId
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
    var map = load_opendrive("<OpenDRIVE/>")
    var point = Waypoint(RoadId(1), SectionId(0), LaneId(-1), Length64(0))
    _ = map.next(point, Float64(1))
