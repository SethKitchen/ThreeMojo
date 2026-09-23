# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How a prefiltered environment is laid out and read, from three.js's
`cube_uv_reflection_fragment`.

A PMREM holds one environment many times over, each copy blurred for one
roughness, in a single flat image three.js calls the cube UV layout. Each
copy is six square tiles, three across and two up. The sharpest copy is
`2^lod_max` texels a side and sits at the bottom left; each copy above it
is half the size, down to sixteen texels; six more copies of sixteen
texels sit beside the last one, each blurrier than the one before, for the
roughest surfaces. So the whole image is `3 * max(2^lod_max, 112)` texels
wide and `4 * 2^lod_max` tall.

A "mip" here counts the other way from a mip chain: it is the base-two
logarithm of a tile's size, so `lod_max` is the sharpest copy and four the
first sixteen-texel one. Mips below four, down to minus two, name the six
extra copies. `roughness_to_mip` is three.js's table from a roughness to a
mip, and `textureCubeUV` reads the two copies either side of it and mixes
them, which is `cube_uv_taps` here.

Every tile keeps a one-texel border of what lies past its edge, in the
directions the next face holds, which `generate` fills because it writes
every texel from its own direction. `cube_uv_coordinate` maps a face onto
the inner `size - 2` texels, three.js's "#25071", so the bilinear filter
never reads a neighbor tile.

**One image, three.js's orientation.** Each tile's orientation is three.js's
own, `getUV` and `getDirection`, not `render.cube_texture`'s: the layout is
internal to a PMREM, and matching three.js exactly keeps its arithmetic
comparable line by line. The directions are world directions; the faces
are what the environment looks like in them.

