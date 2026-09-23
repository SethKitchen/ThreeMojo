# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a Catmull-Rom type."""

from math.curve3 import catmull_rom3
from math.vector3 import Vector3


def main() raises:
    var bad = catmull_rom3([Vector3(0, 0, 0), Vector3(1, 0, 0)], False, 1)
    print(bad.points[0].x)
