# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Procedural maps for the surfaces of the castle.

A set of maps is three textures that tile: the albedo, the tangent-space
normals and the roughness. The albedo is sRGB. The normals and the roughness
are linear, and the roughness is in the green channel, where a physical
material reads it.

A tile covers a fixed size in meters, and the number of texels is a choice.
The surfaces are laid out from the real sizes of the parts:

- A brick is 210 mm long and 65 mm high, with a 10 mm joint, so a course is
  73.3 mm. A tile of 4 bricks and 12 courses is 880 mm each way, in running
  bond.
- A block of dressed stone is 600 mm long and 300 mm high with a 4 mm joint.
  A tile of 2 blocks and 4 courses is 1200 mm each way.
- A slate is 300 mm wide and 400 mm long, laid with a 120 mm exposure. A tile
  of 2 slates and 4 courses is 600 mm wide and 480 mm high.

The normals come from a height field that the same pattern makes, so a joint
is a groove and a slate has an edge that throws a shadow. Texture rows run
from the top, and v rises upward.
"""

from std.math import cos, floor, pi, sin, sqrt
from core.assets import Assets
from generators.utils import Vec3d
from math.vector2 import Vector2
from render.srgb import LINEAR, SRGB
from render.texture import BILINEAR, CLAMP, IGNORED, REPEAT, Texture
from render.texture_store import TextureId

# The size of one tile of each pattern, in meters.
comptime BRICK_TILE = 0.88
comptime STONE_TILE = 1.2
comptime SLATE_WIDTH = 0.6
comptime SLATE_HEIGHT = 0.48
comptime GRASS_TILE = 6.0
comptime GRAVEL_TILE = 2.4

# The smallest and the largest number of texels along a side of a map.
comptime MIN_SIZE = 8
comptime MAX_SIZE = 4096

# The sizes of a brick, in meters: its length and its height with the joint.
comptime _BRICK_LENGTH = 0.22
comptime _BRICK_COURSE = 0.073333
comptime _BRICK_JOINT = 0.01


@fieldwise_init
struct SurfaceMaps(Movable):
    """The three textures of one surface."""

    # The color of the surface, in sRGB.
    var albedo: Texture
    # The tangent-space normals, in linear values.
    var normal: Texture
    # The roughness in the green channel, in linear values.
    var roughness: Texture

    def store(
        deinit self, mut assets: Assets, repeat: Vector2
    ) -> Tuple[TextureId, TextureId, TextureId]:
        """Add the three textures to the assets.

        Args:
            assets: The stores.
            repeat: How many tiles there are for each unit of texture
                coordinates, along u and along v.

        Returns:
            The ids of the albedo, the normals and the roughness.
        """
        self.albedo.repeat = repeat
        self.normal.repeat = repeat
        self.roughness.repeat = repeat
        var albedo = assets.textures.add(self.albedo^)
        var normal = assets.textures.add(self.normal^)
        var roughness = assets.textures.add(self.roughness^)
        return (albedo, normal, roughness)


struct _Layers(Movable):
    """The values of every texel of a tile, before they become bytes."""

    var size: Int
    var color: List[Vec3d]
    var height: List[Float64]
    var rough: List[Float64]

    def __init__(out self, size: Int):
        self.size = size
        self.color = List[Vec3d](length=size * size, fill=Vec3d(0, 0, 0))
        self.height = List[Float64](length=size * size, fill=0.0)
        self.rough = List[Float64](length=size * size, fill=1.0)

    def put(
        mut self,
        column: Int,
        row: Int,
        color: Vec3d,
        height: Float64,
        rough: Float64,
    ):
        """Set the values of one texel."""
        var at = row * self.size + column
        self.color[at] = color
        self.height[at] = height
        self.rough[at] = rough


def _require_size(size: Int) raises:
    """Refuse a size that is out of range."""
    if size < MIN_SIZE or size > MAX_SIZE:
        raise Error(
            "A map must be "
            + String(MIN_SIZE)
            + " to "
            + String(MAX_SIZE)
            + " texels along a side"
        )


def _hash(x: Int, y: Int, seed: Int) -> Float64:
    """Return a repeatable number from 0 up to 1 for a lattice point."""
    var h = (
        UInt32((x * 73856093) & 0xFFFFFFFF)
        ^ UInt32((y * 19349663) & 0xFFFFFFFF)
        ^ UInt32((seed * 83492791) & 0xFFFFFFFF)
    )
    h = (h ^ (h >> 16)) * UInt32(0x45D9F3B)
    h = (h ^ (h >> 16)) * UInt32(0x45D9F3B)
    h = h ^ (h >> 16)
    return Float64(h) / 4294967296.0


def _smooth(x: Float64) -> Float64:
    """Return the smooth step of a number clamped to 0 through 1."""
    var t = min(max(x, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def _wrap(index: Int, period: Int) -> Int:
    """Return an index folded into 0 up to the period."""
    return ((index % period) + period) % period


def _noise(u: Float64, v: Float64, period: Int, seed: Int) -> Float64:
    """Return value noise from 0 to 1 that repeats once every unit."""
    var x = u * Float64(period)
    var y = v * Float64(period)
    var ix = Int(floor(x))
    var iy = Int(floor(y))
    var sx = _smooth(x - Float64(ix))
    var sy = _smooth(y - Float64(iy))
    var x0 = _wrap(ix, period)
    var x1 = _wrap(ix + 1, period)
    var y0 = _wrap(iy, period)
    var y1 = _wrap(iy + 1, period)
    var low = _hash(x0, y0, seed) * (1.0 - sx) + _hash(x1, y0, seed) * sx
    var high = _hash(x0, y1, seed) * (1.0 - sx) + _hash(x1, y1, seed) * sx
    return low * (1.0 - sy) + high * sy


def _fbm(
    u: Float64, v: Float64, period: Int, octaves: Int, seed: Int
) -> Float64:
    """Return fractal noise from 0 to 1 that repeats once every unit."""
    var total = Float64(0)
    var amplitude = Float64(0.5)
    var weight = Float64(0)
    var cells = period
    for octave in range(octaves):
        total += amplitude * _noise(u, v, cells, seed + 17 * octave)
        weight += amplitude
        amplitude *= 0.5
        cells *= 2
    return total / weight


def _cells(
    u: Float64, v: Float64, period: Int, seed: Int
) -> Tuple[Float64, Float64]:
    """Return the distance to the nearest of a set of jittered points, in
    cells, and a number from 0 to 1 that names that point. It repeats once
    every unit."""
    var x = u * Float64(period)
    var y = v * Float64(period)
    var ix = Int(floor(x))
    var iy = Int(floor(y))
    var best = Float64(1.0e30)
    var name = Float64(0)
    for dy in range(-1, 2):
        for dx in range(-1, 2):
            var cx = ix + dx
            var cy = iy + dy
            var wx = _wrap(cx, period)
            var wy = _wrap(cy, period)
            var px = Float64(cx) + 0.15 + 0.7 * _hash(wx, wy, seed)
            var py = Float64(cy) + 0.15 + 0.7 * _hash(wx, wy, seed + 5)
            var distance = sqrt((px - x) * (px - x) + (py - y) * (py - y))
            if distance < best:
                best = distance
                name = _hash(wx, wy, seed + 9)
    return (best, name)


def _byte(value: Float64) -> UInt8:
    """Return a number from 0 to 1 as a byte."""
    return UInt8(Int(min(max(value, 0.0), 1.0) * 255.0 + 0.5))


def _maps(layers: _Layers, strength: Float64) raises -> SurfaceMaps:
    """Turn the values of a tile into its three textures.

    Args:
        layers: The color, the height and the roughness of each texel.
        strength: How steep the normals are for a height step of 1.
    """
    var size = layers.size
    var albedo = List[UInt8](capacity=size * size * 4)
    var normal = List[UInt8](capacity=size * size * 4)
    var rough = List[UInt8](capacity=size * size * 4)
    for row in range(size):
        for column in range(size):
            var at = row * size + column
            var color = layers.color[at]
            albedo.append(_byte(color.x))
            albedo.append(_byte(color.y))
            albedo.append(_byte(color.z))
            albedo.append(255)
            var left = row * size + _wrap(column - 1, size)
            var right = row * size + _wrap(column + 1, size)
            var above = _wrap(row - 1, size) * size + column
            var below = _wrap(row + 1, size) * size + column
            var across = (layers.height[right] - layers.height[left]) * 0.5
            var upward = (layers.height[above] - layers.height[below]) * 0.5
            var nx = -across * strength
            var ny = -upward * strength
            var length = sqrt(nx * nx + ny * ny + 1.0)
            normal.append(_byte(0.5 + 0.5 * nx / length))
            normal.append(_byte(0.5 + 0.5 * ny / length))
            normal.append(_byte(0.5 + 0.5 / length))
            normal.append(255)
            rough.append(255)
            rough.append(_byte(layers.rough[at]))
            rough.append(0)
            rough.append(255)
    var color_map = Texture(size, size, albedo^, REPEAT, BILINEAR, SRGB, True)
    var normal_map = Texture(
        size, size, normal^, REPEAT, BILINEAR, LINEAR, True, IGNORED
    )
    var rough_map = Texture(
        size, size, rough^, REPEAT, BILINEAR, LINEAR, True, IGNORED
    )
    color_map.anisotropy = 8
    normal_map.anisotropy = 8
    rough_map.anisotropy = 8
    return SurfaceMaps(color_map^, normal_map^, rough_map^)


def brick_maps(size: Int, seed: Int) raises -> SurfaceMaps:
    """Return the maps of a brick wall in running bond.

    The tile is `BRICK_TILE` meters each way: 4 bricks across and 12 courses
    up. Each brick has its own color, and a few are burnt dark. The joints are
    lime mortar, set back 3 mm, and the arrises are rounded.

    Args:
        size: The number of texels along a side.
        seed: Where the random numbers start.

    Returns:
        The albedo, the normals and the roughness.

    Raises:
        Error: If the size is out of range.
    """
    _require_size(size)
    var layers = _Layers(size)
    var dark = Vec3d(0.36, 0.11, 0.08)
    var light = Vec3d(0.62, 0.25, 0.14)
    var burnt = Vec3d(0.30, 0.19, 0.18)
    var mortar = Vec3d(0.74, 0.70, 0.62)
    var joint_x = _BRICK_JOINT / _BRICK_LENGTH
    var joint_y = _BRICK_JOINT / _BRICK_COURSE
    for row in range(size):
        for column in range(size):
            var u = (Float64(column) + 0.5) / Float64(size)
            var v = 1.0 - (Float64(row) + 0.5) / Float64(size)
            var course_at = v * 12.0
            var course = Int(floor(course_at))
            var fy = course_at - Float64(course)
            var bond = u * 4.0
            if course % 2 == 1:
                bond += 0.5
            var brick = Int(floor(bond))
            var fx = bond - Float64(brick)
            var edge_x = (
                min(fx - joint_x / 2, 1.0 - joint_x / 2 - fx) * _BRICK_LENGTH
            )
            var edge_y = (
                min(fy - joint_y / 2, 1.0 - joint_y / 2 - fy) * _BRICK_COURSE
            )
            var edge = min(edge_x, edge_y)
            # The height in millimeters: a groove, a rounded arris, a face.
            var height = -3.0 + 3.0 * _smooth((edge * 1000.0 + 1.5) / 4.0)
            var grain = _fbm(u, v, 64, 3, seed + 3)
            var broad = _fbm(u, v, 3, 3, seed + 11)
            var fine = _noise(u, v, 256, seed + 21)
            var id = _hash(_wrap(brick, 4), course, seed)
            if edge < -0.0005:
                var shade = 0.78 + 0.34 * grain
                layers.put(
                    column,
                    row,
                    mortar * shade * (0.85 + 0.15 * _smooth(-edge * 400.0)),
                    height + 0.5 * (fine - 0.5),
                    0.96,
                )
                continue
            var base = dark * (1.0 - id) + light * id
            if _hash(_wrap(brick, 4), course, seed + 31) > 0.9:
                base = burnt * 0.5 + base * 0.5
            var ao = 0.78 + 0.22 * _smooth(edge * 1000.0 / 3.0)
            var weather = 0.9 + 0.2 * broad
            var shade = (0.84 + 0.32 * grain) * ao * weather
            layers.put(
                column,
                row,
                base * shade,
                height + 0.9 * (grain - 0.5) + 0.5 * (fine - 0.5),
                0.78 + 0.18 * fine,
            )
    return _maps(layers, 0.9)


def stone_maps(size: Int, seed: Int) raises -> SurfaceMaps:
    """Return the maps of dressed limestone laid in courses.

    The tile is `STONE_TILE` meters each way: 2 blocks across and 4 courses
    up, in running bond with a 4 mm joint. The stone is pale, with a faint
    stain and small pits.

    Args:
        size: The number of texels along a side.
        seed: Where the random numbers start.

    Returns:
        The albedo, the normals and the roughness.

    Raises:
        Error: If the size is out of range.
    """
    _require_size(size)
    var layers = _Layers(size)
    var stone = Vec3d(0.66, 0.62, 0.54)
    var warm = Vec3d(0.70, 0.62, 0.48)
    var mortar = Vec3d(0.66, 0.63, 0.56)
    var joint_x = 0.004 / 0.6
    var joint_y = 0.004 / 0.3
    for row in range(size):
        for column in range(size):
            var u = (Float64(column) + 0.5) / Float64(size)
            var v = 1.0 - (Float64(row) + 0.5) / Float64(size)
            var course_at = v * 4.0
            var course = Int(floor(course_at))
            var fy = course_at - Float64(course)
            var bond = u * 2.0
            if course % 2 == 1:
                bond += 0.5
            var block = Int(floor(bond))
            var fx = bond - Float64(block)
            var edge_x = min(fx - joint_x / 2, 1.0 - joint_x / 2 - fx) * 0.6
            var edge_y = min(fy - joint_y / 2, 1.0 - joint_y / 2 - fy) * 0.3
            var edge = min(edge_x, edge_y)
            var grain = _fbm(u, v, 48, 4, seed + 2)
            var stain = _fbm(u, v, 4, 3, seed + 7)
            var pit = _noise(u, v, 220, seed + 13)
            var height = -2.0 + 2.0 * _smooth((edge * 1000.0 + 1.0) / 3.0)
            if edge < -0.0003:
                layers.put(
                    column, row, mortar * (0.8 + 0.3 * grain), height, 0.95
                )
                continue
            var id = _hash(_wrap(block, 2), course, seed)
            var base = stone * (1.0 - id * 0.6) + warm * (id * 0.6)
            var shade = (0.9 + 0.2 * grain) * (0.88 + 0.2 * stain)
            var pitted = pit > 0.93
            if pitted:
                shade *= 0.72
            layers.put(
                column,
                row,
                base * shade,
                height + 0.8 * (grain - 0.5) - (0.7 if pitted else 0.0),
                0.78 + 0.12 * grain,
            )
    return _maps(layers, 0.7)


def slate_maps(size: Int, seed: Int) raises -> SurfaceMaps:
    """Return the maps of a slate roof.

    The tile is `SLATE_WIDTH` by `SLATE_HEIGHT` meters: 2 slates across and 4
    courses up, laid with a half bond. Each slate has its own tone, and the
    free edge of a slate is raised and throws a thin shadow on the course
    below.

    Args:
        size: The number of texels along a side.
        seed: Where the random numbers start.

    Returns:
        The albedo, the normals and the roughness.

    Raises:
        Error: If the size is out of range.
    """
    _require_size(size)
    var layers = _Layers(size)
    var blue = Vec3d(0.27, 0.30, 0.36)
    var green = Vec3d(0.27, 0.32, 0.31)
    var brown = Vec3d(0.33, 0.30, 0.31)
    var gap = Vec3d(0.06, 0.06, 0.07)
    for row in range(size):
        for column in range(size):
            var u = (Float64(column) + 0.5) / Float64(size)
            var v = 1.0 - (Float64(row) + 0.5) / Float64(size)
            var course_at = v * 4.0
            var course = Int(floor(course_at))
            var fy = course_at - Float64(course)
            var across = u * 2.0
            if course % 2 == 1:
                across += 0.5
            var slate = Int(floor(across))
            var fx = across - Float64(slate)
            var id = _hash(_wrap(slate, 2), course, seed)
            var tone = _hash(_wrap(slate, 2), course, seed + 4)
            var base = blue * (1.0 - id) + green * id
            if tone > 0.85:
                base = base * 0.5 + brown * 0.5
            var grain = _fbm(u, v, 40, 3, seed + 8)
            var fine = _noise(u, v, 180, seed + 15)
            if fx < 0.007 or fx > 0.993:
                layers.put(column, row, gap, -3.0, 0.9)
                continue
            # The free edge is at the bottom of the row. The slate falls away
            # toward the course above, which covers its top.
            var height = 3.0 * (1.0 - fy) + 0.5 * (fine - 0.5)
            var shadow = 0.72 + 0.28 * _smooth((1.0 - fy) / 0.35)
            var chip = 1.0 + 0.25 * _smooth((0.04 - fy) / 0.04)
            var color = base * (0.82 + 0.3 * grain) * shadow * chip
            layers.put(column, row, color, height, 0.42 + 0.2 * fine)
    return _maps(layers, 0.8)


def grass_maps(size: Int, seed: Int) raises -> SurfaceMaps:
    """Return the maps of a meadow in autumn.

    The tile is `GRASS_TILE` meters each way. Green and dry patches run
    across it, and a fine grain stands for the blades.

    Args:
        size: The number of texels along a side.
        seed: Where the random numbers start.

    Returns:
        The albedo, the normals and the roughness.

    Raises:
        Error: If the size is out of range.
    """
    _require_size(size)
    var layers = _Layers(size)
    var green = Vec3d(0.30, 0.38, 0.14)
    var deep = Vec3d(0.20, 0.28, 0.10)
    var dry = Vec3d(0.52, 0.47, 0.22)
    for row in range(size):
        for column in range(size):
            var u = (Float64(column) + 0.5) / Float64(size)
            var v = 1.0 - (Float64(row) + 0.5) / Float64(size)
            var patch = _fbm(u, v, 5, 4, seed + 1)
            var clump = _fbm(u, v, 24, 3, seed + 6)
            var blade = _noise(u, v, 300, seed + 12)
            var blade_fine = _noise(u, v, 640, seed + 19)
            var base = deep * (0.7 - 0.4 * clump + 0.3) + green * (
                0.3 + 0.4 * clump
            )
            var dryness = 0.3 * _smooth((patch - 0.5) * 3.0)
            base = base * (1.0 - dryness) + dry * dryness
            var shade = 0.75 + 0.5 * (0.6 * blade + 0.4 * blade_fine)
            layers.put(
                column,
                row,
                base * shade,
                1.2 * blade + 0.8 * blade_fine + 0.6 * clump,
                0.92,
            )
    return _maps(layers, 0.35)


def gravel_maps(size: Int, seed: Int) raises -> SurfaceMaps:
    """Return the maps of a gravel path.

    The tile is `GRAVEL_TILE` meters each way, with stones about 6 cm across
    in a bed of sand.

    Args:
        size: The number of texels along a side.
        seed: Where the random numbers start.

    Returns:
        The albedo, the normals and the roughness.

    Raises:
        Error: If the size is out of range.
    """
    _require_size(size)
    var layers = _Layers(size)
    var sand = Vec3d(0.46, 0.40, 0.30)
    var gray = Vec3d(0.52, 0.50, 0.47)
    var tan = Vec3d(0.62, 0.54, 0.40)
    var white = Vec3d(0.72, 0.70, 0.64)
    for row in range(size):
        for column in range(size):
            var u = (Float64(column) + 0.5) / Float64(size)
            var v = 1.0 - (Float64(row) + 0.5) / Float64(size)
            var found = _cells(u, v, 40, seed)
            var distance = found[0]
            var name = found[1]
            var grain = _noise(u, v, 200, seed + 3)
            var stone = gray
            if name > 0.66:
                stone = white
            elif name > 0.33:
                stone = tan
            var inside = _smooth((0.36 - distance) / 0.08)
            var color = sand * (1.0 - inside) + stone * inside
            var height = 4.0 * inside * (1.0 - distance) + 0.6 * grain
            layers.put(column, row, color * (0.82 + 0.36 * grain), height, 0.88)
    return _maps(layers, 0.6)


def leaf_texture(size: Int, seed: Int) raises -> Texture:
    """Return a card of leaves with a cut-out outline.

    The card is a spray of leaves on a clear ground. The albedo is gray, so
    that a vertex color tints each card. The alpha is 255 inside a leaf and 0
    outside it, for an alpha test.

    Args:
        size: The number of texels along a side.
        seed: Where the random numbers start.

    Returns:
        The texture, clamped at its edges.

    Raises:
        Error: If the size is out of range.
    """
    _require_size(size)
    var count = 44
    var px = List[Float64]()
    var py = List[Float64]()
    var angle = List[Float64]()
    var half_length = List[Float64]()
    var half_width = List[Float64]()
    var shade = List[Float64]()
    for leaf in range(count):
        # Leaves sit inside a disc, and point away from its middle.
        var around = 2.0 * pi * _hash(leaf, 1, seed)
        var reach = 0.36 * sqrt(_hash(leaf, 2, seed))
        px.append(0.5 + reach * cos(around))
        py.append(0.5 + reach * sin(around))
        angle.append(around + (_hash(leaf, 3, seed) - 0.5) * 1.6)
        var length = 0.11 + 0.07 * _hash(leaf, 4, seed)
        half_length.append(length)
        half_width.append(length * (0.42 + 0.12 * _hash(leaf, 5, seed)))
        shade.append(0.55 + 0.45 * _hash(leaf, 6, seed))
    var pixels = List[UInt8](length=size * size * 4, fill=0)
    for row in range(size):
        for column in range(size):
            var x = (Float64(column) + 0.5) / Float64(size)
            var y = 1.0 - (Float64(row) + 0.5) / Float64(size)
            var found = False
            var value = Float64(0)
            for leaf in range(count):
                var dx = x - px[leaf]
                var dy = y - py[leaf]
                var along = (
                    dx * cos(angle[leaf]) + dy * sin(angle[leaf])
                ) / half_length[leaf]
                var across = (
                    -dx * sin(angle[leaf]) + dy * cos(angle[leaf])
                ) / half_width[leaf]
                if along < -1.0 or along > 1.0:
                    continue
                # A leaf is widest a third of the way along, and pointed.
                var width = (1.0 - along * along) * (1.0 - 0.25 * along)
                if abs(across) > width:
                    continue
                found = True
                var vein = 1.0 - 0.3 * _smooth(1.0 - abs(across) * 14.0)
                var side = 0.85 + 0.15 * abs(
                    sin(abs(along) * 9.0 + 3.0 * across)
                )
                value = shade[leaf] * vein * side * (0.8 + 0.1 * (along + 1.0))
            if found:
                var at = (row * size + column) * 4
                var byte = _byte(value)
                pixels[at] = byte
                pixels[at + 1] = byte
                pixels[at + 2] = byte
                pixels[at + 3] = 255
    var texture = Texture(size, size, pixels^, CLAMP, BILINEAR, SRGB, True)
    texture.anisotropy = 4
    return texture^


def _segment_distance(
    px: Float64,
    py: Float64,
    ax: Float64,
    ay: Float64,
    bx: Float64,
    by: Float64,
) -> Tuple[Float64, Float64]:
    """Return the distance from a point to a segment, and how far along the
    segment the nearest point is, from 0 to 1."""
    var dx = bx - ax
    var dy = by - ay
    var along = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    along = min(max(along, 0.0), 1.0)
    var nx = ax + along * dx - px
    var ny = ay + along * dy - py
    return (sqrt(nx * nx + ny * ny), along)


def needle_texture(size: Int, seed: Int) raises -> Texture:
    """Return a card with a spray of conifer needles on a cut-out ground.

    The spray is a stem up the middle of the card, with pairs of needle
    clusters leaning up and out from it, longest at the foot. The albedo is
    gray and the alpha cuts the outline.

    Args:
        size: The number of texels along a side.
        seed: Where the random numbers start.

    Returns:
        The texture, clamped at its edges.

    Raises:
        Error: If the size is out of range.
    """
    _require_size(size)
    var pairs = 30
    var pixels = List[UInt8](length=size * size * 4, fill=0)
    for row in range(size):
        for column in range(size):
            var x = (Float64(column) + 0.5) / Float64(size)
            var y = 1.0 - (Float64(row) + 0.5) / Float64(size)
            var value = Float64(0)
            var found = False
            var stem = _segment_distance(x, y, 0.5, 0.02, 0.5, 0.98)
            if stem[0] < 0.012:
                found = True
                value = 0.45
            for k in range(pairs):
                var t = (Float64(k) + 0.5) / Float64(pairs)
                var base_y = 0.06 + 0.86 * t
                var length = 0.34 * (1.0 - 0.7 * t)
                for side in range(2):
                    var sign = -1.0 if side == 0 else 1.0
                    var wobble = 0.12 * (_hash(k, side, seed) - 0.5)
                    var tip_x = 0.5 + sign * length * cos(0.9 + wobble)
                    var tip_y = base_y + length * sin(0.9 + wobble) * 0.8
                    var hit = _segment_distance(x, y, 0.5, base_y, tip_x, tip_y)
                    if hit[0] < 0.016 * (1.0 - 0.55 * hit[1]):
                        found = True
                        value = 0.55 + 0.45 * hit[1] * _hash(k, side, seed + 3)
            if found:
                var at = (row * size + column) * 4
                var byte = _byte(value)
                pixels[at] = byte
                pixels[at + 1] = byte
                pixels[at + 2] = byte
                pixels[at + 3] = 255
    var texture = Texture(size, size, pixels^, CLAMP, BILINEAR, SRGB, True)
    texture.anisotropy = 4
    return texture^
