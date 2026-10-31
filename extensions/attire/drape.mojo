# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Colliders fit to a dressed person, for a cloak to fall over.

A cloak falls against capsules on the body's bones. A robe flares off
the legs, a pauldron stands off the shoulder, and a fur mantle is thick
on it. The body's capsules lie inside them, so a cloak falls through
them. `dressed_colliders` fits capsules to the garments' shells instead:

1. Each capsule of `body_colliders` is cut into `DRAPE_PARTS` capsules
   along its bone.
2. Each vertex of a garment's shell grows a part of the bone that
   weighs it most, the part whose skin it lies nearest, so that the part
   holds the vertex `DRAPE_MARGIN` inside it. The neck's vertices grow
   the chest's parts. The trunk is wider than it is deep, so a part of the
   trunk grows to hold its garments' depth, before and behind it, alone. A vertex of a bone with no capsule, a hand's or a
   foot's, grows nothing. A part grows by `DRAPE_GROWTH`, or to twice its
   radius, at the most, so a wide sleeve does not swing a great capsule
   through the cloak.
3. A skirt hangs round both legs, far from each. A skirted garment's
   vertices below the skirt's top are sliced into bands `DRAPE_BAND`
   high. Each band is held in a capsule laid across the hips, as wide
   and as deep as the band, on the hips' bone.
4. A hat is left out: a cloak falls below it.

The colliders are fit at rest. A garment skinned to the legs moves a
little off them as the legs swing, so a skirt's capsules are made deeper
toward the hem by `DRAPE_SWING` of the fall.

This is not a three.js port. See Extensions.

    var dressed = dress(scene, assets, person, outfit)
    var over = dressed_colliders(person, outfit, dressed)
    var cloak = add_cloak(scene, assets, person, cut, over)
"""

from core.buffer_geometry import POSITION
from extensions.attire.kinds import HATTED, SKIRTED
from extensions.attire.outfit import Dressed, Outfit
from extensions.attire.skirt import skirt_scale, skirt_top
from extensions.attire.springs import (
    SpringCollider,
    body_colliders,
    nearest_on_segment,
)
from extensions.humanoid.rig.game import GameHumanoid
from extensions.humanoid.rig.joints import CHEST, HIPS, JOINT_COUNT, NECK
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX

comptime DRAPE_PARTS = 3
"""The capsules each of the body's capsules is cut into, along its bone."""
comptime DRAPE_MARGIN = Float32(0.004)
"""How far inside a fit capsule a garment's vertex lies, in meters."""
comptime DRAPE_GROWTH = Float32(0.12)
"""The most a part grows to hold a garment, in meters on the template."""
comptime DRAPE_BAND = Float32(0.04)
"""How high each band of a skirt is, in meters on the template."""
comptime DRAPE_SWING = Float32(0.04)
"""How much deeper a skirt's capsule is at the hem than at its top, as a
share of how far the hem falls below the top."""


def body_parts(person: GameHumanoid) raises -> List[SpringCollider]:
    """Return the body's capsules, each cut into `DRAPE_PARTS` along its
    bone.

    Args:
        person: The person.

    Returns:
        The parts, `DRAPE_PARTS` for each capsule in the order of
        `body_colliders`, each of its capsule's radius. A sphere is cut
        into spheres that match it.
    """
    var parts = List[SpringCollider]()
    for collider in body_colliders(person):  # pragma: no branch
        var along = collider.end - collider.start
        for k in range(DRAPE_PARTS):  # pragma: no branch
            var a = Float32(k) / Float32(DRAPE_PARTS)
            var b = Float32(k + 1) / Float32(DRAPE_PARTS)
            parts.append(
                SpringCollider(
                    collider.node,
                    collider.start + along * a,
                    collider.start + along * b,
                    collider.radius,
                )
            )
    return parts^


