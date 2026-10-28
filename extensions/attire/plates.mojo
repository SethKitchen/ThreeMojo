# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How plate follows the bones: rigid, or in lames.

A flexible garment keeps the skin's weights and bends as the skin bends.
Plate does not bend:

- A rigid garment with an anchor rides that one bone. A cuirass rides
  the chest, a bascinet the head.
- A rigid garment without an anchor rides, at each vertex, the heaviest
  bone it covers. A pair of greaves thus rides each shin.
- A lamed garment is cut into bands, the lames. The top lame rides the
  anchor wholly. Each lame below it shares more of its weight with the
  bones under it, in equal steps, until the last follows the skin. The
  bands follow the anchor's own weight on the skin, so each lame is a
  smooth band round the body. A fauld thus opens as the thigh lifts, and
  a pauldron as the arm rises.

Each lame is a separate piece. It reaches a little past its band, under
the top of the lame below it, and stands a little out over that lame,
so each lame shows its lower edge as a lip, as riveted lames do. The
lames part a little as they turn.

This is not a three.js port. See Extensions.

    var plate = articulate(piece, garment)
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from extensions.attire.garment import NO_ANCHOR, Garment
from extensions.attire.kinds import LAMED, RIGID
from extensions.attire.mesh_ops import cut_attribute, merge
from extensions.humanoid.rig.joints import JOINT_COUNT, Joint
from extensions.humanoid.rig.weights import rigid_weights
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT

comptime BAND = "band"
"""The attribute that carries each vertex's band while a garment is cut into
lames."""
comptime LAME_OVERLAP = Float32(0.3)
"""How far, in bands, each lame reaches past its band's lower bound, under
the top of the lame below it."""
comptime LAME_STEP = Float32(0.0025)
"""How far each lame stands out over the one below it, in meters."""


def anchor_weights(
    piece: BufferGeometry, anchor: Joint
) raises -> List[Float32]:
    """Return the weight one bone has on each vertex.

    Args:
        piece: A skinned mesh.
        anchor: A joint.

    Returns:
        One weight per vertex, zero where the bone has none.

    Raises:
        Error: If the mesh has no skin weights.
    """
    ref bones = piece.attribute_view(String(SKIN_INDEX))
    ref weights = piece.attribute_view(String(SKIN_WEIGHT))
    var out = List[Float32](capacity=bones.count())
    for v in range(bones.count()):
        var w = Float32(0)
        for k in range(4):  # pragma: no branch
            if Int(bones.component(v, k)) == anchor.value:
                w += weights.component(v, k)
        out.append(w)
    return out^


def ride_covered(mut piece: BufferGeometry, garment: Garment) raises:
    """Bind each vertex wholly to the heaviest bone the garment covers.

    A vertex none of whose bones the garment covers rides its heaviest
    bone.

    Args:
        piece: A skinned garment.
        garment: Its description.

    Raises:
        Error: If the mesh has no skin weights.
    """
    ref bones = piece.attribute_view(String(SKIN_INDEX))
    ref weights = piece.attribute_view(String(SKIN_WEIGHT))
    var indices = List[Float32](capacity=4 * bones.count())
    var ones = List[Float32](capacity=4 * bones.count())
    for v in range(bones.count()):
        var best = Int(bones.component(v, 0))
        var heaviest = Float32(-1)
        var covered = False
        for k in range(4):  # pragma: no branch
            var bone = Int(bones.component(v, k))
            var weight = weights.component(v, k)
            var mine = garment.cover.covers(Joint(bone))
            # A covered bone beats any bone that is not covered.
            if (mine and not covered) or (
                mine == covered and weight > heaviest
            ):
                best = bone
                heaviest = weight
                covered = mine
        indices.append(Float32(best))
        indices.append(0)
        indices.append(0)
        indices.append(0)
        ones.append(1)
        ones.append(0)
        ones.append(0)
        ones.append(0)
    piece.set_attribute(String(SKIN_INDEX), BufferAttribute(indices^, 4))
    piece.set_attribute(String(SKIN_WEIGHT), BufferAttribute(ones^, 4))


