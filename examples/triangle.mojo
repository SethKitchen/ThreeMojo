# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Render one triangle and write it out.

    mojo run -I . examples/triangle.mojo [out.png]

Writes a PNG by default, since that is what image viewers and VS Code can
actually display. Pass a path ending in `.ppm` to get the human-readable text
format instead.
"""

from math.vector2 import Vector2
from render.framebuffer import Color, Framebuffer
from render.png import encode as encode_png
from render.ppm import encode as encode_ppm
from render.rasterizer import Triangle, rasterize
from std.pathlib import Path
from std.sys import argv

comptime DEFAULT_OUTPUT = "triangle.png"


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var background = Color(20, 24, 32)
    var foreground = Color(255, 128, 32)

    var triangle = Triangle(
        Vector2(50, 180),
        Vector2(160, 40),
        Vector2(275, 190),
    )

    var target = Framebuffer(320, 240, background)
    rasterize(triangle, target, foreground)

    if destination.endswith(".ppm"):
        var text = String("")
        encode_ppm(target, text)
        Path(destination).write_text(text)
    else:
        Path(destination).write_bytes(encode_png(target))
    print("Wrote", destination)
