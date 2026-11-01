# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How a garment is cut at the neck, where it is open, and how full its
sleeves are.

A cover says which bones a garment covers. It cannot leave the front of
the neck bare, part a coat's skirts, or swell a sleeve. Three kinds on a
garment do:

| Kind | Values |
|---|---|
| `Neckline` | round, a V, square, a scoop, a slit |
| `Opening` | closed, open down the front, open below the waist, the front alone |
| `Sleeve` | fitted, bishop, puffed at the shoulder |

`opening_field` is how far a point lies from the cut-away part, in
meters, positive where the garment stays. Each neckline and opening is
a few planes and an oval, scaled to the stature:

| Cut | Shape on the template |
|---|---|
| V neck | to 17 cm below the neck's joint, 14 cm wide at the neck |
| square neck | 14 cm below the neck's joint, 22 cm wide |
| scoop neck | an oval 30 cm wide and 13 cm deep under the neck |
| slit neck | 14 cm deep, 5 cm wide at the top, closing to its foot |
| open front | a gap 12 cm wide, from the neck to the hem |
| open below | from the waist down, 6 cm wide there and parting by a quarter of the fall |
| front only | the part 3 cm or more in front of the trunk's middle |

Each cut is in front of the trunk's middle alone, but for the front
alone, which keeps that and nothing behind it.

`opening_mask` turns the field into a share of the cover: zero inside
the cut, one past `OPENING_RAMP` from it, and one half on its line.
`dress` multiplies the garment's cover by it. So the garment is cut on
the line, the garment under it shows through, and its cover falls to
the trim's level along the cut, as at a hem: the trim runs round a
neckline and down an opening. A skirt's tube is cut on the same line.

`sleeve_lift` is how much farther out than its fitted shell a sleeve
stands at a point. A bishop sleeve swells down the forearm, `PUFF` at
its fullest, and closes to the wrist at the cuff. A puffed shoulder
swells round the top two fifths of the upper arm, `SHOULDER_PUFF` at
its fullest. The lift is shared by the skin
weights, so it fades into the shoulder and the hand.

This is not a three.js port. See Extensions.

    var mask = opening_mask(rig, SQUARE_NECK, CLOSED, point)
    var lift = sleeve_lift(rig, BISHOP_SLEEVE, joint, point)
