# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The surfaces of the village's houses: textures made from rules, and
the materials that wear them.

Each texture is drawn texel by texel from seeded noise, and tiles: its
right edge meets its left edge, and its top meets its bottom. Each covers
a known size of surface, its `*_TILE` in meters, so a brick keeps its
size on every wall. `extensions.village.sheet.Sheet` lays texture
coordinates in meters divided by that size.

| Texture | Covers | What it shows |
|---|---|---|
| `brick_texture` | 0.9 m | Running bond: 4 bricks of 22.5 cm a course, 12 courses of 7.5 cm, in a pale mortar |
| `fieldstone_texture` | 1.2 m | Rounded stones of four tints, about 20 cm across, in a deep mortar |
| `plaster_texture` | 2 m | Lime plaster, cloudy and warm white |
| `boards_texture` | 1.2 m | Six vertical boards of 20 cm, with grain and dark joints |
| `wood_texture` | 1 m | Grain along the first coordinate, with rare knots |
| `ashlar_texture` | 0.8 m | Dressed blocks of 40 by 20 cm, staggered |
| `tile_texture` | 1 m | Five courses of clay tiles, each shading the course below it |
| `slate_texture` | 0.9 m | Six courses of gray slates |
| `plank_texture` | 1.2 m | Floor planks of 15 cm, their ends staggered |
| `cloth_texture` | 0.25 m | Undyed wool in a twill weave, for rugs, quilts and hangings |

