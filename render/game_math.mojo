# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The arithmetic that the renderers share, written once for any SIMD
width.

The general CPU rasterizer and the GPU kernel call these at width one,
through `render.tonemap` and `core.fog`. The game renderer calls them at
`GAME_LANES`, sixteen pixels or vertices at a time. Each function is the
same operations in the same order at every width, so each lane gives the
bits that the scalar call gives.
"""

from std.math import exp2, max, min, round

comptime GAME_LANES = 16
"""How many pixels or vertices the game renderer works on at once."""
comptime LOG2_E = Float32(1.4426950408889634)
"""`log2(e)`, to take `exp(x)` as `exp2(x * LOG2_E)`."""
comptime TWO_PI_HIGH = Float32(6.28125)
comptime TWO_PI_LOW = Float32(0.0019353071795864769)
"""Two pi as two floats, high and low, so the reduction of a large angle
keeps its low bits."""
comptime HALF_PI = Float32(1.5707963267948966)
comptime PI = Float32(3.141592653589793)


@always_inline
def fast_sin[w: Int](x: SIMD[DType.float32, w]) -> SIMD[DType.float32, w]:
    """Return the sine of each lane, within about 2e-7 for angles up to a
    few thousand radians.

    `std.math.sin` calls the C library once a lane. This reduces each
    angle to the half turn round zero, folds it to the quarter turn, and
    sums the sine's Taylor series to its eleventh power, all in vector
    instructions.

    Parameters:
        w: The SIMD width.

    Args:
        x: The angles, in radians.

    Returns:
        Their sines.
    """
    var turns = round(x * (1 / (TWO_PI_HIGH + TWO_PI_LOW)))
    var r = (x - turns * TWO_PI_HIGH) - turns * TWO_PI_LOW
    var high = r.gt(HALF_PI)
    var low = r.lt(-HALF_PI)
    r = high.select(PI - r, low.select(-PI - r, r))
    var r2 = r * r
    var series = 1 + r2 * (
        Float32(-1.0 / 6.0)
        + r2
        * (
            Float32(1.0 / 120.0)
            + r2
            * (
                Float32(-1.0 / 5040.0)
                + r2
                * (Float32(1.0 / 362880.0) + r2 * Float32(-1.0 / 39916800.0))
            )
        )
    )
    return r * series


@always_inline
def saturate_lanes[
    w: Int
](value: SIMD[DType.float32, w]) -> SIMD[DType.float32, w]:
    """Return each lane held from zero to one, as GLSL's `saturate`.

    `max(0, min(1, value))`, the operations of `math.utils.saturate` in
    its order, so a lane gives the bits that the scalar call gives.

    Parameters:
        w: The SIMD width.

    Args:
        value: The lanes.

    Returns:
        Each lane within zero and one.
    """
    return max(SIMD[DType.float32, w](0), min(SIMD[DType.float32, w](1), value))


@always_inline
def aces_fit[w: Int](v: SIMD[DType.float32, w]) -> SIMD[DType.float32, w]:
    """Return three.js's `RRTAndODTFit`, the ACES curve itself, on each lane.

    Parameters:
        w: The SIMD width.

    Args:
        v: One channel in the ACES working primaries.

    Returns:
        The fitted channel.
    """
    var a = v * (v + 0.0245786) - 0.000090537
    var b = v * (0.983729 * v + 0.4329510) + 0.238081
    return a / b


@always_inline
def aces_tone[
    w: Int
](
    r: SIMD[DType.float32, w],
    g: SIMD[DType.float32, w],
    b: SIMD[DType.float32, w],
    exposure: Float32,
) -> Tuple[
    SIMD[DType.float32, w], SIMD[DType.float32, w], SIMD[DType.float32, w]
]:
    """Return three.js's `ACESFilmicToneMapping` of linear light.

    Scaled by the exposure over 0.6, into the ACES working primaries by
    `ACESInputMat`, through `aces_fit`, back out by `ACESOutputMat`, and
    clamped.

    Parameters:
        w: The SIMD width.

    Args:
        r: The red channel, linear.
        g: The green channel, linear.
        b: The blue channel, linear.
        exposure: The exposure.

    Returns:
        The tone-mapped red, green and blue, each from zero to one.
    """
    var scale = exposure / 0.6
    var sr = r * scale
    var sg = g * scale
    var sb = b * scale
    var ir = 0.59719 * sr + 0.35458 * sg + 0.04823 * sb
    var ig = 0.07600 * sr + 0.90834 * sg + 0.01566 * sb
    var ib = 0.02840 * sr + 0.13383 * sg + 0.83777 * sb
    var fr = aces_fit(ir)
    var fg = aces_fit(ig)
    var fb = aces_fit(ib)
    return (
        saturate_lanes(1.60475 * fr - 0.53108 * fg - 0.07367 * fb),
        saturate_lanes(-0.10208 * fr + 1.10813 * fg - 0.00605 * fb),
        saturate_lanes(-0.00327 * fr - 0.07276 * fg + 1.07602 * fb),
    )


@always_inline
def exp2_veil[
    w: Int
](density: Float32, depth: SIMD[DType.float32, w]) -> SIMD[DType.float32, w]:
    """Return how much of an exponential-squared fog's color shows.

    Parameters:
        w: The SIMD width.

    Args:
        density: How fast the fog thickens.
        depth: The camera-space depth of each lane.

    Returns:
        `1 - exp(-(density * depth)^2)` for each lane, with the power
        taken as `exp2` of the exponent times `log2(e)`: `exp2` is one
        vector instruction on every width, and `exp` is a call a lane.
    """
    var scaled = density * depth
    return 1 - exp2(-(scaled * scaled) * LOG2_E)


@always_inline
def hemisphere_share[
    w: Int
](
    nx: SIMD[DType.float32, w],
    ny: SIMD[DType.float32, w],
    nz: SIMD[DType.float32, w],
    up: SIMD[DType.float32, 4],
) -> SIMD[DType.float32, w]:
    """Return how much of a hemisphere light's sky a surface takes.

    Parameters:
        w: The SIMD width.

    Args:
        nx: The unit normal's x, in world space.
        ny: Its y.
        nz: Its z.
        up: The sky's direction, in the first three lanes.

    Returns:
        `0.5 * dot(n, up) + 0.5`: one facing the sky, zero facing the
        ground.
    """
    return 0.5 * (nx * up[0] + ny * up[1] + nz * up[2]) + 0.5


@always_inline
def lambert[
    w: Int
](
    nx: SIMD[DType.float32, w],
    ny: SIMD[DType.float32, w],
    nz: SIMD[DType.float32, w],
    toward: SIMD[DType.float32, 4],
) -> SIMD[DType.float32, w]:
    """Return the cosine a surface catches a directional light by.

    Parameters:
        w: The SIMD width.

    Args:
        nx: The unit normal's x, in world space.
        ny: Its y.
        nz: Its z.
        toward: The unit direction toward the light, in the first three
            lanes.

    Returns:
        `max(dot(n, toward), 0)` for each lane.
    """
    var c = nx * toward[0] + ny * toward[1] + nz * toward[2]
    return c.gt(0).select(c, SIMD[DType.float32, w](0))
