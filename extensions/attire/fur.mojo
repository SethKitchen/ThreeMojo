# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fuzzy fur: shells of strands over a fur garment.

A garment's shell is a smooth surface, so fur drawn on it alone looks
like felt. Fur stands up from the skin of the beast in strands, and its
outline is soft. `fur_shells` stacks copies of a fur garment above it,
each a little farther out along the normals. Each copy draws only the
strands that reach it: its material's `alpha_map` is `fur_texture`, a
tile of strands, and its `alpha_test` is its height in the pile. A
strand is a cone, so the higher copies draw it thinner, and it ends in a
point.

| Value | Size |
|---|---|
| Pile, `FUR_PILE` | 1.6 cm |
| Shells, `FUR_SHELLS` | 3 at full detail, 2 at the least |
| Strands, `FUR_STRANDS` | 10 across a 3 cm tile, 3 mm apart |
| Comb, `FUR_COMB` | the tips fall 40% of the pile down |
| Root, `FUR_ROOT` | the root is drawn at 55% of the dye's shade |

The strands lean down, as combed fur does. The roots are darker than the
tips, because the strands around a root shade it. The texture is not
mipmapped: averaged strands would turn to a haze and fall under the test,
and the fur would go bald at a distance.

This is not a three.js port. See Extensions.

    for k in range(len(shells)):
        look.alpha_test = fur_test(k, len(shells))
"""

from std.math import floor, sqrt

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, BufferGeometry
from extensions.attire.mesh_ops import cut
from extensions.attire.springs import nearest_on_segment
from extensions.humanoid.rig.joints import HumanoidRig
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from math.utils import clamp
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.srgb import LINEAR
from render.texture import BILINEAR, IGNORED, REPEAT, Texture

comptime FUR_PILE = Float32(0.016)
"""How high the strands stand, in meters."""
comptime FUR_SHELLS = 3
"""How many shells stand over a fur garment at full detail."""
comptime LEAST_FUR_SHELLS = 2
"""The fewest shells over a fur garment."""
comptime FUR_STRANDS = 10
"""How many strands lie across a tile, and down it."""
comptime FUR_TILE = Float32(0.03)
"""The side of a tile of strands, in meters."""
comptime FUR_TEXELS = 80
"""The side of the strands' texture, in texels."""
comptime FUR_COMB = Float32(0.4)
"""How far the tips fall down, as a share of the pile."""
comptime FUR_ROOT = Float32(0.55)
"""The shade of a strand at its root, as a share of its tip's."""


def fur_shell_count(detail: Float32) -> Int:
    """Return how many shells stand over a fur garment.

    Args:
        detail: The share of its full detail the garment takes, as
            `garment_detail` gives it.

    Returns:
        `FUR_SHELLS` at full detail, fewer for less, and
        `LEAST_FUR_SHELLS` at the least.
    """
    return max(LEAST_FUR_SHELLS, Int(Float32(FUR_SHELLS) * detail + 0.5))


def fur_test(shell: Int, shells: Int) -> Float32:
    """Return the alpha a strand must reach to be drawn on one shell.

    Args:
        shell: Which shell, from zero, the lowest.
        shells: How many there are.

    Returns:
        The shell's height in the pile, above zero and below one.
    """
    return Float32(shell + 1) / Float32(shells + 1)


def _scramble(a: Int, b: Int) -> Float32:
    """Return a fixed number from zero to one for two integers."""
    var h = UInt64(a * 73856093 + b * 19349663 + 83492791)
    h = (h ^ (h >> 15)) * 0x2C1B3C6D
    h = h ^ (h >> 12)
    return Float32(Int(h & 0xFFFF)) / 65535


def strand_heights() -> List[Float32]:
    """Return a tile of strands: how high each texel's strand reaches.

    Each of `FUR_STRANDS` by `FUR_STRANDS` cells holds one strand, set
    off its cell's middle by chance, and long by chance, from 60% of the
    pile to all of it. A strand is a cone: it reaches its whole length at
    its middle and none at its rim. The tile wraps both ways.

    Returns:
        `FUR_TEXELS` by `FUR_TEXELS` heights, row by row, zero through
        one.
    """
    var heights = List[Float32](length=FUR_TEXELS * FUR_TEXELS, fill=0)
    var cell = Float32(FUR_TEXELS) / Float32(FUR_STRANDS)
    var size = Float32(FUR_TEXELS)
    var rim = cell * 0.6
    for j in range(FUR_STRANDS):  # pragma: no branch
        for i in range(FUR_STRANDS):  # pragma: no branch
            var cx = (Float32(i) + 0.2 + 0.6 * _scramble(i, j)) * cell
            var cy = (Float32(j) + 0.2 + 0.6 * _scramble(j, i + 31)) * cell
            var length = 0.6 + 0.4 * _scramble(i + 7, j + 13)
            for y in range(FUR_TEXELS):  # pragma: no branch
                for x in range(FUR_TEXELS):  # pragma: no branch
                    var dx = Float32(x) + 0.5 - cx
                    var dy = Float32(y) + 0.5 - cy
                    dx -= size * floor(dx / size + 0.5)
                    dy -= size * floor(dy / size + 0.5)
                    var d = sqrt(dx * dx + dy * dy)
                    if d >= rim:
                        continue
                    var h = length * (1 - d / rim)
                    var at = y * FUR_TEXELS + x
                    heights[at] = max(heights[at], h)
    return heights^


