# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a color space."""

from render.framebuffer import Color
from render.texture import NEAREST, REPEAT, checkerboard


def main() raises:
    var bad = checkerboard(
        2, 1, Color(0, 0, 0), Color(9, 9, 9), REPEAT, NEAREST, 0
    )
    print(bad.width)
