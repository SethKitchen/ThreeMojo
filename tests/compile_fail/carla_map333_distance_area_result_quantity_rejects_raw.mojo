# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject raw assignment of the typed distance area result."""

from extensions.carla.math import distance_squared_2d
from math.vector3 import Vector3
from units.si import Length, Length64, Area64, Duration


def main() raises:
    var result: Float32 = distance_squared_2d(
        Vector3(0, 0, 0), Vector3(3, 4, 0)
    )
    _ = result