"""

from std.math import pi, sin, sqrt

from core.buffer_geometry import POSITION, BufferGeometry
from extensions.attire.mesh_ops import COVER, cut
from extensions.attire.kinds import (
    BISHOP_SLEEVE,
    CLOSED,
    FITTED_SLEEVE,
    FRONT_ONLY,
    OPEN_BELOW,
    OPEN_FRONT,
    ROUND_NECK,
    SCOOP_NECK,
    SLIT_NECK,
    SQUARE_NECK,
    V_NECK,
    Neckline,
    Opening,
    Sleeve,
)
from extensions.humanoid.rig.joints import (
    HIPS,
    LEFT_FOREARM,
    LEFT_UPPER_ARM,
    NECK,
    RIGHT_FOREARM,
    RIGHT_UPPER_ARM,
    SPINE,
    HumanoidRig,
)
from math.utils import clamp
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT

comptime OPENING_STATURE = Float32(1.8288)
"""The template stature the cuts are sized for, in meters."""
comptime OPENING_RAMP = Float32(0.12)
"""Over how many meters on the template the cover falls to nothing at a
cut."""
comptime OPEN = Float32(-1)
"""The field inside a cut, far from any garment that stays."""
comptime KEPT = Float32(1)
"""The field where no cut reaches."""
comptime PUFF = Float32(0.035)
"""How much farther out a bishop sleeve stands at its fullest, in meters
on the template."""
comptime SHOULDER_PUFF = Float32(0.024)
"""How much farther out a puffed shoulder stands at its fullest, in
meters on the template."""


def _scale(rig: HumanoidRig) -> Float32:
    """Return the rig's stature over the template's."""
    return rig.stature / OPENING_STATURE


def neckline_field(rig: HumanoidRig, neckline: Neckline, p: Vector3) -> Float32:
    """Return how far a point lies from a neckline's cut, in meters.

    Args:
        rig: The rig.
        neckline: The neckline.
        p: The point, in the pelvis frame.

    Returns:
        Positive where the garment stays, negative in the cut. `KEPT`
        for a round neck, and behind the trunk's middle.
    """
    var neck = rig.joints[NECK.value]
    var s = _scale(rig)
    # Behind the trunk's middle, no neckline cuts.
    var behind = neck.z - p.z
    var dx = abs(p.x - neck.x)
    if neckline == V_NECK:
        var line = neck.y - 0.17 * s + dx * (0.17 / 0.07)
        return max(line - p.y, behind)
    if neckline == SQUARE_NECK:
        return max(max(neck.y - 0.14 * s - p.y, dx - 0.11 * s), behind)
    if neckline == SCOOP_NECK:
        var across = dx / (0.15 * s)
        var down = (p.y - neck.y - 0.02 * s) / (0.15 * s)
        return max((sqrt(across * across + down * down) - 1) * 0.15 * s, behind)
    if neckline == SLIT_NECK:
        var foot = neck.y - 0.14 * s
        var wide = 0.025 * s * clamp((p.y - foot) / (0.14 * s), 0, 1)
        return max(max(dx - wide, foot - p.y), behind)
    return KEPT


def opening_field(rig: HumanoidRig, opening: Opening, p: Vector3) -> Float32:
    """Return how far a point lies from an opening's cut, in meters.

    Args:
        rig: The rig.
        opening: The opening.
        p: The point, in the pelvis frame.

    Returns:
        Positive where the garment stays, negative in the cut. `KEPT`
        for a closed garment.
    """
    var hips = rig.joints[HIPS.value]
    var s = _scale(rig)
    var behind = hips.z - p.z
    var dx = abs(p.x - hips.x)
    if opening == OPEN_FRONT:
        return max(dx - 0.06 * s, behind)
    if opening == OPEN_BELOW:
        var waist = rig.joints[SPINE.value].y
        var gap = 0.03 * s + 0.25 * max(Float32(0), waist - p.y)
        return max(max(dx - gap, p.y - waist), behind)
    if opening == FRONT_ONLY:
        return p.z - hips.z - 0.03 * s
    return KEPT


def cut_field(
    rig: HumanoidRig, neckline: Neckline, opening: Opening, p: Vector3
) -> Float32:
    """Return how far a point lies from a garment's cuts, in meters.

    Args:
        rig: The rig.
        neckline: The garment's neckline.
        opening: The garment's opening.
        p: The point, in the pelvis frame.

    Returns:
        Positive where the garment stays: the nearer of its neckline's
        and its opening's fields.
    """
    return min(neckline_field(rig, neckline, p), opening_field(rig, opening, p))


def is_cut(neckline: Neckline, opening: Opening) -> Bool:
    """Return whether a garment is cut anywhere its cover is not.

    Args:
        neckline: The garment's neckline.
        opening: The garment's opening.

    Returns:
        False for a round-necked, closed garment.
    """
    return neckline != ROUND_NECK or opening != CLOSED


def opening_mask(
    rig: HumanoidRig, neckline: Neckline, opening: Opening, p: Vector3
) -> Float32:
    """Return the share of its cover a garment keeps at a point.

    Args:
        rig: The rig.
        neckline: The garment's neckline.
        opening: The garment's opening.
        p: The point, in the pelvis frame.

    Returns:
        One half on the cut's line, zero inside the cut, and one at
        `OPENING_RAMP` past it, scaled to the stature.
    """
    var ramp = OPENING_RAMP * _scale(rig)
    return clamp(cut_field(rig, neckline, opening, p) / ramp + 0.5, 0, 1)


def sleeve_lift(
    rig: HumanoidRig, sleeve: Sleeve, joint: Int, p: Vector3
) -> Float32:
    """Return how much farther out a sleeve stands over one bone at a
    point, in meters.

    Args:
        rig: The rig.
        sleeve: The garment's sleeve.
        joint: The bone that weighs on the point.
        p: The point, in the pelvis frame.

    Returns:
        Zero for a fitted sleeve, and for a bone but the upper arms and
        the forearms.
    """
    var upper = joint == RIGHT_UPPER_ARM.value or joint == LEFT_UPPER_ARM.value
    var fore = joint == RIGHT_FOREARM.value or joint == LEFT_FOREARM.value
    if sleeve == FITTED_SLEEVE or not (upper or fore):
        return 0
    var a = rig.joints[joint]
    var bone = rig.ends[joint] - a
    var length = max(bone.length(), Float32(1e-6))
    var t = clamp((p - a).dot(bone) / (length * length), 0, 1)
    var s = _scale(rig)
    if sleeve == BISHOP_SLEEVE:
        if upper:
            return PUFF * s * 0.4 * t
        # Fullest a little above the wrist, gathered at the cuff.
        return PUFF * s * (0.4 + 0.6 * t) * clamp((0.95 - t) / 0.2, 0, 1)
    # A puffed shoulder swells round the top half of the upper arm.
    if upper:
        var bulge = sin(Float32(pi) * clamp(t / 0.42, 0, 1))
        return SHOULDER_PUFF * s * max(Float32(0), bulge)
    return 0


def cut_open(
    piece: BufferGeometry,
    rig: HumanoidRig,
    neckline: Neckline,
    opening: Opening,
    below: Float32,
) raises -> BufferGeometry:
    """Cut a garment's piece along its neckline and its opening.

    A skirt's tube is lofted from rings, not cut from the skin, so the
    cover cannot open it. This cuts it on the cut's line, and lowers the
    `cover` of the vertices below `below` by the mask, so a trim runs
    down the cut's edge there as at a hem.

    Args:
        piece: A garment's piece, with positions and a `cover`
            attribute, in the pelvis frame.
        rig: The rig it was made on.
        neckline: The garment's neckline.
        opening: The garment's opening.
        below: The height below which the cover is lowered.

    Returns:
        The piece, cut.

    Raises:
        Error: If the piece has no positions or no cover.
    """
    ref placed = piece.attribute_view(String(POSITION))
    var field = List[Float32](capacity=placed.count())
    for v in range(placed.count()):
        field.append(cut_field(rig, neckline, opening, placed.vector3(v)))
    var kept = cut(piece, field, 0)
    ref points = kept.attribute_view(String(POSITION))
    var covers = kept.clone_attribute(String(COVER))
    for v in range(points.count()):
        var p = points.vector3(v)
        if p.y < below:
            covers.set_component(
                v,
                0,
                covers.component(v, 0)
                * opening_mask(rig, neckline, opening, p),
            )
    kept.set_attribute(String(COVER), covers^)
    return kept^


def sleeve_lifts(
    skin: BufferGeometry, rig: HumanoidRig, sleeve: Sleeve
) raises -> List[Float32]:
    """Return how much farther out a sleeve stands at each skin vertex.

    Args:
        skin: A skin with positions and four skin weights a vertex.
        rig: The rig it is bound to.
        sleeve: The garment's sleeve.

    Returns:
        One lift per vertex, in meters: each bone's `sleeve_lift`, by its
        weight.

    Raises:
        Error: If the skin has no positions or skin weights.
    """
    ref points = skin.attribute_view(String(POSITION))
    ref bones = skin.attribute_view(String(SKIN_INDEX))
    ref weights = skin.attribute_view(String(SKIN_WEIGHT))
    var lifts = List[Float32](capacity=points.count())
    for v in range(points.count()):
        var p = points.vector3(v)
        var lift = Float32(0)
        for k in range(4):  # pragma: no branch
            lift += weights.component(v, k) * sleeve_lift(
                rig, sleeve, Int(bones.component(v, k)), p
            )
        lifts.append(lift)
    return lifts^
