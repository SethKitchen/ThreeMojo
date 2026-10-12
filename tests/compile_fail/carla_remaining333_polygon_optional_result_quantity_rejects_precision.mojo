# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject precision assignment of the typed polygon optional result."""

from extensions.carla.traffic_manager_collision import polygon_distance
from math.vector3 import Vector3
from units.si import (
    Duration,
    Duration64,
    Length,
    Length64,
    Velocity,
    Velocity64,
)


def main() raises:
    var result: Optional[Length] = polygon_distance(
        List[Vector3](), List[Vector3]()
    )
    _ = result
