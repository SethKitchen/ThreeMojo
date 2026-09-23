# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a proper Euler order."""

from math.utils import quaternion_from_proper_euler
from units.si import Angle, RADIAN


def main() raises:
    var turn = Angle(0.5, RADIAN)
    var bad = quaternion_from_proper_euler(turn, turn, turn, 0)
    print(bad.w)
