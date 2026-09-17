# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a fog kind."""

from core.fog import Fog
from render.framebuffer import Color
from units.si import InverseLength, Length, METER, PER_METER


def main() raises:
    var bad = Fog(
        1,
        Color(200, 200, 200),
        Length(1.0, METER),
        Length(10.0, METER),
        InverseLength(0.0, PER_METER),
    )
    print(bad.color.r)
