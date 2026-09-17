# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a corner's material kind.

The kind decides which fragment path a triangle takes on both backends --
lit, unlit, a normal or a depth -- and it used to be a `Bool` that only
said whether the lights reached the surface. A bare integer in its place
would be read as a kind nothing implements.
"""

from render.framebuffer import FloatColor
from render.rasterizer import RasterVertex


def main() raises:
    var bad = RasterVertex(0, 0, 0.5, 1, FloatColor(1, 1, 1), kind=1)
    print(bad.x)
