# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How a garment takes its colors, and the marks it takes in use.

A garment has four dye channels: primary, secondary, trim and accent. A
pattern says where each lies:

| Pattern | Primary | Secondary |
|---|---|---|
| `SOLID` | everywhere | nowhere |
| `PARTY` | the wearer's right side | the left side |
| `STRIPES` | even bands round the body | odd bands |
| `QUARTERLY` | upper right and lower left | upper left and lower right |

Every pattern puts the trim dye along each hem. A vertex whose `accent`
attribute is one or more half takes the accent dye: a hat's stones, horns
and feather.

`dye_pattern` cuts the garment along each boundary of its pattern, so a
boundary is a crisp line and not a blend across a triangle. Each vertex
keeps the weights of its channels in a `dye` attribute.

Wear is four more channels per vertex, in a `wear` attribute: dirt,
blood, wet and damage, each zero through one. `soil` lays dirt from the
lowest point of a garment up. `stain` lays any channel round a point.

`paint` mixes the dyes and then the wear into the `color` attribute,
three linear floats a vertex, which the fabric's look multiplies.

This is not a three.js port. See Extensions.

    var piece = dye_pattern(piece, rig, PARTY)
    stain(piece, BLOOD, Vector3(0.1, 1.2, 0.15), Length(0.08, METER), 0.9)
    paint(piece, garment.dyes)
"""

from std.math import pi, sin

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from extensions.attire.kinds import (
    ACCENT_DYE,
    DIRT,
    DYE_CHANNEL_COUNT,
    PARTY,
    PRIMARY_DYE,
    QUARTERLY,
    SECONDARY_DYE,
    STRIPES,
    TRIM_DYE,
    WEAR_KIND_COUNT,
    DyeChannel,
    DyePattern,
    WearKind,
    require_dye_pattern,
    require_wear_kind,
)
from extensions.attire.mesh_ops import ACCENT, cut, merge
from extensions.attire.shell import COVER
from extensions.humanoid.rig.joints import (
    HIPS,
    RIGHT_UPPER_ARM,
    SPINE,
    HumanoidRig,
)
from math.utils import clamp
from math.vector3 import Vector3
from render.framebuffer import Color
from render.srgb import srgb_to_linear
from units.si import Length

comptime DYE = "dye"
"""The name of the attribute that carries each vertex's dye weights."""
comptime WEAR = "wear"
"""The name of the attribute that carries each vertex's wear."""
comptime TRIM_LEVEL = Float32(0.6)
"""Below this cover value a vertex lies on a hem's trim."""
comptime STRIPE = Float32(0.09)
"""The height of one stripe, in meters on the template."""
comptime PATTERN_STATURE = Float32(1.8288)
"""The template stature patterns are sized for, in meters."""


def _linear(color: Color) -> Vector3:
    """Return an sRGB color as three linear floats."""
    return Vector3(
        srgb_to_linear(Float32(color.r) / 255),
        srgb_to_linear(Float32(color.g) / 255),
        srgb_to_linear(Float32(color.b) / 255),
    )


def _with_channel(
    var piece: BufferGeometry, channel: DyeChannel
) raises -> BufferGeometry:
    """Return `piece` with every vertex wholly in one dye channel."""
    var count = piece.vertex_count()
    var weights = List[Float32](capacity=4 * count)
    for _ in range(count):
        for c in range(DYE_CHANNEL_COUNT):  # pragma: no branch
            weights.append(Float32(1) if c == channel.value else Float32(0))
    piece.set_attribute(String(DYE), BufferAttribute(weights^, 4))
    return piece^


def _negated(values: List[Float32]) -> List[Float32]:
    """Return each value negated."""
    var out = List[Float32](capacity=len(values))
    for v in values:
        out.append(-v)
    return out^


def _split(
    piece: BufferGeometry,
    values: List[Float32],
    above: DyeChannel,
    below: DyeChannel,
) raises -> BufferGeometry:
    """Cut `piece` along the zero iso-line of `values`, and give each side
    its own channel."""
    var high = _with_channel(cut(piece, values, 0), above)
    var low = _with_channel(cut(piece, _negated(values), 0), below)
    return merge(high, low)


