# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A lane marking color must be a `LaneMarkingColor`, not a bare integer."""

from extensions.carla.road_info import CHANGE_NONE, LaneMarking, SOLID


def main() raises:
    var mark = LaneMarking(SOLID, 4, CHANGE_NONE, 0.15)
    print(mark.width)
