# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How a depth or a distance is written into the bytes of a pixel: three.js's
`packing.glsl`, and the four `DepthPacking` modes of `MeshDepthMaterial`.

A byte holds 256 steps. A depth written as one gray therefore keeps only
eight bits of itself. The packings spread one number across two, three or
four channels, eight more bits each, so that a byte image can carry a depth
to sixteen, twenty-four or thirty-two bits. The unpack functions read it
back.

**The arithmetic is three.js's, step for step, in Float32.** Every step
multiplies by a power of two or takes a fraction, and each of those is
exact in Float32. So a depth packed here and read back as bytes gives the
bytes three.js's shader gives. The one inexact step is the byte itself: the
last channel of each packing holds the fraction that is left, and a byte
rounds it.

Both rasterizers call `packed_depth_fragment` and `normalized_distance`,
the host from `render.rasterizer.rasterize_shaded` and the device from the
pixel kernel, so the two agree by construction.
"""

from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import floor, isfinite, max, min, sqrt

# three.js's `PackUpscale`, `Inv255`, `ShiftRight8` and `UnpackDownscale`.
comptime PACK_UPSCALE = Float32(256.0 / 255.0)
comptime INV_255 = Float32(1.0 / 255.0)
comptime SHIFT_RIGHT_8 = Float32(1.0 / 256.0)
comptime UNPACK_DOWNSCALE = Float32(255.0 / 256.0)
# three.js's `PackFactors`: one, and 256 to the first, second and third.
comptime PACK_FACTOR_G = Float32(256.0)
comptime PACK_FACTOR_B = Float32(65536.0)
comptime PACK_FACTOR_A = Float32(16777216.0)


@fieldwise_init
struct DepthPacking(Equatable, ImplicitlyCopyable, Writable):
    """How a `DEPTH` material writes its depth into a pixel, as a type
    rather than a bare int. three.js's `BasicDepthPacking` and the rest,
    with its numbering."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four depth packings.

        Returns:
            Whether the value names a depth packing.
        """
        return (
            self == BASIC_DEPTH_PACKING
            or self == RGBA_DEPTH_PACKING
            or self == RGB_DEPTH_PACKING
            or self == RG_DEPTH_PACKING
        )


# One minus the depth in every channel, and the opacity as the alpha: near
# white, far black. three.js's `BasicDepthPacking`, and its default.
comptime BASIC_DEPTH_PACKING = DepthPacking(3200)
# The depth across all four channels, 32 bits: `pack_depth_to_rgba`.
comptime RGBA_DEPTH_PACKING = DepthPacking(3201)
# The depth across red, green and blue, 24 bits, and an alpha of one:
# `pack_depth_to_rgb`.
comptime RGB_DEPTH_PACKING = DepthPacking(3202)
# The depth across red and green, 16 bits, a blue of zero and an alpha of
# one: `pack_depth_to_rg`.
comptime RG_DEPTH_PACKING = DepthPacking(3203)


def pack_depth_to_rgba(v: Float32) -> SIMD[DType.float32, 4]:
    """Return a number from zero to one spread across four channels,
    three.js's `packDepthToRGBA`.

    Red holds the top eight bits, green the next eight, blue the next
    eight, and alpha the fraction that is left. Zero and below is all zero;
    one and above is all one.

    Args:
        v: The number to pack, nominally zero to one.

    Returns:
        Red, green, blue and alpha, each zero to one.
    """
    if v <= 0:
        return SIMD[DType.float32, 4](0, 0, 0, 0)
    if v >= 1:
        return SIMD[DType.float32, 4](1, 1, 1, 1)
    var scaled = v * PACK_FACTOR_A
    var whole = floor(scaled)
    var af = scaled - whole
    scaled = whole * SHIFT_RIGHT_8
    whole = floor(scaled)
    var bf = scaled - whole
    scaled = whole * SHIFT_RIGHT_8
    whole = floor(scaled)
    var gf = scaled - whole
    return SIMD[DType.float32, 4](
        whole * INV_255, gf * PACK_UPSCALE, bf * PACK_UPSCALE, af
    )


def pack_depth_to_rgb(v: Float32) -> Vector3:
    """Return a number from zero to one spread across three channels,
    three.js's `packDepthToRGB`.

    Red holds the top eight bits, green the next eight, and blue the
    fraction that is left. Zero and below is all zero; one and above is
    all one.

    Args:
        v: The number to pack, nominally zero to one.

    Returns:
        Red, green and blue in x, y and z, each zero to one.
    """
    if v <= 0:
        return Vector3(0, 0, 0)
    if v >= 1:
        return Vector3(1, 1, 1)
    var scaled = v * PACK_FACTOR_B
    var whole = floor(scaled)
    var bf = scaled - whole
    scaled = whole * SHIFT_RIGHT_8
    whole = floor(scaled)
    var gf = scaled - whole
    return Vector3(whole * INV_255, gf * PACK_UPSCALE, bf)


def pack_depth_to_rg(v: Float32) -> Vector2:
    """Return a number from zero to one spread across two channels,
    three.js's `packDepthToRG`.

    Red holds the top eight bits, and green the fraction that is left.
    Zero and below is both zero; one and above is both one.

    Args:
        v: The number to pack, nominally zero to one.

    Returns:
        Red and green in x and y, each zero to one.
    """
    if v <= 0:
        return Vector2(0, 0)
    if v >= 1:
        return Vector2(1, 1)
    var scaled = v * PACK_FACTOR_G
    var whole = floor(scaled)
    return Vector2(whole * INV_255, scaled - whole)


def unpack_rgba_to_depth(packed: SIMD[DType.float32, 4]) -> Float32:
    """Return the number four channels hold, three.js's `unpackRGBAToDepth`.

    Args:
        packed: Red, green, blue and alpha, each zero to one.

    Returns:
        The number, zero to one.
    """
    return (
        packed[0] * UNPACK_DOWNSCALE
        + packed[1] * (UNPACK_DOWNSCALE / PACK_FACTOR_G)
        + packed[2] * (UNPACK_DOWNSCALE / PACK_FACTOR_B)
        + packed[3] * (1 / PACK_FACTOR_A)
    )


def unpack_rgb_to_depth(packed: Vector3) -> Float32:
    """Return the number three channels hold, three.js's `unpackRGBToDepth`.

    Args:
        packed: Red, green and blue in x, y and z, each zero to one.

    Returns:
        The number, zero to one.
    """
    return (
        packed.x * UNPACK_DOWNSCALE
        + packed.y * (UNPACK_DOWNSCALE / PACK_FACTOR_G)
        + packed.z * (1 / PACK_FACTOR_B)
    )


def unpack_rg_to_depth(packed: Vector2) -> Float32:
    """Return the number two channels hold, three.js's `unpackRGToDepth`.

    Args:
        packed: Red and green in x and y, each zero to one.

    Returns:
        The number, zero to one.
    """
    return packed.x * UNPACK_DOWNSCALE + packed.y * (1 / PACK_FACTOR_G)


def window_depth(z: Float32) -> Float32:
    """Return an NDC depth as the window-space depth, three.js's
    `fragCoordZ`: zero at the near plane and one at the far.

    Args:
        z: The NDC depth, -1 at the near plane and 1 at the far.

    Returns:
        Half of it plus a half.
    """
    return z * 0.5 + 0.5


def packed_depth_fragment(
    packing: DepthPacking, z: Float32, alpha: Float32
) -> SIMD[DType.float32, 4]:
    """Return the four channels a `DEPTH` material writes for a fragment,
    three.js's `depth.glsl` fragment shader.

    `BASIC_DEPTH_PACKING` writes one minus the window-space depth in every
    channel and keeps the alpha. The other three write the depth packed,
    with an alpha of one where the packing leaves the alpha free.

    Args:
        packing: The material's packing. A value that is none of the four
            writes as `BASIC_DEPTH_PACKING`; the boundaries refuse one.
        z: The fragment's NDC depth.
        alpha: The fragment's alpha, which only the basic packing keeps.

    Returns:
        Red, green, blue and alpha, each zero to one.
    """
    var depth = window_depth(z)
    if packing == RGBA_DEPTH_PACKING:
        return pack_depth_to_rgba(depth)
    if packing == RGB_DEPTH_PACKING:
        var rgb = pack_depth_to_rgb(depth)
        return SIMD[DType.float32, 4](rgb.x, rgb.y, rgb.z, 1)
    if packing == RG_DEPTH_PACKING:
        var rg = pack_depth_to_rg(depth)
        return SIMD[DType.float32, 4](rg.x, rg.y, 0, 1)
    var gray = 1 - depth
    return SIMD[DType.float32, 4](gray, gray, gray, alpha)


def normalized_distance(
    world: Vector3, reference: Vector3, near: Float32, far: Float32
) -> Float32:
    """Return how far a point is from a reference point, as a fraction of
    the way from `near` to `far`: three.js's `distance.glsl` fragment
    shader, before it packs.

    Args:
        world: The point, in world space.
        reference: The reference point, in world space.
        near: The distance that maps to zero, in meters.
        far: The distance that maps to one, in meters. Greater than `near`;
            the boundaries refuse anything else.

    Returns:
        The fraction, clamped to zero to one.
    """
    var dx = world.x - reference.x
    var dy = world.y - reference.y
    var dz = world.z - reference.z
    var dist = sqrt(dx * dx + dy * dy + dz * dz)
    var fraction = (dist - near) / (far - near)
    return min(max(fraction, Float32(0)), Float32(1))


def packed_distance_fragment(
    world: Vector3, reference: Vector3, near: Float32, far: Float32
) -> SIMD[DType.float32, 4]:
    """Return the four channels a `DISTANCE` material writes for a fragment:
    `normalized_distance` packed by `pack_depth_to_rgba`, as three.js
    r180's `distance.glsl` writes it.

    Args:
        world: The fragment's position, in world space.
        reference: The reference point, in world space.
        near: The distance that maps to zero, in meters.
        far: The distance that maps to one, in meters.

    Returns:
        Red, green, blue and alpha, each zero to one.
    """
    return pack_depth_to_rgba(normalized_distance(world, reference, near, far))


def check_distance_range(
    reference: Vector3, near: Float32, far: Float32
) raises:
    """Refuse a reference point or a range a `DISTANCE` surface cannot
    measure by.

    Shared by the material and by both rasterizers' triangle checks, so
    none of them accepts what another refuses.

    Args:
        reference: The reference point, in world space.
        near: The distance that maps to zero, in meters.
        far: The distance that maps to one, in meters.

    Raises:
        Error: If any coordinate of the reference point is not finite,
            `near` is negative or not finite, or `far` is not finite or not
            greater than `near`, which would divide by zero or turn the
            fraction around.
    """
    if (
        not isfinite(reference.x)
        or not isfinite(reference.y)
        or not isfinite(reference.z)
    ):
        raise Error("A distance's reference position must be finite")
    if not isfinite(near) or near < 0:
        raise Error("A near distance must be finite and not negative")
    if not isfinite(far) or far <= near:
        raise Error("A far distance must be finite and past the near one")
