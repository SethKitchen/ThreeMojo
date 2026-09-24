# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What three.js's `dithering`, `alphaHash` and `alphaToCoverage` do to one
fragment.

Both rasterizers call these functions, the host from
`render.rasterizer.rasterize_shaded` and the device from the pixel kernel,
so the two agree by construction.

**Dithering** is three.js's `dithering_pars_fragment`: a shift of a
quarter of a byte, up in red and blue and down in green, turned round by
`rand(gl_FragCoord.xy)`. three.js adds it to the encoded color. This port
encodes once, when a target is resolved, so `dither` adds the shift to the
encoded value and decodes the sum again. With no tone mapping, the
resolved byte is the one three.js writes. With a curve, the shift is
applied before the curve and not after it.

**Alpha hash** is three.js's `alphahash_pars_fragment`: the hashed alpha
test of Wyman and McGuire. three.js hashes the object-space position. A
corner here carries its world position and not its object-space one, so
`alpha_hash_threshold` hashes the world position. The noise stays fixed
to the world, and it moves across an object that moves.

**Alpha to coverage** is WebGL's `SAMPLE_ALPHA_TO_COVERAGE`. A GPU turns
the alpha into a mask of the pixel's samples. This port takes one sample a
pixel, or `SUPERSAMPLE` squared under `antialias`, so `alpha_covers` keeps a
sample where the alpha is above a four-by-four ordered threshold. After
the supersampled frame is averaged, a pixel's coverage follows its alpha.
"""

from materials.nodes import AT_HERE, AT_RIGHT, AT_UP, NodeSource
from materials.nodes import node_attributes
from math.vector3 import Vector3
from render.framebuffer import FloatColor
from render.srgb import linear_to_srgb, srgb_to_linear
from std.math import ceil, exp2, floor, log2, max, min, pi, sin

# three.js's `ALPHA_HASH_SCALE`.
comptime ALPHA_HASH_SCALE = Float32(0.05)
# The smallest threshold `alpha_hash_threshold` returns, three.js's clamp.
comptime MIN_HASH_THRESHOLD = Float32(1.0e-6)
# A quarter of one byte of the encoded color: three.js's dither step.
comptime DITHER_STEP = Float32(0.25 / 255.0)


@always_inline
def _fract(value: Float32) -> Float32:
    """Return the fractional part of `value`, GLSL's `fract`."""
    return value - floor(value)


@always_inline
def fragment_rand(x: Float32, y: Float32) -> Float32:
    """Return three.js's `rand` of a fragment coordinate.

    `fract(sin(mod(dot(uv, (12.9898, 78.233)), PI)) * 43758.5453)`, from
    three.js's `common` shader chunk.

    Args:
        x: The coordinate's first component.
        y: The second.

    Returns:
        A value from zero to one.
    """
    var dt = x * Float32(12.9898) + y * Float32(78.233)
    var turn = Float32(pi)
    var sn = dt - turn * floor(dt / turn)
    return _fract(sin(sn) * Float32(43758.5453))


@always_inline
def dither(color: FloatColor, x: Int, y: Int, height: Int) -> FloatColor:
    """Return a linear color with three.js's dither added to its encoding.

    three.js's `dithering`: at `gl_FragCoord`, the pixel's center counted
    from the bottom row, the encoded red and blue move by up to half a byte
    and the green the other way. The shift is added to the sRGB encoding
    of each channel and the sum is decoded again, so the target still holds
    light.

    Args:
        color: The fragment's linear color, straight alpha.
        x: The pixel's column.
        y: The pixel's row, counted from the top.
        height: The target's height in pixels.

    Returns:
        The dithered color, alpha kept.
    """
    var grid = fragment_rand(
        Float32(x) + Float32(0.5), Float32(height - y) - Float32(0.5)
    )
    # three.js's `mix(2 * shift, -2 * shift, grid)`.
    var shift = DITHER_STEP * (2 - 4 * grid)
    return FloatColor(
        srgb_to_linear(linear_to_srgb(color.r) + shift),
        srgb_to_linear(linear_to_srgb(color.g) - shift),
        srgb_to_linear(linear_to_srgb(color.b) + shift),
        color.a,
    )


