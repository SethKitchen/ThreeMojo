# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A road geometry kind must be a `RoadGeometryKind`, not a bare integer."""

from extensions.carla.geometry import RoadGeometry
from units.si import Angle, Length, METER, RADIAN


def main() raises:
    var g = RoadGeometry(
        0,
        Length(0.0, METER),
        Length(0.0, METER),
        Length(0.0, METER),
        Angle(0.0, RADIAN),
        Length(1.0, METER),
    )
    print(g.length)