`house_looks` adds each texture once to the stores, and a material for
each: a rough standard material with its vertex colors on. The vertex
colors carry each house's tint and the light that its corners keep out.
"""

from core.assets import Assets
from extensions.vegetation.noise import hash01
from materials.material import BASIC, Material, MaterialId, standard_material
from math.vector3 import Vector3
from render.framebuffer import Color
from render.srgb import SRGB
from render.texture import BILINEAR, REPEAT, Texture
from std.math import floor, sin, sqrt

comptime BRICK_TILE = Float32(0.9)
comptime FIELDSTONE_TILE = Float32(1.2)
comptime PLASTER_TILE = Float32(2.0)
comptime BOARDS_TILE = Float32(1.2)
comptime BATTEN = Float32(0.125)
"""Half a batten's width, as a share of a board's."""
comptime WOOD_TILE = Float32(1.0)
comptime ASHLAR_TILE = Float32(0.8)
comptime TILE_TILE = Float32(1.0)
comptime SLATE_TILE = Float32(0.9)
comptime PLANK_TILE = Float32(1.2)
comptime CLOTH_TILE = Float32(0.25)


def _fade(t: Float32) -> Float32:
    """Return the smooth step of a share from 0 to 1."""
    return t * t * (3 - 2 * t)


def tiled_noise(x: Float32, y: Float32, period: Int, seed: Int) -> Float32:
    """Return smooth noise that repeats every `period` units.

    Args:
        x: Where, in units of the noise's cells.
        y: Where, in units of the noise's cells.
        period: How many cells the noise repeats after, on each axis. It
            must be positive.
        seed: Which noise.

    Returns:
        A number from 0 to 1, mixed from the four cells' corners around
        the point.
    """
    var fx = floor(x)
    var fy = floor(y)
    var i = Int(fx)
    var j = Int(fy)
    var tx = _fade(x - fx)
    var ty = _fade(y - fy)
    var i0 = i % period
    var j0 = j % period
    var i1 = (i + 1) % period
    var j1 = (j + 1) % period
    var a = hash01(i0, j0, seed)
    var b = hash01(i1, j0, seed)
    var c = hash01(i0, j1, seed)
    var d = hash01(i1, j1, seed)
    var top = a + (b - a) * tx
    var bottom = c + (d - c) * tx
    return top + (bottom - top) * ty


def _byte(value: Float32) -> UInt8:
    """Return a channel value from 0 to 255, clamped and rounded."""
    return UInt8(Int(min(Float32(255), max(Float32(0), value)) + 0.5))


struct _Canvas(Movable):
    """The bytes of a square texture, filled texel by texel."""

    var size: Int
    var pixels: List[UInt8]

    def __init__(out self, size: Int) raises:
        if size < 1:
            raise Error("A texture needs at least one texel on a side")
        self.size = size
        self.pixels = List[UInt8](length=size * size * 4, fill=255)

    def set(mut self, x: Int, y: Int, r: Float32, g: Float32, b: Float32):
        """Set a texel to sRGB values from 0 to 255."""
        var at = (y * self.size + x) * 4
        self.pixels[at] = _byte(r)
        self.pixels[at + 1] = _byte(g)
        self.pixels[at + 2] = _byte(b)

    def texture(self) raises -> Texture:
        """Return the canvas as a repeating, mipmapped sRGB texture."""
        return Texture(
            self.size,
            self.size,
            self.pixels.copy(),
            REPEAT,
            BILINEAR,
            SRGB,
            True,
        )


def brick_texture(size: Int, seed: Int) raises -> Texture:
    """Return red brick in running bond, `BRICK_TILE` meters on a side.

    Args:
        size: The texels on a side.
        seed: Which bricks are lighter or darker.

    Returns:
        Four bricks a course and twelve courses, each course offset by
        half a brick, in a pale mortar 1 centimeter wide.

    Raises:
        Error: If `size` is below one.
    """
    var canvas = _Canvas(size)
    var across = Float32(4)
    var courses = Float32(12)
    # The mortar's share of a brick's length and of a course's height.
    var joint_u = Float32(0.01 / 0.225)
    var joint_v = Float32(0.01 / 0.075)
    for y in range(size):  # pragma: no branch
        var fy = (Float32(y) + 0.5) / Float32(size) * courses
        var row = Int(fy)
        var local_v = fy - Float32(row)
        var shift = Float32(0.5) if row % 2 == 1 else Float32(0)
        for x in range(size):  # pragma: no branch
            var fx = (Float32(x) + 0.5) / Float32(size) * across + shift
            var column = Int(fx)
            var local_u = fx - Float32(column)
            var brick = column % Int(across)
            var grit = hash01(x, y, seed + 7) * 0.12 + 0.94
            if local_u < joint_u or local_v < joint_v:
                var m = 178 * grit
                canvas.set(x, y, m, m * 0.96, m * 0.9)
                continue
            var tone = 0.82 + hash01(brick, row, seed) * 0.32
            var burnt = hash01(brick, row, seed + 1) < 0.12
            var r = Float32(150) * tone
            var g = Float32(64) * tone
            var b = Float32(44) * tone
            if burnt:
                r *= 0.62
                g *= 0.6
                b *= 0.75
            # The arrises are a little darker than the face.
            var edge = min(local_u - joint_u, local_v - joint_v)
            var arris = 0.9 + 0.1 * min(Float32(1), edge * 12)
            canvas.set(
                x, y, r * grit * arris, g * grit * arris, b * grit * arris
            )
    return canvas.texture()


def fieldstone_texture(size: Int, seed: Int) raises -> Texture:
    """Return fieldstone in lime mortar, `FIELDSTONE_TILE` meters on a
    side.

    Args:
        size: The texels on a side.
        seed: Where the stones lie.

    Returns:
        Rounded stones of four tints, one in each cell of a 6 by 6 grid
        moved at random, in a deep mortar.

    Raises:
        Error: If `size` is below one.
    """
    var canvas = _Canvas(size)
    var cells = 6
    var tints: List[Vector3] = [
        Vector3(140, 135, 125),
        Vector3(158, 146, 120),
        Vector3(118, 116, 110),
        Vector3(168, 158, 142),
    ]
    for y in range(size):  # pragma: no branch
        var py = (Float32(y) + 0.5) / Float32(size) * Float32(cells)
        for x in range(size):  # pragma: no branch
            var px = (Float32(x) + 0.5) / Float32(size) * Float32(cells)
            var first = Float32(1.0e9)
            var second = Float32(1.0e9)
            var owner = 0
            var cx = Int(px)
            var cy = Int(py)
            for dj in range(-1, 2):  # pragma: no branch
                for di in range(-1, 2):  # pragma: no branch
                    var i = cx + di
                    var j = cy + dj
                    var wi = (i + cells) % cells
                    var wj = (j + cells) % cells
                    var sx = Float32(i) + 0.15 + hash01(wi, wj, seed) * 0.7
                    var sy = Float32(j) + 0.15 + hash01(wi, wj, seed + 1) * 0.7
                    var d = sqrt((px - sx) * (px - sx) + (py - sy) * (py - sy))
                    if d < first:
                        second = first
                        first = d
                        owner = wj * cells + wi
                    elif d < second:
                        second = d
            var edge = second - first
            var grit = hash01(x, y, seed + 9) * 0.14 + 0.93
            if edge < 0.1:
                var m = 112 * grit
                canvas.set(x, y, m, m * 0.97, m * 0.92)
                continue
            var tint = tints[Int(hash01(owner, 3, seed) * 3.999)]
            var round = 0.72 + 0.28 * _fade(min(Float32(1), (edge - 0.1) * 3))
            var shade = round * grit
            canvas.set(x, y, tint.x * shade, tint.y * shade, tint.z * shade)
    return canvas.texture()


def plaster_texture(size: Int, seed: Int) raises -> Texture:
    """Return lime plaster, `PLASTER_TILE` meters on a side.

    Args:
        size: The texels on a side.
        seed: Which clouds.

    Returns:
        Warm white plaster, clouded at two scales.

    Raises:
        Error: If `size` is below one.
    """
    var canvas = _Canvas(size)
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            var u = Float32(x) / Float32(size)
            var v = Float32(y) / Float32(size)
            var cloud = tiled_noise(u * 4, v * 4, 4, seed) * 0.08
            cloud += tiled_noise(u * 16, v * 16, 16, seed + 1) * 0.05
            var grit = hash01(x, y, seed + 2) * 0.04
            var shade = 0.89 + cloud + grit
            canvas.set(x, y, 236 * shade, 228 * shade, 210 * shade)
    return canvas.texture()


def _grain(u: Float32, v: Float32, seed: Int) -> Float32:
    """Return a wood grain's shade along `u`, from 0.8 to 1.1."""
    var wobble = tiled_noise(u * 2, v * 8, 8, seed) * 3
    var ring = sin((v * 40 + wobble) * 3.14159)
    return 0.92 + ring * 0.06 + tiled_noise(u * 16, v * 64, 16, seed + 1) * 0.1