def pattern_values(
    piece: BufferGeometry, rig: HumanoidRig, pattern: DyePattern
) raises -> List[Float32]:
    """Return, per vertex, a value whose sign says which dye it takes.

    Args:
        piece: A garment, in the pelvis frame.
        rig: The rig it was made on.
        pattern: A named pattern.

    Returns:
        One value per vertex: at or above zero for the primary dye, below
        it for the secondary. Every value is one for `SOLID`.

    Raises:
        Error: If `pattern` is not named or the mesh has no positions.
    """
    require_dye_pattern(pattern)
    ref placed = piece.attribute_view(String(POSITION))
    var middle = rig.joints[HIPS.value].x
    # The wearer's right, dexter in heraldry, takes the primary dye.
    var right = Float32(1)
    if rig.joints[RIGHT_UPPER_ARM.value].x < middle:
        right = -1
    var waist = rig.joints[SPINE.value].y
    var stripe = STRIPE * rig.stature / PATTERN_STATURE
    var values = List[Float32](capacity=placed.count())
    for v in range(placed.count()):
        var p = placed.vector3(v)
        var value = Float32(1)
        if pattern == PARTY:
            value = right * (p.x - middle)
        elif pattern == STRIPES:
            value = sin(Float32(pi) * (p.y - waist) / stripe)
        elif pattern == QUARTERLY:
            value = right * (p.x - middle) * (p.y - waist)
        values.append(value)
    return values^


def dye_pattern(
    piece: BufferGeometry, rig: HumanoidRig, pattern: DyePattern
) raises -> BufferGeometry:
    """Return a garment cut along its pattern, each vertex in one channel.

    The trim takes the strip along each hem where the `cover` attribute
    is below `TRIM_LEVEL`. The rest takes the primary and secondary dyes
    as the pattern lays them.

    Args:
        piece: A garment with a `cover` attribute, in the pelvis frame.
        rig: The rig it was made on.
        pattern: A named pattern.

    Returns:
        The garment with a `dye` attribute: four weights a vertex.

    Raises:
        Error: If `pattern` is not named or the mesh has no cover values.
    """
    require_dye_pattern(pattern)
    ref covered = piece.attribute_view(String(COVER))
    var trim = List[Float32](capacity=covered.count())
    for v in range(covered.count()):
        trim.append(covered.component(v, 0) - TRIM_LEVEL)
    var body = cut(piece, trim, 0)
    var hem = _with_channel(cut(piece, _negated(trim), 0), TRIM_DYE)
    var dyed = merge(
        _split(
            body,
            pattern_values(body, rig, pattern),
            PRIMARY_DYE,
            SECONDARY_DYE,
        ),
        hem,
    )
    # A hat's stones, horns and feather take the accent dye.
    if dyed.has_attribute(String(ACCENT)):
        ref marks = dyed.attribute_view(String(ACCENT))
        var weights = dyed.clone_attribute(String(DYE))
        for v in range(marks.count()):
            if marks.component(v, 0) >= 0.5:
                for c in range(DYE_CHANNEL_COUNT):  # pragma: no branch
                    weights.set_component(
                        v, c, Float32(1) if c == ACCENT_DYE.value else 0
                    )
        dyed.set_attribute(String(DYE), weights^)
    return dyed^


def _wear_of(mut piece: BufferGeometry) raises:
    """Give `piece` a `wear` attribute of zeros if it has none."""
    if piece.has_attribute(String(WEAR)):
        return
    var count = piece.vertex_count()
    piece.set_attribute(
        String(WEAR),
        BufferAttribute(List[Float32](length=4 * count, fill=0), 4),
    )


def stain(
    mut piece: BufferGeometry,
    kind: WearKind,
    center: Vector3,
    radius: Length,
    amount: Float32,
) raises:
    """Lay one wear channel round a point.

    The amount falls off smoothly from the center to the radius. Wear
    adds up, and each channel stays at most one.

    Args:
        piece: A garment, in the pelvis frame.
        kind: A named wear channel.
        center: Where the mark is centered.
        radius: How far it reaches.
        amount: How strong it is at the center, zero through one.

    Raises:
        Error: If `kind` is not named, the radius is not positive, or the
            amount is not zero through one.
    """
    require_wear_kind(kind)
    if not (radius.value > 0):
        raise Error("A stain needs a positive radius")
    if not (amount >= 0 and amount <= 1):
        raise Error("A stain's amount must be zero through one")
    _wear_of(piece)
    ref placed = piece.attribute_view(String(POSITION))
    var wear = piece.clone_attribute(String(WEAR))
    for v in range(placed.count()):
        var d = (placed.vector3(v) - center).length() / radius.value
        if d >= 1:
            continue
        var fall = 1 - d * d
        var now = wear.component(v, kind.value)
        wear.set_component(
            v, kind.value, min(Float32(1), now + amount * fall * fall)
        )
    piece.set_attribute(String(WEAR), wear^)