def fur_texture() raises -> Texture:
    """Return the strands' tile as an alpha map, `FUR_TILE` a tile.

    Returns:
        A texture whose channels hold each texel's height, linear, with
        no mip chain.

    Raises:
        Error: If the texture is refused, which it is not.
    """
    var heights = strand_heights()
    var pixels = List[UInt8](capacity=4 * len(heights))
    for h in heights:  # pragma: no branch
        var byte = UInt8(Int(clamp(h, 0, 1) * 255 + 0.5))
        pixels.append(byte)
        pixels.append(byte)
        pixels.append(byte)
        pixels.append(255)
    var texture = Texture(
        FUR_TEXELS,
        FUR_TEXELS,
        pixels^,
        REPEAT,
        BILINEAR,
        color_space=LINEAR,
        mipmapped=False,
        alpha=IGNORED,
    )
    texture.repeat = Vector2(1 / FUR_TILE, 1 / FUR_TILE)
    return texture^


def outer_face(
    piece: BufferGeometry, rig: HumanoidRig
) raises -> BufferGeometry:
    """Return the part of a garment that faces out from its bones.

    A vertex faces out when its normal points away from the bone that
    weighs most on it. The lining of a skirt faces in, and so does the
    inside of a cuff, and no strands stand on them.

    Args:
        piece: A garment with normals and skin weights.
        rig: The rig it was made on.

    Returns:
        The part that faces out.

    Raises:
        Error: If the garment has no positions, normals or skin weights.
    """
    ref placed = piece.attribute_view(String(POSITION))
    ref normals = piece.attribute_view(String(NORMAL))
    ref bones = piece.attribute_view(String(SKIN_INDEX))
    ref weights = piece.attribute_view(String(SKIN_WEIGHT))
    var facing = List[Float32](capacity=placed.count())
    for v in range(placed.count()):  # pragma: no branch
        var best = 0
        for c in range(1, 4):  # pragma: no branch
            if weights.component(v, c) > weights.component(v, best):
                best = c
        var bone = Int(bones.component(v, best))
        var p = placed.vector3(v)
        var axis = nearest_on_segment(p, rig.joints[bone], rig.ends[bone])
        facing.append(normals.vector3(v).dot(p - axis))
    return cut(piece, facing, 0)


def fur_shells(
    piece: BufferGeometry, shells: Int, pile: Float32 = FUR_PILE
) raises -> List[BufferGeometry]:
    """Return the shells that stand over a fur garment.

    Pass the garment's `outer_face`, so no strands stand on its lining.
    Shell `k` of `n` stands `pile` times `(k + 1) / n` out along each
    vertex's normal, and its tips fall `FUR_COMB` of that down, more the
    higher it stands. Its vertex colors are darker the lower it stands,
    from `FUR_ROOT` of the garment's at the root to all of it at the tip.

    Args:
        piece: The garment, painted, with normals.
        shells: How many shells, one or more.
        pile: How high the strands stand, in meters.

    Returns:
        The shells, from the lowest out. Each has the garment's
        attributes.

    Raises:
        Error: If there are no shells, or the garment has no positions,
            normals or colors.
    """
    if shells < 1:
        raise Error("Fur needs one shell or more")
    ref placed = piece.attribute_view(String(POSITION))
    ref normals = piece.attribute_view(String(NORMAL))
    ref colors = piece.attribute_view(String(COLOR))
    var made = List[BufferGeometry]()
    for k in range(shells):  # pragma: no branch
        var height = Float32(k + 1) / Float32(shells)
        var shade = FUR_ROOT + (1 - FUR_ROOT) * height
        var points = List[Float32](capacity=3 * placed.count())
        var tints = List[Float32](capacity=3 * placed.count())
        for v in range(placed.count()):  # pragma: no branch
            var p = (
                placed.vector3(v)
                + normals.vector3(v) * (pile * height)
                + Vector3(0, -1, 0) * (FUR_COMB * pile * height * height)
            )
            points.append(p.x)
            points.append(p.y)
            points.append(p.z)
            for c in range(3):  # pragma: no branch
                tints.append(colors.component(v, c) * shade)
        var shell = piece.clone()
        shell.set_attribute(String(POSITION), BufferAttribute(points^, 3))
        shell.set_attribute(String(COLOR), BufferAttribute(tints^, 3))
        made.append(shell^)
    return made^