def boards_texture(size: Int, seed: Int) raises -> Texture:
    """Return vertical boards, `BOARDS_TILE` meters on a side.

    Args:
        size: The texels on a side.
        seed: Which boards are lighter or darker.

    Returns:
        Six boards across, each its own shade, with grain up the board,
        and a batten over each joint. A batten is lit along its left edge
        and shaded along its right, and casts a thin shadow on the board
        to its right, so it stands out from the boards without a mesh of
        its own. A batten drawn as a mesh is thinner than a pixel from a
        few meters away, and its rows of pixels beat into waves.

    Raises:
        Error: If `size` is below one.
    """
    var canvas = _Canvas(size)
    var boards = 6
    for y in range(size):  # pragma: no branch
        var v = Float32(y) / Float32(size)
        for x in range(size):  # pragma: no branch
            var fu = (Float32(x) + 0.5) / Float32(size) * Float32(boards)
            var board = Int(fu)
            var local = fu - Float32(board)
            # How far across the board from the nearest joint, from -0.5
            # to 0.5, and which joint that is.
            var across = local - Float32(1) if local > 0.5 else local
            var joint = board + 1 if local > 0.5 else board
            var tone = 0.82 + hash01(board, 0, seed) * 0.3
            var shade = tone * _grain(
                v, Float32(board) / Float32(boards) + local / 6, seed
            )
            if abs(across) < BATTEN:
                # The batten: its own grain, a lit edge and a shaded one.
                shade = (0.95 + hash01(joint, 1, seed) * 0.15) * _grain(
                    v, across + Float32(joint) * 0.37, seed + 1
                )
                shade *= 1 + 0.3 * _rise(across, -BATTEN, -BATTEN * 0.7)
                shade *= 1 - 0.45 * _rise(across, BATTEN, BATTEN * 0.7)
            else:
                # Its shadow on the board to its right.
                var gap = across if across > 0 else Float32(1)
                shade *= 1 - 0.4 * _rise(gap, BATTEN, BATTEN * 1.6)
            canvas.set(x, y, 128 * shade, 92 * shade, 60 * shade)
    return canvas.texture()


