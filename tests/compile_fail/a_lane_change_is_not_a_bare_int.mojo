# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A lane change must be a `LaneChange`, not a bare integer."""

from extensions.carla.road_info import LaneMarking, MARKING_WHITE, SOLID

from units.si import Length64


def main() raises:
    var mark = LaneMarking(SOLID, MARKING_WHITE, 3, Length64(0.15))
    print(mark.width)
