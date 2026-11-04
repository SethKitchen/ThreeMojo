# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The air of a finished frame: the glow round bright light, and the mist
that lies low on the ground.

Both work on a finished frame, after the triangles and the water, and
before the frame is stretched to the window:

1. **Bloom.** `bloom` finds the light brighter than a threshold: lamps,
   lit windows, fire, glints and lightning. It blurs that light over a
   frame a quarter of the size, and adds it back, so bright light glows
   into what is round it.
2. **Ground mist.** `ground_mist` veils each pixel by how low and how far
   its point is. The mist is thickest on the ground and thins over
   `MIST_HEIGHT` above it. It fades in over distance, so the near ground
   stays clear. It lies in the fog's color.
"""

from cameras.perspective_camera import PerspectiveCamera
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor, Framebuffer
from std.math import exp, isinf

comptime BLOOM_SCALE = 4
"""How many pixels across and down of the frame one texel of the bloom's
blur covers."""
comptime BLOOM_REACH = 3
"""How many texels of the blur each side of a texel its box takes, in
each of its two passes."""
comptime MIST_HEIGHT = Float32(2.5)
"""How far above its base the ground mist thins to a third, in meters."""
comptime MIST_NEAR = Float32(25)
"""How far away, in meters, the ground mist has come in to two thirds."""


def _box(source: List[Float32], w: Int, h: Int, across: Bool) -> List[Float32]:
    """Return a box blur of three floats a texel, along one axis."""
    var blurred = List[Float32](length=len(source), fill=0)
    var span = Float32(2 * BLOOM_REACH + 1)
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            var r = Float32(0)
            var g = Float32(0)
            var b = Float32(0)
            for k in range(-BLOOM_REACH, BLOOM_REACH + 1):  # pragma: no branch
                var sx = x + k if across else x
                var sy = y if across else y + k
                sx = min(w - 1, max(0, sx))
                sy = min(h - 1, max(0, sy))
                var at = (sy * w + sx) * 3
                r += source[at]
                g += source[at + 1]
                b += source[at + 2]
            var p = (y * w + x) * 3
            blurred[p] = r / span
            blurred[p + 1] = g / span
            blurred[p + 2] = b / span
    return blurred^


def bloom(
    mut image: Framebuffer, threshold: Float32, strength: Float32
) raises -> Int:
    """Make the light brighter than a threshold glow into what is round it.

    Args:
        image: The frame. Its pixels are changed.
        threshold: The linear light, from 0 to 1, above which a pixel
            glows.
        strength: How much of the blurred light is added back, from 0 to
            4.

    Returns:
        How many pixels were bright enough to glow.

    Raises:
        Error: If the threshold is not from 0 to below 1, or the strength
            is not from 0 to 4.
    """
    if not (threshold >= 0 and threshold < 1):
        raise Error("A bloom's threshold must be from 0 to below 1")
    if not (strength >= 0 and strength <= 4):
        raise Error("A bloom's strength must be from 0 to 4")
    var w = image.width
    var h = image.height
    var sw = (w + BLOOM_SCALE - 1) // BLOOM_SCALE
    var sh = (h + BLOOM_SCALE - 1) // BLOOM_SCALE
    var small = List[Float32](length=sw * sh * 3, fill=0)
    var bright = 0
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            var c = FloatColor(srgb=image.get_pixel(x, y))
            var peak = max(c.r, max(c.g, c.b))
            if peak <= threshold:
                continue
            bright += 1
            # Only the light past the threshold glows.
            var keep = (peak - threshold) / (1 - threshold) / peak
            var at = ((y // BLOOM_SCALE) * sw + x // BLOOM_SCALE) * 3
            var share = 1 / Float32(BLOOM_SCALE * BLOOM_SCALE)
            small[at] += c.r * keep * share
            small[at + 1] += c.g * keep * share
            small[at + 2] += c.b * keep * share
    if bright == 0 or strength == 0:
        return bright
    var blurred = _box(_box(small, sw, sh, True), sw, sh, False)
    blurred = _box(_box(blurred, sw, sh, True), sw, sh, False)
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            var at = ((y // BLOOM_SCALE) * sw + x // BLOOM_SCALE) * 3
            var add_r = blurred[at] * strength
            var add_g = blurred[at + 1] * strength
            var add_b = blurred[at + 2] * strength
            if add_r + add_g + add_b <= 1.0e-4:
                continue
            var c = FloatColor(srgb=image.get_pixel(x, y))
            var glowing = FloatColor(
                min(Float32(1), c.r + add_r),
                min(Float32(1), c.g + add_g),
                min(Float32(1), c.b + add_b),
            ).encode()
            var p = (y * w + x) * 4
            image.pixels[p] = glowing.r
            image.pixels[p + 1] = glowing.g
            image.pixels[p + 2] = glowing.b
    return bright


def ground_mist(
    mut image: Framebuffer,
    camera: PerspectiveCamera,
    base: Float32,
    thickness: Float32,
    color: Color,
) raises -> Int:
    """Veil a frame with mist that lies low on the ground.

    A pixel's point is found from its depth. Its veil is `thickness`,
    thinned by how far its point stands above `base` and by how near it
    is. A pixel of the sky keeps its color.

    Args:
        image: The frame, with a depth for each pixel. Its pixels are
            changed.
        camera: The camera that drew it, placed.
        base: The height of the mist's base, in meters.
        thickness: How much of a far, low point the mist hides, from 0 to
            1.
        color: The mist's color, in sRGB.

    Returns:
        How many pixels the mist veiled.

    Raises:
        Error: If the frame has no depth for each pixel, the thickness is
            not from 0 to 1, or the camera's matrices cannot be inverted.
    """
    var w = image.width
    var h = image.height
    if len(image.depth) != w * h:
        raise Error("A frame needs a depth for each pixel")
    if not (thickness >= 0 and thickness <= 1):
        raise Error("A mist's thickness must be from 0 to 1")
    if thickness == 0:
        return 0
    var inverse = camera.projection_matrix()
    inverse.multiply(camera.view_matrix())
    inverse.invert()
    var eye = camera.position
    var mist = FloatColor(srgb=color)
    var veiled = 0
    for y in range(h):  # pragma: no branch
        var ny = 1 - (Float32(y) + 0.5) / Float32(h) * 2
        for x in range(w):  # pragma: no branch
            var k = y * w + x
            var z = image.depth[k]
            if isinf(z):
                continue
            var nx = (Float32(x) + 0.5) / Float32(w) * 2 - 1
            var at = inverse.transform_point(Vector3(nx, ny, z))
            var high = max(Float32(0), at.y - base)
            var far = (at - eye).length()
            var share = (
                thickness
                * exp(-high / MIST_HEIGHT)
                * (1 - exp(-far / MIST_NEAR))
            )
            if share <= 1.0e-3:
                continue
            veiled += 1
            var c = FloatColor(srgb=image.get_pixel(x, y))
            var veil = FloatColor(
                c.r + (mist.r - c.r) * share,
                c.g + (mist.g - c.g) * share,
                c.b + (mist.b - c.b) * share,
            ).encode()
            var p = k * 4
            image.pixels[p] = veil.r
            image.pixels[p + 1] = veil.g
            image.pixels[p + 2] = veil.b
    return veiled