@always_inline
def _hash2d(x: Float32, y: Float32) -> Float32:
    """Return three.js's `hash2D`."""
    return _fract(
        Float32(1.0e4)
        * sin(17 * x + Float32(0.1) * y)
        * (Float32(0.1) + abs(sin(13 * y + x)))
    )


@always_inline
def _hash3d(point: Vector3) -> Float32:
    """Return three.js's `hash3D`."""
    return _hash2d(_hash2d(point.x, point.y), point.z)


@always_inline
def alpha_hash_threshold(
    position: Vector3, across: Vector3, down: Vector3
) -> Float32:
    """Return the alpha below which a hashed fragment is thrown away.

    three.js's `getAlphaHashThreshold`, line for line: the noise is read at
    the two powers of two nearest the scale the position changes by across
    one pixel, mixed, and moved through the mix's distribution so the
    threshold is uniform from zero to one.

    Args:
        position: Where the fragment is.
        across: How far the position moves one pixel to the right,
            GLSL's `dFdx`.
        down: How far it moves one pixel up, GLSL's `dFdy`.

    Returns:
        The threshold, from one millionth to one.
    """
    var deriv = max(across.length(), down.length())
    var scale = 1 / (ALPHA_HASH_SCALE * deriv)
    var level = log2(scale)
    var low = exp2(floor(level))
    var high = exp2(ceil(level))
    var first = _hash3d(
        Vector3(
            floor(low * position.x),
            floor(low * position.y),
            floor(low * position.z),
        )
    )
    var second = _hash3d(
        Vector3(
            floor(high * position.x),
            floor(high * position.y),
            floor(high * position.z),
        )
    )
    var lerp = _fract(level)
    var x = (1 - lerp) * first + lerp * second
    var a = min(lerp, 1 - lerp)
    var threshold: Float32
    if x < 1 - a:
        if x < a:
            threshold = x * x / (2 * a * (1 - a))
        else:
            threshold = (x - Float32(0.5) * a) / (1 - a)
    else:
        threshold = 1 - ((1 - x) * (1 - x) / (2 * a * (1 - a)))
    return min(max(threshold, MIN_HASH_THRESHOLD), Float32(1))


def hashed_threshold[S: NodeSource](source: S) -> Float32:
    """Return `alpha_hash_threshold` for the fragment a triangle's source
    is at.

    The world position is interpolated at the fragment, at the pixel to
    its right and at the pixel above it, from the triangle's own plane, as
    a node's `dfdx` and `dfdy` are. Both rasterizers hand in their
    `NodeSource`, so the two differences are the same numbers.

    Args:
        source: The triangle, at the fragment.

    Returns:
        The threshold.
    """
    var here = node_attributes(source, AT_HERE, False).position
    var right = node_attributes(source, AT_RIGHT, False).position
    var up = node_attributes(source, AT_UP, False).position
    return alpha_hash_threshold(here, right - here, up - here)


# The four-by-four ordered dither matrix, each entry's rank from 0 to 15.
comptime _BAYER = SIMD[DType.int32, 16](
    0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5
)


@always_inline
def coverage_threshold(x: Int, y: Int) -> Float32:
    """Return the alpha a fragment must pass to cover the sample at a pixel.

    Args:
        x: The sample's column.
        y: The sample's row.

    Returns:
        `(rank + 0.5) / 16`, where `rank` is the pixel's place in a
        four-by-four ordered dither matrix.
    """
    var rank = _BAYER[(y & 3) * 4 + (x & 3)]
    return (Float32(rank) + Float32(0.5)) / 16


@always_inline
def alpha_covers(alpha: Float32, x: Int, y: Int) -> Bool:
    """Return True if a fragment's alpha covers the sample at a pixel.

    Args:
        alpha: The fragment's alpha.
        x: The sample's column.
        y: The sample's row.

    Returns:
        Whether the alpha is above `coverage_threshold`. An alpha of one
        covers every sample and an alpha of zero none.
    """
    return alpha > coverage_threshold(x, y)
