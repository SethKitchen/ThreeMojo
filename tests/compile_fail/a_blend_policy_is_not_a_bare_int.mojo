# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a blend policy."""

from render.framebuffer import FloatColor
from render.rasterizer import RasterVertex


def main() raises:
    var bad = RasterVertex(0, 0, 0, 1, FloatColor(1, 1, 1), blend=7)
    print(bad.x)
