# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject raw assignment of the typed navigation height result."""

from extensions.carla.navigation_mesh import NavPolygon, AREA_SIDEWALK
from math.vector3 import Vector3
from units.si import Length, Length64, Area64, Duration


def main() raises:
    var result: Float32 = NavPolygon(
        [Vector3(0, 0, 3), Vector3(4, 0, 3), Vector3(0, 4, 3)], AREA_SIDEWALK
    ).height_at(Vector3(1, 1, 0))
    _ = result
