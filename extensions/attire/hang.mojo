# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A loose garment hangs from the chest: it does not follow the body into
every hollow below it.

A shell made from the skin follows the skin. Under the bust, over the
small of the back and below the chest, a fitted garment does, and a
loose robe does not: its cloth falls from the widest point above and
bridges the hollow. `hang_lifts` gives the extra standoff that makes a
loose garment fall so, vertex by vertex, the way `sleeve_lifts` makes a
full sleeve:

1. The trunk between the waist joint and `HANG_TOP` of the way up to the
   neck is cut into `HANG_SECTORS` sectors round a vertical axis through
   the hips.
2. In each sector, from the top down, the cloth hangs as far out as the
   widest point above it, less `HANG_SLOPE` for each meter it falls.
3. A vertex inside that curtain is lifted out to it. The lift fades to
   none over the lowest `HANG_FADE` of the span, so the garment comes
   back to the body at the waist, where a belt cinches it.

Each lift is scaled by how much the trunk's bones weigh on the vertex,
so an arm hanging beside the body is not lifted. `hangs_loose` says which
garments hang: a closed, round- or slit-necked garment of cloth, skirted
below the hips, that covers the chest, such as a robe, a tunic, a gown or
a surcoat. A tailored coat, a ball gown, a bodice and armor are fitted.

This is not a three.js port. See Extensions.

    if hangs_loose(garment):
        var hang = hang_lifts(skin, rig)
"""

from core.buffer_geometry import POSITION, BufferGeometry
from extensions.attire.garment import Garment
from extensions.attire.kinds import (
    CLOSED,
    LEATHER,
    PADDING,
    ROUND_NECK,
    SKIRTED,
    SLIT_NECK,
)
from extensions.humanoid.rig.joints import (
    CHEST,
    HIPS,
    NECK,
    SPINE,
    HumanoidRig,
)
from math.utils import clamp
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from std.math import atan2, pi, sqrt

comptime HANG_SECTORS = 36
"""How many sectors the trunk is cut into round its axis."""
comptime HANG_TOP = Float32(0.5)
"""How far from the chest joint to the neck the hang starts, as a share."""
comptime HANG_SLOPE = Float32(0.2)
"""How far in the cloth draws for each meter it falls, in meters."""
comptime HANG_FADE = Float32(0.35)
"""The share of the span, from the waist up, over which the lift fades."""


def hangs_loose(garment: Garment) raises -> Bool:
    """Return whether a garment hangs loose from the chest.

    Args:
        garment: A garment.

    Returns:
        True for a closed garment of cloth, skirted, that covers the
        chest, with a round or a slit neck.

    Raises:
        Error: If the garment's cover cannot be read, which a checked
            garment's can.
    """
    return (
        garment.form == SKIRTED
        and garment.cover.covers(CHEST)
        and garment.opening == CLOSED
        and (garment.neckline == ROUND_NECK or garment.neckline == SLIT_NECK)
        and not garment.fabric.is_metal()
        and garment.fabric != LEATHER
        and garment.fabric != PADDING
    )


def _trunk_share(
    bones: List[Float32], weights: List[Float32], v: Int
) -> Float32:
    """Return how much the trunk's bones weigh on a vertex."""
    var share = Float32(0)
    for c in range(4):  # pragma: no branch
        var bone = Int(bones[4 * v + c])
        if bone == HIPS.value or bone == SPINE.value or bone == CHEST.value:
            share += weights[4 * v + c]
    return share


def hang_lifts(skin: BufferGeometry, rig: HumanoidRig) raises -> List[Float32]:
    """Return how much farther out a loose garment stands at each vertex.

    Args:
        skin: A skin with positions and four skin weights a vertex, in
            the pelvis frame.
        rig: The rig it is bound to.

    Returns:
        One lift per vertex, in meters. It is zero outside the trunk's
        span and at every vertex the curtain does not pass outside.

    Raises:
        Error: If the skin has no positions or skin weights.
    """
    ref points = skin.attribute_view(String(POSITION))
    var bones = skin.attribute_view(String(SKIN_INDEX)).packed()
    var weights = skin.attribute_view(String(SKIN_WEIGHT)).packed()
    var count = points.count()
    var lifts = List[Float32](length=count, fill=0)
    var axis = rig.joints[HIPS.value]
    var chest = rig.joints[CHEST.value].y
    var top = chest + HANG_TOP * (rig.joints[NECK.value].y - chest)
    var waist = rig.joints[SPINE.value].y
    if not (top > waist):
        return lifts^
    # Each sector's vertices in the span, from the top down.
    var sectors = List[List[Int]]()
    for _ in range(HANG_SECTORS):  # pragma: no branch
        sectors.append(List[Int]())
    var radii = List[Float32](length=count, fill=0)
    for v in range(count):  # pragma: no branch
        var p = points.vector3(v)
        if p.y > top or p.y < waist:
            continue
        if _trunk_share(bones, weights, v) <= 0:
            continue
        var dx = p.x - axis.x
        var dz = p.z - axis.z
        radii[v] = sqrt(dx * dx + dz * dz)
        var turn = (atan2(dx, dz) + Float32(pi)) / (2 * Float32(pi))
        var at = min(HANG_SECTORS - 1, Int(turn * Float32(HANG_SECTORS)))
        sectors[at].append(v)
    for s in range(HANG_SECTORS):  # pragma: no branch
        # Highest first.
        ref row = sectors[s]
        for i in range(1, len(row)):
            var v = row[i]
            var y = points.vector3(v).y
            var k = i
            while k > 0 and points.vector3(row[k - 1]).y < y:
                row[k] = row[k - 1]
                k -= 1
            row[k] = v
    for row in sectors:  # pragma: no branch
        var curtain = Float32(-1)
        var above = top
        for v in row:
            var y = points.vector3(v).y
            curtain = max(curtain - HANG_SLOPE * (above - y), radii[v])
            above = y
            var fade = clamp((y - waist) / (HANG_FADE * (top - waist)), 0, 1)
            lifts[v] = (
                (curtain - radii[v])
                * fade
                * min(Float32(1), _trunk_share(bones, weights, v))
            )
    return lifts^
