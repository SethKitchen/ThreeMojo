# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A road mark's lane change must be a `MarkLaneChange`, not a bare integer."""

from extensions.carla.road_info import RoadInfoMarkRecord


def main() raises:
    var mark = RoadInfoMarkRecord(
        0.0, 0, "solid", "", "white", "", 0.15, 1, 0.0, "", 0.0, True
    )
    print(mark.width)