Pure arithmetic, shared by both rasterizers: the host samples the image
with `Texture.sample` at the coordinates these return, and the kernel with
its own `_sample_at`, and both mix with `mix_color`.
"""

from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import FloatColor
from render.texture import Texture, mix_color
from std.math import exp2, floor, log2, max, min

# The smallest tile, as a mip and in texels: three.js's
# `cubeUV_minMipLevel` and `cubeUV_minTileSize`.
comptime CUBE_UV_MIN_MIP = 4
comptime CUBE_UV_MIN_TILE = 16
# The blurriest copy's mip, three.js's `cubeUV_m0`: roughness one.
comptime CUBE_UV_LOWEST_MIP = Float32(-2)
# How many sixteen-texel copies the layout holds past the halvings: the
# length of three.js's `EXTRA_LOD_SIGMA`.
comptime CUBE_UV_EXTRA_COPIES = 6


def cube_uv_face(direction: Vector3) -> Int:
    """Return which face a direction lands on in the cube UV layout:
    three.js's `getFace`.

    Zero to five for positive x, positive y, positive z, negative x,
    negative y, negative z: three.js's PMREM order, not
    `render.cube_texture`'s. A tie is broken as three.js breaks it, by its
    strict comparisons.

    Args:
        direction: Any vector.

    Returns:
        The face, zero to five.
    """
    var ax = abs(direction.x)
    var ay = abs(direction.y)
    var az = abs(direction.z)
    if ax > az:
        if ax > ay:
            return 0 if direction.x > 0 else 3
        return 1 if direction.y > 0 else 4
    if az > ay:
        return 2 if direction.z > 0 else 5
    return 1 if direction.y > 0 else 4


def cube_uv_face_uv(direction: Vector3, face: Int) -> Vector2:
    """Return where a direction lands on one face, from zero to one:
    three.js's `getUV`.

    Args:
        direction: Any vector; it need not be unit length.
        face: The face `cube_uv_face` chose for it.

    Returns:
        The coordinate. The middle of the face for a direction with no
        length along the face's axis, which only the zero vector has for
        the face it is given; three.js divides by zero there.
    """
    var along: Float32
    var across: Float32
    var up: Float32
    if face == 0 or face == 3:
        along = abs(direction.x)
        across = direction.z if face == 0 else -direction.z
        up = direction.y
    elif face == 1 or face == 4:
        along = abs(direction.y)
        across = -direction.x
        up = -direction.z if face == 1 else direction.z
    else:
        along = abs(direction.z)
        across = -direction.x if face == 2 else direction.x
        up = direction.y
    if along == 0:
        return Vector2(0.5, 0.5)
    return Vector2(0.5 * (across / along + 1), 0.5 * (up / along + 1))


def cube_uv_direction(u: Float32, v: Float32, face: Int) -> Vector3:
    """Return the direction through a place on one face: three.js's
    `getDirection` in the PMREM vertex shader, the inverse of
    `cube_uv_face_uv`.

    Args:
        u: Across the face, zero to one; a border texel lies outside.
        v: Up the face, zero to one.
        face: Zero to five, in `cube_uv_face`'s order.

    Returns:
        The direction, one unit along the face's axis, not normalized.
    """
    var s = 2 * u - 1
    var t = 2 * v - 1
    if face == 0:
        return Vector3(1, t, s)
    if face == 1:
        return Vector3(-s, 1, -t)
    if face == 2:
        return Vector3(-s, t, 1)
    if face == 3:
        return Vector3(-1, t, -s)
    if face == 4:
        return Vector3(-s, -1, t)
    return Vector3(s, t, -1)


def roughness_to_mip(roughness: Float32) -> Float32:
    """Return the mip a roughness reads, before it is clamped: three.js's
    `roughnessToMip`.

    Straight lines between five knots from roughness 0.21 to one, and below
    0.21 the curve `-2 * log2(1.16 * roughness)`, which is where the halving
    copies are. Roughness one reads mip minus two, the blurriest copy, and
    roughness zero reads infinity, which the caller clamps to the sharpest.

    Args:
        roughness: From zero to one.

    Returns:
        The mip, which can be infinite at zero.
    """
    if roughness >= 0.8:
        return (1.0 - roughness) * (-1.0 - -2.0) / (1.0 - 0.8) + -2.0
    if roughness >= 0.4:
        return (0.8 - roughness) * (2.0 - -1.0) / (0.8 - 0.4) + -1.0
    if roughness >= 0.305:
        return (0.4 - roughness) * (3.0 - 2.0) / (0.4 - 0.305) + 2.0
    if roughness >= 0.21:
        return (0.305 - roughness) * (4.0 - 3.0) / (0.305 - 0.21) + 3.0
    return -2.0 * log2(1.16 * roughness)


def cube_uv_lod_max(height: Int) -> Int:
    """Return the sharpest copy's mip from the layout's height, which is
    four of its tiles: three.js's `CUBEUV_MAX_MIP`.

    Args:
        height: The layout image's height in texels, `4 * 2^lod_max`.

    Returns:
        `lod_max`, the base-two logarithm of a quarter of the height,
        rounded down.
    """
    var lod = 0
    while (4 << (lod + 1)) <= height:
        lod += 1
    return lod


def cube_uv_coordinate(
    direction: Vector3, mip: Float32, lod_max: Int, width: Int, height: Int
) -> Vector2:
    """Return where one copy holds a direction, as a texture coordinate on
    the layout image: three.js's `bilinearCubeUV` up to the read.

    Args:
        direction: Any vector.
        mip: A whole mip, from minus two to `lod_max`.
        lod_max: The sharpest copy's mip, `cube_uv_lod_max`.
        width: The layout image's width in texels.
        height: The layout image's height in texels.

    Returns:
        `u` from the left and `v` from the bottom, both zero to one, as
        `Texture.sample` reads them.
    """
    var face = cube_uv_face(direction)
    var filter_int = max(Float32(CUBE_UV_MIN_MIP) - mip, Float32(0))
    var level = max(mip, Float32(CUBE_UV_MIN_MIP))
    var face_size = exp2(level)
    var uv = cube_uv_face_uv(direction, face)
    var x = uv.x * (face_size - 2) + 1
    var y = uv.y * (face_size - 2) + 1
    var column = face
    if face > 2:
        y += face_size
        column -= 3
    x += Float32(column) * face_size
    x += filter_int * 3 * Float32(CUBE_UV_MIN_TILE)
    y += 4 * (exp2(Float32(lod_max)) - face_size)
    return Vector2(x * (1 / Float32(width)), y * (1 / Float32(height)))


@fieldwise_init
struct CubeUvTaps(ImplicitlyCopyable):
    """The one or two places `textureCubeUV` reads, and how far to mix."""

    # Where the copy at the mip rounded down holds the direction.
    var near: Vector2
    # Where the next sharper copy holds it. Read only when `blend` is not
    # zero, as three.js skips the second read.
    var far: Vector2
    # How far from `near` toward `far`, three.js's `mipF`.
    var blend: Float32


def cube_uv_taps(
    direction: Vector3, roughness: Float32, width: Int, height: Int
) -> CubeUvTaps:
    """Return where a direction is read at a roughness: three.js's
    `textureCubeUV` up to the reads.

    The mip `roughness_to_mip` gives, clamped between minus two and the
    sharpest copy, then split into a whole part and a fraction.

    Args:
        direction: Any vector.
        roughness: From zero to one.
        width: The layout image's width in texels.
        height: The layout image's height in texels.

    Returns:
        The two places and the mix between them.
    """
    var lod_max = cube_uv_lod_max(height)
    var mip = min(
        max(roughness_to_mip(roughness), CUBE_UV_LOWEST_MIP),
        Float32(lod_max),
    )
    var whole = floor(mip)
    return CubeUvTaps(
        cube_uv_coordinate(direction, whole, lod_max, width, height),
        cube_uv_coordinate(direction, whole + 1, lod_max, width, height),
        mip - whole,
    )


def sample_cube_uv(
    image: Texture, direction: Vector3, roughness: Float32
) -> FloatColor:
    """Return the environment a roughness sees in a direction: three.js's
    `textureCubeUV`, on the host.

    The kernel's `_sample_cube_uv` reads the same taps from the same
    image. Alpha is one, as three.js's is.

    Args:
        image: The layout image, a PMREM's `cube_uv`.
        direction: Any vector.
        roughness: From zero to one.

    Returns:
        The light, linear.
    """
    var taps = cube_uv_taps(direction, roughness, image.width, image.height)
    var near = image.sample(taps.near.x, taps.near.y)
    if taps.blend == 0:
        return FloatColor(near.r, near.g, near.b, 1.0)
    var far = image.sample(taps.far.x, taps.far.y)
    var mixed = mix_color(near, far, taps.blend)
    return FloatColor(mixed.r, mixed.g, mixed.b, 1.0)
