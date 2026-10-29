# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A gathering spot's kind must be a `GatherKind`, not a bare integer."""

from extensions.village.gathering import Spot
from units.si import DEGREE, Angle


def main() raises:
    var spot = Spot(1, 0, 0, Angle(0.0, DEGREE))
    print(spot.x)
