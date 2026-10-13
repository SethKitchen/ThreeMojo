# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A lane marking must be a `LaneMarkingType`, not a bare integer."""

from extensions.carla.road_info import CHANGE_NONE, LaneMarking, MARKING_WHITE

from units.si import Length64


def main() raises:
    var mark = LaneMarking(2, MARKING_WHITE, CHANGE_NONE, Length64(0.15))
    print(mark.width)
