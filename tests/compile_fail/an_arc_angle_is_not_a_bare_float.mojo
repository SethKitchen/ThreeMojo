# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for an arc's angle."""

from math.curve import arc
from math.vector2 import Vector2
from units.si import Angle, Length, METER, RADIAN


def main() raises:
    var bad = arc(Vector2(0, 0), Length(1, METER), 0.0, Angle(1, RADIAN))
    print(bad.sweep)