def soil(mut piece: BufferGeometry, reach: Length, amount: Float32) raises:
    """Lay dirt from the lowest point of a garment up.

    Args:
        piece: A garment, in the pelvis frame.
        reach: How far up from its lowest point the dirt fades out.
        amount: How dirty its lowest point is, zero through one.

    Raises:
        Error: If the reach is not positive or the amount is not zero
            through one.
    """
    if not (reach.value > 0):
        raise Error("Dirt needs a positive reach")
    if not (amount >= 0 and amount <= 1):
        raise Error("Dirt's amount must be zero through one")
    _wear_of(piece)
    ref placed = piece.attribute_view(String(POSITION))
    var lowest = Float32(1e30)
    for v in range(placed.count()):
        lowest = min(lowest, placed.vector3(v).y)
    var wear = piece.clone_attribute(String(WEAR))
    for v in range(placed.count()):
        var up = (placed.vector3(v).y - lowest) / reach.value
        var now = wear.component(v, DIRT.value)
        var add = amount * clamp(1 - up, 0, 1)
        wear.set_component(v, DIRT.value, min(Float32(1), now + add))
    piece.set_attribute(String(WEAR), wear^)


# The colors wear mixes toward, as linear floats.
comptime _DIRT_COLOR = Vector3(0.11, 0.075, 0.045)
comptime _BLOOD_COLOR = Vector3(0.16, 0.008, 0.008)
comptime _SCORCH_COLOR = Vector3(0.03, 0.025, 0.02)


def _toward(a: Vector3, b: Vector3, t: Float32) -> Vector3:
    """Return the point `t` of the way from `a` to `b`."""
    return a + (b - a) * t


def worn_color(base: Vector3, wear: List[Float32]) -> Vector3:
    """Return a color with its wear laid over it.

    Dirt browns it. Blood reddens it. Wet darkens it. Damage scorches it.

    Args:
        base: The dyed color, linear.
        wear: Dirt, blood, wet and damage, each zero through one.

    Returns:
        The worn color, linear.
    """
    var color = _toward(base, _DIRT_COLOR, 0.7 * wear[0])
    color = _toward(color, _BLOOD_COLOR, 0.85 * wear[1])
    color = color * (1 - 0.4 * wear[2])
    return _toward(color, _SCORCH_COLOR, 0.6 * wear[3])


def paint(mut piece: BufferGeometry, dyes: List[Color]) raises:
    """Write a garment's `color` attribute from its dyes and its wear.

    Args:
        piece: A garment with a `dye` attribute, and a `wear` attribute
            if it is worn.
        dyes: Four dyes, in sRGB.

    Raises:
        Error: If there are not four dyes or the mesh has no dye weights.
    """
    if len(dyes) != DYE_CHANNEL_COUNT:
        raise Error("Painting needs four dyes")
    var linear = List[Vector3]()
    for dye in dyes:  # pragma: no branch
        linear.append(_linear(dye))
    ref weights = piece.attribute_view(String(DYE))
    var worn = piece.has_attribute(String(WEAR))
    var colors = List[Float32](capacity=3 * weights.count())
    for v in range(weights.count()):
        var color = Vector3(0, 0, 0)
        for c in range(DYE_CHANNEL_COUNT):  # pragma: no branch
            color = color + linear[c] * weights.component(v, c)
        if worn:
            ref wear = piece.attribute_view(String(WEAR))
            var marks = List[Float32]()
            for c in range(WEAR_KIND_COUNT):  # pragma: no branch
                marks.append(wear.component(v, c))
            color = worn_color(color, marks)
        colors.append(color.x)
        colors.append(color.y)
        colors.append(color.z)
    piece.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
