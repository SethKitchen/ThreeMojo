# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A lane id must be a `LaneId`, not a bare integer."""

from extensions.carla.road import LaneSection
from extensions.carla.road_info import SectionId


def main() raises:
    var section = LaneSection(SectionId(0), 0.0)
    print(section.contains_lane(-1))