def share_with(mut piece: BufferGeometry, anchor: Joint, share: Float32) raises:
    """Give each vertex the anchor's weight, but for a share of its own.

    Each vertex's weights become `1 - share` on the anchor, plus `share`
    times the weights it had.

    Args:
        piece: A skinned mesh.
        anchor: A named joint.
        share: How much of its own weights a vertex keeps, zero through
            one.

    Raises:
        Error: If the mesh has no skin weights.
    """
    ref bones = piece.attribute_view(String(SKIN_INDEX))
    ref weights = piece.attribute_view(String(SKIN_WEIGHT))
    var indices = List[Float32](capacity=4 * bones.count())
    var kept = List[Float32](capacity=4 * bones.count())
    for v in range(bones.count()):
        var mixed = List[Float32](length=JOINT_COUNT, fill=0)
        mixed[anchor.value] = 1 - share
        for k in range(4):  # pragma: no branch
            var bone = Int(bones.component(v, k))
            mixed[bone] += share * weights.component(v, k)
        var chosen = List[Int]()
        var total = Float32(0)
        for _ in range(4):  # pragma: no branch
            var best = 0
            var heaviest = Float32(-1)
            for j in range(JOINT_COUNT):  # pragma: no branch
                if mixed[j] > heaviest and j not in chosen:
                    heaviest = mixed[j]
                    best = j
            chosen.append(best)
            total += mixed[best]
        for k in range(4):  # pragma: no branch
            indices.append(Float32(chosen[k]))
            kept.append(mixed[chosen[k]] / max(total, Float32(1e-30)))
    piece.set_attribute(String(SKIN_INDEX), BufferAttribute(indices^, 4))
    piece.set_attribute(String(SKIN_WEIGHT), BufferAttribute(kept^, 4))


def _stand_out(mut piece: BufferGeometry, distance: Float32) raises:
    """Move every vertex out along its normal."""
    ref normals = piece.attribute_view(String(NORMAL))
    var places = piece.clone_attribute(String(POSITION))
    for v in range(places.count()):
        var p = places.vector3(v) + normals.vector3(v) * distance
        places.set_component(v, 0, p.x)
        places.set_component(v, 1, p.y)
        places.set_component(v, 2, p.z)
    piece.set_attribute(String(POSITION), places^)


def lames(
    piece: BufferGeometry, anchor: Joint, count: Int
) raises -> BufferGeometry:
    """Cut a garment into lames and bind each one a step further from
    the anchor.

    Args:
        piece: A skinned garment.
        anchor: The bone the top lame rides.
        count: How many lames, two or more.

    Returns:
        The lames, as one mesh of separate pieces.

    Raises:
        Error: If `count` is below two or the mesh has no skin weights.
    """
    if count < 2:
        raise Error("Lames come two or more to a garment")
    var on_anchor = anchor_weights(piece, anchor)
    # The band coordinate: zero where the anchor holds the skin wholly,
    # `count` where it holds none of it. It rides on the mesh, so each
    # cut carries it to the vertices it makes.
    var band = List[Float32](capacity=len(on_anchor))
    for w in on_anchor:
        band.append((1 - w) * Float32(count))
    var banded = piece.clone()
    banded.set_attribute(String(BAND), BufferAttribute(band^, 1))
    var joined = Optional[BufferGeometry](None)
    for k in range(count):  # pragma: no branch
        # Inside lame k: k <= band <= k + 1. The first and the last
        # lames reach past their outer bounds.
        var lame = banded.clone()
        if k > 0:
            lame = cut_attribute(lame, String(BAND), Float32(k), True)
        if k < count - 1:
            lame = cut_attribute(
                lame, String(BAND), Float32(k + 1) + LAME_OVERLAP, False
            )
        _stand_out(lame, LAME_STEP * Float32(count - 1 - k))
        share_with(lame, anchor, Float32(k) / Float32(count - 1))
        lame.delete_attribute(String(BAND))
        if joined:
            joined = merge(joined.value(), lame)
        else:
            joined = lame^
    return joined.take()


def articulate(
    var piece: BufferGeometry, garment: Garment
) raises -> BufferGeometry:
    """Return a garment bound to its bones as its articulation says.

    Args:
        piece: The garment's mesh, with the skin's weights.
        garment: Its description.

    Returns:
        The mesh, rebound. A flexible garment is returned unchanged.

    Raises:
        Error: If the garment does not check or the mesh has no skin
            weights.
    """
    garment.check()
    if garment.articulation == RIGID:
        if garment.anchor == NO_ANCHOR:
            ride_covered(piece, garment)
        else:
            rigid_weights(piece, garment.anchor)
        return piece^
    if garment.articulation == LAMED:
        return lames(piece, garment.anchor, garment.lames)
    return piece^