def _rise(x: Float32, start: Float32, end: Float32) -> Float32:
    """Return one at `start`, zero at `end`, and a straight line between,
    held at zero and one beyond them."""
    return min(Float32(1), max(Float32(0), (end - x) / (end - start)))


def wood_texture(size: Int, seed: Int) raises -> Texture:
    """Return wood with its grain along the first coordinate,
    `WOOD_TILE` meters on a side.

    Args:
        size: The texels on a side.
        seed: Where the grain wanders and the knots lie.

    Returns:
        Light brown wood, ready to be tinted by vertex colors.

    Raises:
        Error: If `size` is below one.
    """
    var canvas = _Canvas(size)
    for y in range(size):  # pragma: no branch
        var v = Float32(y) / Float32(size)
        for x in range(size):  # pragma: no branch
            var u = Float32(x) / Float32(size)
            var shade = _grain(u, v, seed)
            # A knot: a dark ring around a few points.
            var kx = u * 3 - floor(u * 3)
            var ky = v * 3 - floor(v * 3)
            var cell = Int(u * 3) + Int(v * 3) * 3
            if hash01(cell, 5, seed) < 0.3:
                var dx = (kx - 0.5) * 2
                var dy = (ky - 0.5) * 6
                var d = sqrt(dx * dx + dy * dy)
                if d < 0.35:
                    shade *= 0.7 + d * 0.8
            canvas.set(x, y, 170 * shade, 128 * shade, 86 * shade)
    return canvas.texture()


def ashlar_texture(size: Int, seed: Int) raises -> Texture:
    """Return dressed stone blocks, `ASHLAR_TILE` meters on a side.

    Args:
        size: The texels on a side.
        seed: Which blocks are lighter or darker.

    Returns:
        Two blocks of 40 cm a course and four courses of 20 cm, each
        course offset by half a block, with thin pale joints.

    Raises:
        Error: If `size` is below one.
    """
    var canvas = _Canvas(size)
    for y in range(size):  # pragma: no branch
        var fy = (Float32(y) + 0.5) / Float32(size) * 4
        var row = Int(fy)
        var lv = fy - Float32(row)
        var shift = Float32(0.5) if row % 2 == 1 else Float32(0)
        for x in range(size):  # pragma: no branch
            var fx = (Float32(x) + 0.5) / Float32(size) * 2 + shift
            var column = Int(fx)
            var lu = fx - Float32(column)
            var grit = hash01(x, y, seed + 3) * 0.1 + 0.95
            if lu < 0.02 or lv < 0.04:
                canvas.set(x, y, 206 * grit, 200 * grit, 186 * grit)
                continue
            var tone = 0.86 + hash01(column % 2, row, seed) * 0.2
            var cloud = (
                0.94
                + tiled_noise(
                    Float32(x) / Float32(size) * 8,
                    Float32(y) / Float32(size) * 8,
                    8,
                    seed,
                )
                * 0.12
            )
            var shade = tone * grit * cloud
            canvas.set(x, y, 188 * shade, 180 * shade, 162 * shade)
    return canvas.texture()


