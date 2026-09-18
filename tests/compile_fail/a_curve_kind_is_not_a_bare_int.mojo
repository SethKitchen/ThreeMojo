# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a curve kind."""

from math.curve import Curve
from math.vector2 import Vector2


def main() raises:
    var bad = Curve(0, [Vector2(0, 0), Vector2(1, 0)])
    print(bad.points[0].x)
