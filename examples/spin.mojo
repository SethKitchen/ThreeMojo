# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Render a spinning triangle to an animated PNG.

    mojo run -I . examples/spin.mojo [path.png]

The rotation is done by hand here rather than with a matrix, because there is
no Matrix4 yet. When there is, this example is the first thing that should be
rewritten to use it.
"""

from math.vector2 import Vector2
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.rasterizer import Triangle, rasterize
from std.math import cos, pi, sin
from std.pathlib import Path
from std.sys import argv

comptime DEFAULT_OUTPUT = "out/spin.png"
comptime WIDTH = 160
comptime HEIGHT = 120
comptime FRAMES = 24
comptime DELAY_MS = 60
comptime RADIUS = Float32(44)


def rotated(center: Vector2, radius: Float32, angle: Float32) -> Vector2:
    """Return the point `radius` from `center` at `angle` radians."""
    return Vector2(
        center.x + radius * cos(angle), center.y + radius * sin(angle)
    )


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
        rotated(center, RADIUS, angle),
        rotated(center, RADIUS, angle + step),
        rotated(center, RADIUS, angle + step + step),
    )

    var target = Framebuffer(WIDTH, HEIGHT, Color(20, 24, 32))
    rasterize(triangle, target, Color(255, 128, 32))
    return target^


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        # A third of a turn brings the triangle back onto itself, so the loop
        # is seamless without repeating a frame.
        var angle = Float32(2) * Float32(pi) * Float32(index)
        angle = angle / (Float32(3) * Float32(FRAMES))
        frames.append(frame_at(angle))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
