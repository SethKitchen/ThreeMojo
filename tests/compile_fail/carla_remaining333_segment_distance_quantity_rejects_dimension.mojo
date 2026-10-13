# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject dimension assignment of the typed segment distance result."""

from extensions.carla.map import segment_distance_2d
from math.vector3 import Vector3
from units.si import (
    Duration,
    Duration64,
    Length,
    Length64,
    Angle,
    Angle64,
    Velocity,
    Velocity64,
    Area,
    Area64,
    InverseLength,
    InverseLength64,
)


def main() raises:
    var result: Duration64 = segment_distance_2d(
        Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)
    )
    _ = result
