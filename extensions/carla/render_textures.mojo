# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Procedural textures for a CARLA town: asphalt, concrete, grass, facades.

Each surface is a set of three textures that tile: a color map in sRGB, a
roughness map whose green channel is the roughness, and a tangent-space
normal map. The road meshes carry texture coordinates in meters, so a
texture's `repeat` is one over the meters it covers.

**Noise.** The textures are built from value noise on a lattice that wraps,
so every texture tiles without a seam: a hash gives each lattice point a
number, and a smooth step blends the four around a texel. Fractal noise
sums octaves of it. This is the well-known construction of tileable noise.

**Normals.** A surface's height field is turned into normals by central
differences, which wrap as the texture does.

- **Asphalt** is dark gray with light and dark stones, a large-scale
  mottle and darker patches of repair.
- **Concrete** is square slabs with dark joints, each slab a little lighter
  or darker than the next.
- **Grass** is green and brown noise.
- **Foliage** is clumps of light and dark green leaves.
- **A facade** is a wall of plaster, brick or concrete panels with a grid
  of windows, or a shop front of dark stone with wide windows. The
  windows are smooth dark glass, and an emissive map marks which windows
  are lit at night.

The sizes and colors are this port's own choices.
"""

from math.smoothstep import smoothstep
from math.vector2 import Vector2
from render.srgb import LINEAR, SRGB, ColorSpace
from render.texture import BILINEAR, IGNORED, REPEAT, Texture
from std.math import floor, sqrt
from units.si import METER, Length


@fieldwise_init
struct SurfaceMaps(Movable):
    """A surface's color, roughness and normal textures, and the extra
    emissive texture of a facade."""

    var color: Texture
    var roughness: Texture
    var normal: Texture
    var emissive: Texture


def hash2(x: Int, y: Int, seed: Int) -> Float32:
    """Return a number from zero to one for a lattice point.

    An integer hash, the same on every platform: the point and the seed are
    mixed by multiplications and shifts in 32 bits.

    Args:
        x: The column.
        y: The row.
        seed: Which field.

    Returns:
        A number in [0, 1).
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

    Each octave doubles the lattice and halves the weight.

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
        Error: If `size` is less than one, or the heights are not
            `size * size`.
    """
    _check_size(size)
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
    return _texture(size, pixels^, LINEAR)


def _texture(
    size: Int, var pixels: List[UInt8], space: ColorSpace
) raises -> Texture:
    """Return a repeating, mipmapped square texture."""
    return Texture(size, size, pixels^, REPEAT, BILINEAR, space, True, IGNORED)


def _gray(size: Int, value: Float32, space: ColorSpace) raises -> Texture:
    """Return a square texture of one gray."""
    var pixels = List[UInt8](capacity=size * size * 4)
    # The size is checked to be one or more.
    for _ in range(size * size):  # pragma: no branch
        _rgba(pixels, value, value, value)
    return _texture(size, pixels^, space)


def place(mut maps: SurfaceMaps, meters: Length):
    """Make a surface's textures repeat every so many meters.

    Args:
        maps: The textures.
        meters: How far one tile reaches along each axis.
    """
    var scale = 1 / meters.to(METER)
    maps.color.repeat = Vector2(scale, scale)
    maps.roughness.repeat = Vector2(scale, scale)
    maps.normal.repeat = Vector2(scale, scale)
    maps.emissive.repeat = Vector2(scale, scale)


def asphalt_maps(size: Int, seed: Int = 1) raises -> SurfaceMaps:
    """Return asphalt: dark gray with stones, a mottle and repair patches.

    Args:
        size: Texels on a side.
        seed: Which asphalt.

    Returns:
        The maps; the emissive map is black.

    Raises:
        Error: If `size` is less than one.
    """
    _check_size(size)
    var color = List[UInt8](capacity=size * size * 4)
    var rough = List[UInt8](capacity=size * size * 4)
    var heights = List[Float32](capacity=size * size)
    var step = Float32(1) / Float32(size)
    # The size is checked to be one or more.
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            var u = Float32(x) * step
            var v = Float32(y) * step
            var grain = hash2(x, y, seed)
            var mottle = tile_fbm(u, v, 4, 4, seed + 11)
            var patch = smoothstep(0.62, 0.66, tile_fbm(u, v, 2, 3, seed + 29))
            var stone = smoothstep(0.86, 0.95, grain) - smoothstep(
                0.0, 0.06, 0.06 - grain
            )
            var tone = (
                Float32(0.3)
                + (mottle - 0.5) * 0.12
                + stone * 0.14
                - patch * 0.035
            )
            _rgba(color, tone, tone, tone * Float32(1.02))
            var r = (
                Float32(0.9) - stone * 0.25 - patch * 0.2 + (mottle - 0.5) * 0.1
            )
            _rgba(rough, r, r, r)
            heights.append(stone * 0.6 + grain * 0.25 + mottle * 0.3)
    return SurfaceMaps(
        _texture(size, color^, SRGB),
        _texture(size, rough^, LINEAR),
        normal_map(heights, size, 1.2),
        _gray(1, 0, SRGB),
    )


def concrete_maps(
    size: Int, slabs: Int = 2, seed: Int = 3
) raises -> SurfaceMaps:
    """Return concrete slabs with dark joints.

    Args:
        size: Texels on a side.
        slabs: Slabs on a side of the tile; one or more.
        seed: Which concrete.

    Returns:
        The maps; the emissive map is black.

    Raises:
        Error: If `size` or `slabs` is less than one.
    """
    _check_size(size)
    if slabs < 1:
        raise Error("A concrete tile needs at least one slab")
    var color = List[UInt8](capacity=size * size * 4)
    var rough = List[UInt8](capacity=size * size * 4)
    var heights = List[Float32](capacity=size * size)
    var step = Float32(1) / Float32(size)
    # The size is checked to be one or more.
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            var u = Float32(x) * step * Float32(slabs)
            var v = Float32(y) * step * Float32(slabs)
            var edge = min(
                min(u - floor(u), 1 - (u - floor(u))),
                min(v - floor(v), 1 - (v - floor(v))),
            )
            var joint = 1 - smoothstep(0.004, 0.012, edge)
            var slab = hash2(Int(floor(u)), Int(floor(v)), seed)
            var stain = tile_fbm(
                Float32(x) * step, Float32(y) * step, 3, 4, seed + 5
            )
            var fine = hash2(x, y, seed + 7)
            var tone = (
                Float32(0.55)
                + (slab - 0.5) * 0.08
                + (stain - 0.5) * 0.14
                + (fine - 0.5) * 0.04
                - joint * 0.25
            )
            _rgba(color, tone, tone * Float32(0.98), tone * Float32(0.94))
            var r = Float32(0.82) + (fine - 0.5) * 0.1
            _rgba(rough, r, r, r)
            heights.append(-joint * 0.8 + fine * 0.1)
    return SurfaceMaps(
        _texture(size, color^, SRGB),
        _texture(size, rough^, LINEAR),
        normal_map(heights, size, 1.5),
        _gray(1, 0, SRGB),
    )


def grass_maps(size: Int, seed: Int = 5) raises -> SurfaceMaps:
    """Return a lawn of green and brown noise.

    Args:
        size: Texels on a side.
        seed: Which lawn.

    Returns:
        The maps; the emissive map is black.

    Raises:
        Error: If `size` is less than one.
    """
    _check_size(size)
    var color = List[UInt8](capacity=size * size * 4)
    var rough = List[UInt8](capacity=size * size * 4)
    var heights = List[Float32](capacity=size * size)
    var step = Float32(1) / Float32(size)
    # The size is checked to be one or more.
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            var u = Float32(x) * step
            var v = Float32(y) * step
            var dry = tile_fbm(u, v, 3, 4, seed)
            var blade = hash2(x, y, seed + 3)
            var g = Float32(0.30) + (blade - 0.5) * 0.12
            _rgba(color, g * (Float32(0.55) + dry * 0.6), g, g * Float32(0.35))
            _rgba(rough, 0.95, 0.95, 0.95)
            heights.append(blade)
    return SurfaceMaps(
        _texture(size, color^, SRGB),
        _texture(size, rough^, LINEAR),
        normal_map(heights, size, 0.8),
        _gray(1, 0, SRGB),
    )


def foliage_maps(size: Int, seed: Int = 6) raises -> SurfaceMaps:
    """Return foliage: clumps of leaves in light and dark greens.

    Args:
        size: Texels on a side.
        seed: Which leaves.

    Returns:
        The maps; the emissive map is black.

    Raises:
        Error: If `size` is less than one.
    """
    _check_size(size)
    var color = List[UInt8](capacity=size * size * 4)
    var rough = List[UInt8](capacity=size * size * 4)
    var heights = List[Float32](capacity=size * size)
    var step = Float32(1) / Float32(size)
    # The size is checked to be one or more.
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            var u = Float32(x) * step
            var v = Float32(y) * step
            var clump = tile_fbm(u, v, 6, 3, seed)
            var leaf = tile_fbm(u, v, 24, 2, seed + 9)
            var light = smoothstep(0.35, 0.75, clump * 0.6 + leaf * 0.4)
            var g = Float32(0.24) + light * 0.26
            _rgba(color, g * 0.6, g, g * 0.3)
            _rgba(rough, 0.8, 0.8, 0.8)
            heights.append(clump * 0.7 + leaf * 0.5)
    return SurfaceMaps(
        _texture(size, color^, SRGB),
        _texture(size, rough^, LINEAR),
        normal_map(heights, size, 6),
        _gray(1, 0, SRGB),
    )


@fieldwise_init
struct FacadeStyle(Equatable, ImplicitlyCopyable, Writable):
    """What a building's wall is made of."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for one of the four styles.

        Returns:
            Whether the value is from 0 to 3.
        """
        return self.value >= 0 and self.value <= 3

    def write_to(self, mut writer: Some[Writer]):
        """Write the style's number.

        Args:
            writer: The destination.
        """
        writer.write("FacadeStyle(", self.value, ")")


# Pale plaster.
comptime PLASTER = FacadeStyle(0)
# Red brick.
comptime BRICK = FacadeStyle(1)
# Gray concrete panels.
comptime PANELS = FacadeStyle(2)
# A ground floor of shop windows under a sign band, in dark stone.
comptime SHOPFRONT = FacadeStyle(3)
# The meters a facade tile covers: four bays of 3 m and four floors of 3 m.
comptime FACADE_TILE = Length(12, METER)


def wall_color(
    style: FacadeStyle, u: Float32, v: Float32, grain: Float32
) raises -> Tuple[Float32, Float32, Float32]:
    """Return the sRGB color of a facade's wall, away from the windows.

    Args:
        style: The wall.
        u: Across the tile, in meters.
        v: Down the tile, in meters.
        grain: A texel's own noise, zero to one.

    Returns:
        Red, green and blue, from zero to one.

    Raises:
        Error: If the style is not one of the three.
    """
    if not style.is_valid():
        raise Error("A facade style must be one of the four")
    var shade = (grain - 0.5) * Float32(0.05)
    if style == PLASTER:
        return (
            Float32(0.78) + shade,
            Float32(0.72) + shade,
            Float32(0.6) + shade,
        )
    if style == BRICK:
        var course = Int(floor(v / Float32(0.075)))
        var shift = Float32(0.12) * Float32(course % 2)
        var along = (u + shift) / Float32(0.24)
        var mortar = min(
            v / Float32(0.075) - Float32(course), along - floor(along)
        )
        var line = 1 - smoothstep(0.08, 0.14, mortar)
        var brick = hash2(Int(floor(along)), course, 17) * Float32(0.12)
        return (
            Float32(0.55) + brick + shade + line * 0.2,
            Float32(0.27) + brick * 0.5 + shade + line * 0.4,
            Float32(0.2) + shade + line * 0.42,
        )
    if style == SHOPFRONT:
        var stone = Float32(0.3) + shade
        return (stone, stone * Float32(0.96), stone * Float32(0.92))
    var seam = min(v - floor(v / 3) * 3, u - floor(u / 1.5) * Float32(1.5))
    var groove = 1 - smoothstep(0.02, 0.05, seam)
    var tone = Float32(0.6) + shade - groove * 0.2
    return (tone, tone, tone * Float32(1.02))


def facade_maps(
    style: FacadeStyle, size: Int, seed: Int = 7
) raises -> SurfaceMaps:
    """Return a facade: a wall with a grid of windows.

    The tile is `FACADE_TILE` on a side: four bays of 3 m and four floors
    of 3 m. Each bay of each floor has a window 1.6 m wide and 1.7 m high,
    0.9 m above the floor. A shop front has one floor, at the foot of the
    tile: each bay has a window 2.6 m wide and 2.75 m high, 0.25 m above
    the ground. A fifth of the windows, and seven tenths of the shop
    windows, are lit in the emissive map, each a little warmer or cooler.

    Args:
        style: The wall.
        size: Texels on a side.
        seed: Which windows are lit.

    Returns:
        The maps.

    Raises:
        Error: If the style is not one of the four, or `size` is less
            than one.
    """
    _check_size(size)
    var color = List[UInt8](capacity=size * size * 4)
    var rough = List[UInt8](capacity=size * size * 4)
    var glow = List[UInt8](capacity=size * size * 4)
    var heights = List[Float32](capacity=size * size)
    var meters = FACADE_TILE.to(METER) / Float32(size)
    # The share of the windows lit at night.
    var share = Float32(0.7) if style == SHOPFRONT else Float32(0.22)
    # A shop window is larger, so it glows less per texel.
    var gain = Float32(0.5) if style == SHOPFRONT else Float32(1)
    # The size is checked to be one or more.
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            var u = Float32(x) * meters
            # The rows run down from the tile's top, and v up from its foot.
            var v = FACADE_TILE.to(METER) - (Float32(y) + 0.5) * meters
            var bay = u - floor(u / 3) * 3
            var floor_v = v - floor(v / 3) * 3
            # A window's left, right, bottom and top within its bay.
            var box = (Float32(0.7), Float32(2.3), Float32(0.9), Float32(2.6))
            if style == SHOPFRONT:
                floor_v = v - floor(v / 12) * 12
                box = (Float32(0.2), Float32(2.8), Float32(0.25), Float32(3.0))
            var across = smoothstep(box[0], box[0] + 0.02, bay) - smoothstep(
                box[1] - 0.02, box[1], bay
            )
            var up = smoothstep(box[2], box[2] + 0.02, floor_v) - smoothstep(
                box[3] - 0.02, box[3], floor_v
            )
            var window = across * up
            var frame = (
                smoothstep(box[0] - 0.08, box[0] - 0.04, bay)
                - smoothstep(box[1] + 0.04, box[1] + 0.08, bay)
            ) * (
                smoothstep(box[2] - 0.08, box[2] - 0.04, floor_v)
                - smoothstep(box[3] + 0.04, box[3] + 0.08, floor_v)
            ) - window
            var grain = hash2(x, y, seed)
            var wall = wall_color(style, u, v, grain)
            var pane = hash2(Int(floor(u / 3)), Int(floor(v / 3)), seed + 2)
            var sky = (
                Float32(0.2)
                + (1 - floor_v / 3) * Float32(0.12)
                + pane * Float32(0.12)
            )
            var r = (
                wall[0] * (1 - window - frame)
                + sky * 0.8 * window
                + 0.25 * frame
            )
            var g = (
                wall[1] * (1 - window - frame)
                + sky * 0.95 * window
                + 0.25 * frame
            )
            var b = (
                wall[2] * (1 - window - frame)
                + sky * 1.1 * window
                + 0.26 * frame
            )
            _rgba(color, r, g, b)
            var smooth = Float32(0.88) * (1 - window) + Float32(0.06) * window
            _rgba(rough, smooth, smooth, smooth)
            var lit = hash2(Int(floor(u / 3)), Int(floor(v / 3)), seed + 1)
            var on = (
                gain
                * window
                * (Float32(0.35) + pane * 0.65 if lit < share else Float32(0))
            )
            _rgba(
                glow,
                on,
                on * (Float32(0.72) + pane * 0.2),
                on * (Float32(0.45) + pane * 0.3),
            )
            heights.append(-window * 0.5 - frame * 0.2 + grain * 0.05)
    return SurfaceMaps(
        _texture(size, color^, SRGB),
        _texture(size, rough^, LINEAR),
        normal_map(heights, size, 2),
        _texture(size, glow^, SRGB),
    )


def puddle_roughness(
    dry: Texture,
    puddles: Float32,
    wet_roughness: Float32,
    puddle_roughness: Float32,
    seed: Int = 13,
) raises -> Texture:
    """Return a roughness map with puddles.

    Where a large-scale noise is below the puddle share the texel is
    `puddle_roughness`; elsewhere the dry roughness is moved toward
    `wet_roughness`. The roughness sits in the green channel.

    Args:
        dry: The dry roughness map; its green channel is read.
        puddles: The share of the surface under water, zero to one.
        wet_roughness: The roughness a wet texel's is capped at.
        puddle_roughness: The roughness in a puddle.
        seed: Which puddles.

    Returns:
        A linear, repeating, mipmapped texture of the same size.

    Raises:
        Error: If the dry map is not square.
    """
    if dry.width != dry.height:
        raise Error("A puddle map needs a square roughness map")
    var size = dry.width
    var pixels = List[UInt8](capacity=size * size * 4)
    var step = Float32(1) / Float32(size)
    # A texture has at least one texel.
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            var base = Float32(dry.pixels[(y * size + x) * 4 + 1]) / 255
            var wet = min(base, wet_roughness)
            var field = tile_fbm(
                Float32(x) * step, Float32(y) * step, 2, 4, seed
            )
            var water = 1 - smoothstep(puddles - 0.04, puddles + 0.04, field)
            var r = wet + (puddle_roughness - wet) * water
            _rgba(pixels, r, r, r)
    return _texture(size, pixels^, LINEAR)


def _check_size(size: Int) raises:
    """Refuse a texture of no texels."""
    if size < 1:
        raise Error("A texture needs at least one texel on a side")