def _courses(
    size: Int,
    seed: Int,
    rows: Int,
    across: Int,
    base: Vector3,
    spread: Float32,
) raises -> Texture:
    """Return courses of roofing, each piece shading the course below.

    The second coordinate runs up the roof: each course's lower part, at
    its lowest second coordinate, is the lip of the piece over the next
    course down."""
    var canvas = _Canvas(size)
    for y in range(size):  # pragma: no branch
        var fy = (Float32(y) + 0.5) / Float32(size) * Float32(rows)
        var row = Int(fy)
        var lv = fy - Float32(row)
        var shift = Float32(0.5) if row % 2 == 1 else Float32(0)
        for x in range(size):  # pragma: no branch
            var fx = (Float32(x) + 0.5) / Float32(size) * Float32(
                across
            ) + shift
            var column = Int(fx)
            var lu = fx - Float32(column)
            var piece = column % across
            var tone = 1 - spread / 2 + hash01(piece, row, seed) * spread
            var grit = hash01(x, y, seed + 4) * 0.1 + 0.95
            # The lip of this course, and the shadow it casts below.
            var shade = Float32(1)
            if lv < 0.12:
                shade = 0.55 + lv * 3
            elif lv > 0.9:
                shade = 0.85
            if lu < 0.03 or lu > 0.97:
                shade *= 0.6
            var s = tone * grit * shade
            canvas.set(x, y, base.x * s, base.y * s, base.z * s)
    return canvas.texture()


def tile_texture(size: Int, seed: Int) raises -> Texture:
    """Return clay roof tiles, `TILE_TILE` meters on a side.

    Args:
        size: The texels on a side.
        seed: Which tiles are lighter or darker.

    Returns:
        Five courses of five tiles, staggered, each course shading the
        one below it.

    Raises:
        Error: If `size` is below one.
    """
    return _courses(size, seed, 5, 5, Vector3(172, 78, 50), 0.35)


def slate_texture(size: Int, seed: Int) raises -> Texture:
    """Return roof slates, `SLATE_TILE` meters on a side.

    Args:
        size: The texels on a side.
        seed: Which slates are lighter or darker.

    Returns:
        Six courses of four gray slates, staggered.

    Raises:
        Error: If `size` is below one.
    """
    return _courses(size, seed, 6, 4, Vector3(92, 96, 104), 0.3)


def plank_texture(size: Int, seed: Int) raises -> Texture:
    """Return floor planks, `PLANK_TILE` meters on a side.

    Args:
        size: The texels on a side.
        seed: Where the planks end and which are darker.

    Returns:
        Eight planks of 15 cm along the first coordinate, each in two
        lengths whose joint lies at its own place, with grain along them.

    Raises:
        Error: If `size` is below one.
    """
    var canvas = _Canvas(size)
    for y in range(size):  # pragma: no branch
        var fy = (Float32(y) + 0.5) / Float32(size) * 8
        var row = Int(fy)
        var lv = fy - Float32(row)
        var joint = hash01(row, 0, seed)
        for x in range(size):  # pragma: no branch
            var u = (Float32(x) + 0.5) / Float32(size)
            if lv < 0.06:
                canvas.set(x, y, 40, 30, 22)
                continue
            var length = 0 if u < joint else 1
            var gap = abs(u - joint)
            if gap < 0.006:
                canvas.set(x, y, 46, 34, 24)
                continue
            var tone = 0.8 + hash01(row, length + 1, seed) * 0.3
            var shade = tone * _grain(u, Float32(row) / 8 + lv / 8, seed)
            canvas.set(x, y, 150 * shade, 106 * shade, 66 * shade)
    return canvas.texture()


