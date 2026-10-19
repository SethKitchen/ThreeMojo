# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A large triangle turning slowly, so fixed-point coverage stays locked.

    mojo run -I . examples/edges.mojo [path.png]

The edge test is 24.8 fixed point, not a float. A float edge on a
slowly moving triangle would swim. These pixels stay put until the edge
crosses them.
"""

from tools._example_output import (
    example_destination,
    point_on_circle,
    write_third_turn,
)

from math.vector2 import Vector2
from render.framebuffer import Color, Framebuffer
from render.rasterizer import Triangle, rasterize
from std.math import pi

comptime DEFAULT_OUTPUT = "out/coverage.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 48
comptime DELAY_MS = 50
comptime RADIUS = Float32(78)


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
    var step = Float32(2) * Float32(pi) / Float32(3)
    var triangle = Triangle(
        point_on_circle(center, RADIUS, angle),
        point_on_circle(center, RADIUS, angle + step),
        point_on_circle(center, RADIUS, angle + step + step),
    )
    var target = Framebuffer(WIDTH, HEIGHT, Color(18, 20, 28))
    rasterize(triangle, target, Color(70, 200, 255))
    return target^


def main() raises:
    write_third_turn[frame_at](
        FRAMES, DELAY_MS, example_destination(String(DEFAULT_OUTPUT))
    )
