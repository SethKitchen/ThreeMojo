# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A port of three.js's `FlakesTexture`,
`examples/jsm/textures/FlakesTexture.js`: a normal map of metal flakes, for the
clear coat of a car's paint.

three.js paints 4000 discs on a canvas that is the flat normal,
`rgb(127, 127, 255)`. Each disc is three to six pixels across in radius,
at a random place, and its color is a random normal tilted from the z
axis: x and y from minus one to one and z one and a half, made unit
length, then written as `x * 127 + 127`, `y * 127 + 127` and `z * 255`.

This port paints the same discs from a `SeededRandom`, three.js's
`MathUtils.seededRandom`. three.js draws from `Math.random`, which has no
seed, so no two of its canvases agree either. A disc covers a pixel by the
share of the pixel inside it, as a canvas smooths the edge of a fill: the
pixel moves toward the disc's color by that share. A canvas keeps bytes,
so each channel is rounded after each disc.
"""

from math.utils import SeededRandom
from render.srgb import LINEAR
from render.texture import BILINEAR, REPEAT, Texture
from std.math import ceil, floor, sqrt

# How many discs three.js paints.
comptime FLAKE_COUNT = 4000
# How many samples a side a pixel's coverage is measured with, and how far
# the farthest is from the pixel's center: 0.375 across and down.
comptime _SAMPLES = 4
comptime _REACH = 0.5304


def _byte(value: Float64) -> UInt8:
    """Return a CSS `rgb()` channel as a canvas keeps it: rounded to the
    nearest whole number, and held from 0 to 255."""
    return UInt8(Int(max(0.0, min(255.0, value)) + 0.5))


def _coverage(
    x: Int, y: Int, center_x: Float64, center_y: Float64, radius: Float64
) -> Float64:
    """Return the share of the pixel at column `x` and row `y` inside a
    disc, measured at `_SAMPLES` by `_SAMPLES` points. A pixel whose center
    is farther inside or outside the edge than its farthest sample, 0.53
    of a pixel, is measured whole."""
    var dx = Float64(x) + 0.5 - center_x
    var dy = Float64(y) + 0.5 - center_y
    var apart = sqrt(dx * dx + dy * dy)
    if apart + _REACH <= radius:
        return 1
    if apart - _REACH > radius:
        return 0
    var inside = 0
    var squared = radius * radius
    for i in range(_SAMPLES):  # pragma: no branch
        for j in range(_SAMPLES):  # pragma: no branch
            var dx = Float64(x) + (Float64(i) + 0.5) / _SAMPLES - center_x
            var dy = Float64(y) + (Float64(j) + 0.5) / _SAMPLES - center_y
            if dx * dx + dy * dy <= squared:
                inside += 1
    return Float64(inside) / Float64(_SAMPLES * _SAMPLES)


def flakes_texture(
    width: Int = 512, height: Int = 512, seed: Int = 0
) raises -> Texture:
    """Return three.js's `FlakesTexture`: a normal map of `FLAKE_COUNT`
    discs, each a random normal, on the flat normal. The texture holds
    data, not color, and repeats, as three.js's example sets it.

    Args:
        width: The width in pixels; three.js's default is 512.
        height: The height in pixels; three.js's default is 512.
        seed: The seed of the random places, sizes and normals.

    Returns:
        The texture, rows from the top, as a canvas's are.

    Raises:
        Error: If a side is not at least one pixel.
    """
    if width < 1 or height < 1:
        raise Error("A flakes texture is at least one pixel on each side")
    var pixels = List[UInt8](capacity=width * height * 4)
    for _ in range(width * height):  # pragma: no branch
        pixels.append(127)
        pixels.append(127)
        pixels.append(255)
        pixels.append(255)
    var random = SeededRandom(seed)
    for _ in range(FLAKE_COUNT):  # pragma: no branch
        var center_x = random.next() * Float64(width)
        var center_y = random.next() * Float64(height)
        var radius = random.next() * 3 + 3
        var nx = random.next() * 2 - 1
        var ny = random.next() * 2 - 1
        var nz = 1.5
        var length = sqrt(nx * nx + ny * ny + nz * nz)
        nx /= length
        ny /= length
        nz /= length
        var color: List[Float64] = [
            Float64(_byte(nx * 127 + 127)),
            Float64(_byte(ny * 127 + 127)),
            Float64(_byte(nz * 255)),
        ]
        var left = max(0, Int(floor(center_x - radius)))
        var right = min(width - 1, Int(ceil(center_x + radius)))
        var top = max(0, Int(floor(center_y - radius)))
        var bottom = min(height - 1, Int(ceil(center_y + radius)))
        # Never empty: the center is in the image, and the radius three or
        # more.
        for y in range(top, bottom + 1):  # pragma: no branch
            for x in range(left, right + 1):  # pragma: no branch
                var share = _coverage(x, y, center_x, center_y, radius)
                if share == 0:
                    continue
                var at = (y * width + x) * 4
                for channel in range(3):  # pragma: no branch
                    var old = Float64(pixels[at + channel])
                    pixels[at + channel] = _byte(
                        old + (color[channel] - old) * share
                    )
    return Texture(width, height, pixels^, REPEAT, BILINEAR, LINEAR)