def cloth_texture(size: Int, seed: Int) raises -> Texture:
    """Return undyed wool in a twill weave, `CLOTH_TILE` meters on a
    side.

    Args:
        size: The texels on a side.
        seed: Which threads are thicker or paler.

    Returns:
        Pale wool woven in a two-over-two twill of 40 threads each way,
        so the weave runs in diagonal ribs. The vertex colors dye it.

    Raises:
        Error: If `size` is below one.
    """
    var canvas = _Canvas(size)
    for y in range(size):  # pragma: no branch
        var fy = (Float32(y) + 0.5) / Float32(size) * 40
        var row = Int(fy)
        var lv = fy - Float32(row)
        for x in range(size):  # pragma: no branch
            var fx = (Float32(x) + 0.5) / Float32(size) * 40
            var column = Int(fx)
            var lu = fx - Float32(column)
            # In a two-over-two twill the warp lies on top where the
            # thread's place along the diagonal is in the first half.
            var warp = (column + row) % 4 < 2
            var across = lu if warp else lv
            # Each thread is rounded: lighter on its crown.
            var crown = 1 - 4 * (across - 0.5) * (across - 0.5)
            var thread = hash01(column if warp else row, 0 if warp else 1, seed)
            var shade = 0.72 + 0.2 * crown + 0.08 * thread
            shade += (
                tiled_noise(
                    Float32(x) / Float32(size) * 8,
                    Float32(y) / Float32(size) * 8,
                    8,
                    seed + 3,
                )
                * 0.06
            )
            canvas.set(x, y, 232 * shade, 226 * shade, 214 * shade)
    return canvas.texture()


@fieldwise_init
struct HouseLooks(ImplicitlyCopyable):
    """The materials of the village's houses, each made once."""

    # The outside walls' materials, by facade: brick, fieldstone, lime
    # plaster and boards.
    var brick: MaterialId
    var fieldstone: MaterialId
    var plaster: MaterialId
    var boards: MaterialId
    # The wood of the frames, the doors, the timbers and the furniture.
    var wood: MaterialId
    # The dressed stone of the plinths, the steps, the quoins and sills.
    var ashlar: MaterialId
    # The roofs' coverings.
    var tiles: MaterialId
    var slates: MaterialId
    # The floors and the window panes, seen from outside and, lit by
    # the day beyond them, from inside.
    var planks: MaterialId
    var glass: MaterialId
    var daylight: MaterialId
    # The wool of the rugs, the quilts, the cushions and the hangings.
    var cloth: MaterialId


def _look(
    mut assets: Assets, var texture: Texture, roughness: Float32
) raises -> MaterialId:
    """Return a rough material that wears a texture and vertex colors."""
    var id = assets.textures.add(texture^)
    var material = standard_material(
        Color(255, 255, 255), map=id, roughness=roughness
    )
    material.vertex_colors = True
    return assets.materials.add(material)


def house_looks(mut assets: Assets, size: Int, seed: Int) raises -> HouseLooks:
    """Make the textures and the materials of the village's houses.

    Args:
        assets: The stores. Ten textures and twelve materials are added.
        size: The texels on a side of each texture.
        seed: Which bricks, stones, boards and tiles.

    Returns:
        The materials.

    Raises:
        Error: If `size` is below one, or a material cannot be made.
    """
    var glass = standard_material(Color(255, 255, 255), roughness=0.15)
    glass.vertex_colors = True
    return HouseLooks(
        _look(assets, brick_texture(size, seed), 0.9),
        _look(assets, fieldstone_texture(size, seed), 0.95),
        _look(assets, plaster_texture(size, seed), 0.95),
        _look(assets, boards_texture(size, seed), 0.85),
        _look(assets, wood_texture(size, seed), 0.75),
        _look(assets, ashlar_texture(size, seed), 0.9),
        _look(assets, tile_texture(size, seed), 0.8),
        _look(assets, slate_texture(size, seed), 0.6),
        _look(assets, plank_texture(size, seed), 0.7),
        assets.materials.add(glass),
        assets.materials.add(
            Material(Color(255, 255, 255), kind=BASIC, vertex_colors=True)
        ),
        _look(assets, cloth_texture(size, seed), 0.95),
    )
