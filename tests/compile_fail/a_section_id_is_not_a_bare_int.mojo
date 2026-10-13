# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A lane section id must be a `SectionId`, not a bare integer."""

from extensions.carla.road import LaneSection

from units.si import Length64


def main() raises:
    var section = LaneSection(0, Length64(0.0))
    print(section.s)