def skirt_bands(
    person: GameHumanoid, points: List[Vector3]
) -> List[SpringCollider]:
    """Return a capsule across the hips for each band of a skirt's
    points, on the hips' bone.

    The bands are `DRAPE_BAND` high, from the skirt's top down. Each
    capsule lies across the person, as wide as its band's points and as
    deep, `DRAPE_MARGIN` outside them. It is `DRAPE_SWING` of its fall
    deeper, so the skirt stays inside it as the legs swing. A band with
    no point has no capsule.

    Args:
        person: The person.
        points: The points of skirts below the skirt's top, at rest, in
            the rig's frame.

    Returns:
        The capsules, from the top band down.
    """
    var s = skirt_scale(person.rig)
    var top = skirt_top(person.rig)
    var band = DRAPE_BAND * s
    var lowest = top
    for p in points:  # pragma: no branch
        lowest = min(lowest, p.y)
    var count = Int((top - lowest) / band) + 1
    var low_x = List[Float32](length=count, fill=1e9)
    var high_x = List[Float32](length=count, fill=-1e9)
    var low_z = List[Float32](length=count, fill=1e9)
    var high_z = List[Float32](length=count, fill=-1e9)
    for p in points:  # pragma: no branch
        var k = min(count - 1, Int((top - p.y) / band))
        low_x[k] = min(low_x[k], p.x)
        high_x[k] = max(high_x[k], p.x)
        low_z[k] = min(low_z[k], p.z)
        high_z[k] = max(high_z[k], p.z)
    var hips = person.rig.joints[HIPS.value]
    var bands = List[SpringCollider]()
    for k in range(count):  # pragma: no branch
        if high_x[k] < low_x[k]:
            continue
        var y = top - (Float32(k) + 0.5) * band
        var fall = top - y
        var deep = (high_z[k] - low_z[k]) / 2 + DRAPE_MARGIN
        deep += DRAPE_SWING * fall
        var wide = (high_x[k] - low_x[k]) / 2 + DRAPE_MARGIN
        var middle = Vector3(
            (high_x[k] + low_x[k]) / 2, y, (high_z[k] + low_z[k]) / 2
        )
        var half = max(Float32(0), wide - deep)
        bands.append(
            SpringCollider(
                person.bones[HIPS.value],
                middle - Vector3(half, 0, 0) - hips,
                middle + Vector3(half, 0, 0) - hips,
                deep,
            )
        )
    return bands^


def dressed_colliders(
    person: GameHumanoid, outfit: Outfit, dressed: Dressed
) raises -> List[SpringCollider]:
    """Return capsules that hold a cloak off a dressed person's garments.

    Args:
        person: The person, as `dress` dressed them.
        outfit: The outfit they were dressed in.
        dressed: What `dress` returned for it.

    Returns:
        The body's parts, each grown to hold the garments over it, then
        one capsule for each band of the skirts.

    Raises:
        Error: If the outfit and what was dressed do not match, or a
            shell has no positions or skin indices.
    """
    if len(dressed.shells) != len(outfit.garments):
        raise Error("A dressed outfit needs one shell per garment")
    var s = skirt_scale(person.rig)
    var top = skirt_top(person.rig)
    var parts = body_parts(person)
    # Each part's ends and radius at rest, in the rig's frame.
    var starts = List[Vector3]()
    var ends = List[Vector3]()
    var base = List[Float32]()
    var joints = List[Int]()
    for part in parts:  # pragma: no branch
        var joint = 0
        for j in range(JOINT_COUNT):  # pragma: no branch
            if person.bones[j] == part.node:
                joint = j
        var at = person.rig.joints[joint]
        starts.append(at + part.start)
        ends.append(at + part.end)
        base.append(part.radius)
        joints.append(joint)
    var skirted = List[Vector3]()
    for g in range(len(outfit.garments)):  # pragma: no branch
        ref garment = outfit.garments[g]
        # A hat is left out, and so is a garment that covers nothing.
        if garment.form == HATTED or not dressed.shells[g].has_attribute(
            String(POSITION)
        ):
            continue
        ref placed = dressed.shells[g].attribute_view(String(POSITION))
        ref bones = dressed.shells[g].attribute_view(String(SKIN_INDEX))
        for v in range(placed.count()):  # pragma: no branch
            var p = placed.vector3(v)
            if garment.form == SKIRTED and p.y < top:
                skirted.append(p)
                continue
            # A garment keeps its four bones heaviest first.
            var joint = Int(bones.component(v, 0))
            if joint == NECK.value:
                joint = CHEST.value
            var best = -1
            var nearest = Float32(1e30)
            var reach = Float32(0)
            for k in range(len(parts)):  # pragma: no branch
                if joints[k] != joint:
                    continue
                var off = p - nearest_on_segment(p, starts[k], ends[k])
                var d = off.length()
                if d - base[k] < nearest:
                    nearest = d - base[k]
                    best = k
                    # The trunk is wider than it is deep. A round part as
                    # wide as the hips would stand far off the back, so
                    # a trunk's part holds its garments' depth alone.
                    reach = abs(off.z) if joint <= CHEST.value else d
            if best < 0:
                continue
            var most = min(base[best] + DRAPE_GROWTH * s, 2 * base[best])
            parts[best].radius = min(
                most, max(parts[best].radius, reach + DRAPE_MARGIN)
            )
    if len(skirted) > 0:
        parts.extend(skirt_bands(person, skirted))
    return parts^
