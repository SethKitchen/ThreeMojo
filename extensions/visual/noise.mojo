# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shared tileable value noise, height-field normal maps and surface sets.

Both civil-works visual helpers (`extensions.visual.textures`) and CARLA
town surface builders (`extensions.carla.render_textures`) build repeating
color, roughness and tangent-space normal maps from these primitives without
coupling `extensions.visual` to `extensions.carla`.
"""

from math.vector2 import Vector2
from render.srgb import LINEAR, ColorSpace
from render.texture import BILINEAR, IGNORED, REPEAT, Texture
from std.math import floor, sqrt
from units.si import METER, Length


@fieldwise_init
struct SurfaceMaps(Movable):
    """A surface's color, roughness and normal textures, and an emissive map."""

    var color: Texture
    var roughness: Texture
    var normal: Texture
    var emissive: Texture


def check_texture_side(size: Int) raises:
    """Refuse a texture of no texels, or one whose RGBA buffer overflows `Int`.

    Args:
        size: Texels on a side.

    Raises:
        Error: If `size` is less than one, or `4 * size * size` overflows.
    """
    if size < 1:
        raise Error("A texture needs at least one texel on a side")
    if size > (Int.MAX // 4) // size:
        raise Error("A texture is larger than this port builds")


def hash2(x: Int, y: Int, seed: Int) -> Float32:
    """Return a deterministic number in `[0, 1)` for a lattice point.

    Args:
        x: The column.
        y: The row.
        seed: Which field.

    Returns:
        A number in `[0, 1)`.
    """
    var h = UInt32(x * 374761393 + y * 668265263 + seed * 144269504)
    h = (h ^ (h >> 13)) * UInt32(1274126177)
    h = h ^ (h >> 16)
    return Float32(h & 0xFFFFFF) / Float32(16777216)


def tile_noise(u: Float32, v: Float32, period: Int, seed: Int) -> Float32:
    """Return value noise that repeats every `period` lattice cells.

    Args:
        u: Across, in lattice cells.
        v: Down, in lattice cells.
        period: How many cells before the noise repeats; one or more.
        seed: Which field.

    Returns:
        A number from zero to one.
    """
    var fx = floor(u)
    var fy = floor(v)
    var tx = u - fx
    var ty = v - fy
    var x0 = Int(fx) % period
    var y0 = Int(fy) % period
    var x1 = (x0 + 1) % period
    var y1 = (y0 + 1) % period
    var sx = tx * tx * (3 - 2 * tx)
    var sy = ty * ty * (3 - 2 * ty)
    var top = (
        hash2(x0, y0, seed) + (hash2(x1, y0, seed) - hash2(x0, y0, seed)) * sx
    )
    var bottom = (
        hash2(x0, y1, seed) + (hash2(x1, y1, seed) - hash2(x0, y1, seed)) * sx
    )
    return top + (bottom - top) * sy


def tile_fbm(
    u: Float32, v: Float32, period: Int, octaves: Int, seed: Int
) -> Float32:
    """Return fractal value noise that repeats over the unit square.

    Args:
        u: Across, zero to one over the tile.
        v: Down, zero to one over the tile.
        period: The first octave's cells across the tile.
        octaves: How many octaves.
        seed: Which field.

    Returns:
        A number from zero to one; zero for no octave.
    """
    var total = Float32(0)
    var weight = Float32(0.5)
    var norm = Float32(0)
    var cells = period
    for octave in range(octaves):
        total += weight * tile_noise(
            u * Float32(cells), v * Float32(cells), cells, seed + octave
        )
        norm += weight
        weight *= 0.5
        cells *= 2
    return total / max(norm, Float32(1e-30))


def _byte(value: Float32) -> UInt8:
    """Return a share from zero to one as a byte."""
    return UInt8(Int(min(max(value, 0), 1) * 255 + 0.5))


def _rgba(mut pixels: List[UInt8], r: Float32, g: Float32, b: Float32):
    """Append one opaque texel."""
    pixels.extend([_byte(r), _byte(g), _byte(b), 255])


def _square_texture(
    size: Int, var pixels: List[UInt8], space: ColorSpace
) raises -> Texture:
    """Return a repeating, mipmapped square texture."""
    return Texture(size, size, pixels^, REPEAT, BILINEAR, space, True, IGNORED)


def normal_map(
    heights: List[Float32], size: Int, strength: Float32
) raises -> Texture:
    """Return a tangent-space normal map from a height field that tiles.

    Args:
        heights: One height per texel, row by row from the top.
        size: Texels on a side.
        strength: How steep one unit of height across one texel is.

    Returns:
        A linear, repeating, mipmapped texture: x right, y up, z out,
        each from -1 to 1 stored from 0 to 255.

    Raises:
        Error: If `size` is less than one, its texel buffer does not fit,
            or the heights are not `size * size`.
    """
    check_texture_side(size)
    if len(heights) != size * size:
        raise Error("A height field needs one height per texel")
    var pixels = List[UInt8](capacity=size * size * 4)
    # The size is checked to be one or more.
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            var dx = (
                heights[y * size + (x + 1) % size]
                - heights[y * size + (x + size - 1) % size]
            )
            var dy = (
                heights[((y + size - 1) % size) * size + x]
                - heights[((y + 1) % size) * size + x]
            )
            var nx = -dx * strength
            var ny = -dy * strength
            var inverse = 1 / sqrt(nx * nx + ny * ny + 1)
            _rgba(
                pixels,
                nx * inverse * 0.5 + 0.5,
                ny * inverse * 0.5 + 0.5,
                inverse * 0.5 + 0.5,
            )
    return _square_texture(size, pixels^, LINEAR)


def place(mut maps: SurfaceMaps, meters: Length):
    """Make a surface's textures repeat every `meters` along each axis.

    Args:
        maps: The textures.
        meters: How far one tile reaches along each axis.
    """
    var scale = 1 / meters.to(METER)
    maps.color.repeat = Vector2(scale, scale)
    maps.roughness.repeat = Vector2(scale, scale)
    maps.normal.repeat = Vector2(scale, scale)
    maps.emissive.repeat = Vector2(scale, scale)
