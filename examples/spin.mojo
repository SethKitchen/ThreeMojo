# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Render a spinning triangle to an animated PNG.

    mojo run -I . examples/spin.mojo [path.png]

The rotation is done by hand rather than with a matrix, because this is the
smallest thing that animates: three points on a circle and the flat
rasterizer. `Matrix4` exists now, and everything above `cube.mojo` uses it.
"""

from examples.output import (
    example_destination,
    point_on_circle,
    write_third_turn,
)

from math.vector2 import Vector2
from render.framebuffer import Color, Framebuffer
from render.rasterizer import Triangle, rasterize
from std.math import pi

comptime DEFAULT_OUTPUT = "out/spin.png"
comptime WIDTH = 160
comptime HEIGHT = 120
comptime FRAMES = 24
comptime DELAY_MS = 60
comptime RADIUS = Float32(44)


def frame_at(angle: Float32) raises -> Framebuffer:
    """Render one frame with the triangle turned to `angle`.

    Args:
        angle: Rotation in radians.

    Returns:
        A freshly rendered frame.

    Raises:
        Error: If rasterization writes out of bounds, which it cannot.
    """
    var center = Vector2(Float32(WIDTH) / 2, Float32(HEIGHT) / 2)
    # Three points evenly spaced around a circle, all turned together.
    var step = Float32(2) * Float32(pi) / Float32(3)
    var triangle = Triangle(
        point_on_circle(center, RADIUS, angle),
        point_on_circle(center, RADIUS, angle + step),
        point_on_circle(center, RADIUS, angle + step + step),
    )

    var target = Framebuffer(WIDTH, HEIGHT, Color(20, 24, 32))
    rasterize(triangle, target, Color(255, 128, 32))
    return target^


def main() raises:
    write_third_turn[frame_at](
        FRAMES, DELAY_MS, example_destination(String(DEFAULT_OUTPUT))
    )
