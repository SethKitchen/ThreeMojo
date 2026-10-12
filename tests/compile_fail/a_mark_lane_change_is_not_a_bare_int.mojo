# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A road mark's lane change must be a `MarkLaneChange`, not a bare integer."""

from extensions.carla.road_info import RoadInfoMarkRecord

from units.si import Length64


def main() raises:
    var mark = RoadInfoMarkRecord(
        Length64(0),
        0,
        "solid",
        "",
        "white",
        "",
        Length64(0.15),
        1,
        Length64(0),
        "",
        Length64(0),
        True,
    )
    print(mark.width)
