# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Domed pauldrons: each shoulder closed in one smooth plate.

A pauldron made from the skin follows the shoulder's muscles, and reads
as a sleeve. A heroic pauldron does not: it stands well off the shoulder
in one dome, over the garments under it. `dome_shoulders` replaces a
`DOMED` garment's shell with a dome over each shoulder:

1. The shell is split at the middle of the chest into each shoulder's
   part.
2. Each part's vertices are closed in their convex hull.
3. A sphere of `DOME_RINGS` rings and `DOME_SECTORS` sectors, stretched
   to the part's box, is cast from the hull's middle onto the hull,
   `DOME_STAND` out of it.
4. The dome is cut where it turns in toward the body, past `DOME_TUCK` of
   its half width from its middle, and under the armpit. The band along
   that edge takes the trim.
5. A lining a fabric's thickness inside it shows under its edge.
6. Each vertex takes the skin weights of the nearest vertex of the shell,
   so the dome rides the chest and the upper arm, and a lamed dome opens
   as the arm rises.

This is not a three.js port. See Extensions.

    var domes = dome_shoulders(whole, rig, thickness)
"""

from std.math import cos, pi, sin

from core.buffer_geometry import POSITION, BufferGeometry
from extensions.attire.last import FootLast, foot_last
from extensions.attire.mesh_ops import MeshWriter, cut, merge
from extensions.attire.skirt import skirt_scale
from extensions.humanoid.rig.joints import CHEST, RIGHT_UPPER_ARM, HumanoidRig
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT

comptime DOME_RINGS = 16
"""The rings of the sphere a dome is cast from, pole to pole."""
comptime DOME_SECTORS = 24
"""The sectors of the sphere a dome is cast from, round its axis."""
comptime DOME_STAND = Float32(0.022)
"""How far a dome stands out of the hull, in meters on the template."""
comptime DOME_TUCK = Float32(0.35)
"""How far toward the body a dome reaches past its middle, as a share of
its half width."""
comptime DOME_DROP = Float32(0.7)
"""How far below its middle a dome reaches, as a share of its half
height."""
comptime DOME_RIM = Float32(0.018)
"""How wide the trimmed band along a dome's edge is, in meters on the
template."""
comptime DOME_TRIM = Float32(0.5)
"""The cover value of a dome's trim."""


def shoulder_points(
    piece: BufferGeometry, rig: HumanoidRig, right: Bool
) raises -> List[Vector3]:
    """Return the vertices of a shell on one side of the chest's middle.

    Args:
        piece: A garment's shell.
        rig: The rig it was made on.
        right: Whether to take the side the right arm is on.

    Returns:
        Their positions.

    Raises:
        Error: If the mesh has no positions.
    """
    ref placed = piece.attribute_view(String(POSITION))
    var middle = rig.joints[CHEST.value].x
    var side = rig.joints[RIGHT_UPPER_ARM.value].x - middle
    if not right:
        side = -side
    var points = List[Vector3]()
    for v in range(placed.count()):
        var p = placed.vector3(v)
        if (p.x - middle) * side > 0:
            points.append(p)
    return points^


def _nearest(points: List[Vector3], p: Vector3) -> Int:
    """Return the index of the point nearest `p`."""
    var best = 0
    var closest = Float32(1e30)
    for k in range(len(points)):  # pragma: no branch
        var d = (points[k] - p).length_sq()
        if d < closest:
            closest = d
            best = k
    return best


def _corner(ring: Int, sector: Int) -> Int:
    """Return the vertex of the cast sphere at a ring and a sector.

    A pole is one vertex. The sectors wrap round.
    """
    if ring == 0:
        return 0
    if ring == DOME_RINGS:
        return 1 + (DOME_RINGS - 1) * DOME_SECTORS
    return 1 + (ring - 1) * DOME_SECTORS + sector % DOME_SECTORS


def dome_mesh(
    hull: FootLast,
    piece: BufferGeometry,
    rig: HumanoidRig,
    thickness: Float32,
) raises -> BufferGeometry:
    """Return the mesh of one shoulder's dome and its lining.

    Args:
        hull: The hull of the shoulder's part of the shell.
        piece: The garment's shell, whose attributes the dome takes and
            whose nearest vertex gives each of its vertices its weights.
        rig: The rig it was made on.
        thickness: How far inside the dome its lining lies, in meters.

    Returns:
        The dome and its lining, cut where they turn in toward the body
        and under the armpit, with the garment's attributes and normals.

    Raises:
        Error: If the mesh has no positions or skin weights.
    """
    ref placed = piece.attribute_view(String(POSITION))
    ref bones = piece.attribute_view(String(SKIN_INDEX))
    ref weights = piece.attribute_view(String(SKIN_WEIGHT))
    var points = List[Vector3](capacity=placed.count())
    for v in range(placed.count()):  # pragma: no branch
        points.append(placed.vector3(v))
    var s = skirt_scale(rig)
    var c = hull.center
    var chest = rig.joints[CHEST.value]
    # Out from the body, level.
    var away = Vector3(c.x - chest.x, 0, 0)
    away.normalize()
    var tuck = DOME_TUCK * hull.reach.x
    var floor = c.y - DOME_DROP * hull.reach.y
    var writer = MeshWriter(piece)
    var keep = List[Float32]()
    var inner = List[Vector3]()
    var shares = List[List[Float32]]()
    var fours = List[List[Int]]()
    var covers = List[Float32]()
    for ring in range(DOME_RINGS + 1):  # pragma: no branch
        var sectors = DOME_SECTORS
        if ring == 0 or ring == DOME_RINGS:
            sectors = 1
        for sector in range(sectors):  # pragma: no branch
            var down = Float32(pi) * Float32(ring) / Float32(DOME_RINGS)
            var round = (
                2 * Float32(pi) * Float32(sector) / Float32(DOME_SECTORS)
            )
            var d = Vector3(
                hull.reach.x * sin(down) * cos(round),
                hull.reach.y * cos(down),
                hull.reach.z * sin(down) * sin(round),
            )
            d = d * (1 / max(d.length(), Float32(1e-12)))
            var p = c + d * (hull.cast(d) + DOME_STAND * s)
            var value = min((p - c).dot(away) + tuck, p.y - floor)
            keep.append(value)
            var cover = Float32(1)
            if value < DOME_RIM * s:
                cover = DOME_TRIM
            covers.append(cover)
            var source = _nearest(points, p)
            var four = List[Int](length=4, fill=0)
            var share = List[Float32](length=4, fill=0)
            for k in range(4):  # pragma: no branch
                four[k] = Int(bones.component(source, k))
                share[k] = weights.component(source, k)
            _ = writer.add(p, cover, four, share)
            inner.append(p - d * thickness)
            fours.append(four^)
            shares.append(share^)
    var count = len(inner)
    for k in range(count):  # pragma: no branch
        keep.append(keep[k])
        _ = writer.add(inner[k], covers[k], fours[k], shares[k])
    for ring in range(DOME_RINGS):  # pragma: no branch
        for sector in range(DOME_SECTORS):  # pragma: no branch
            var a = _corner(ring, sector)
            var b = _corner(ring, sector + 1)
            var c2 = _corner(ring + 1, sector)
            var d2 = _corner(ring + 1, sector + 1)
            # Each quad is two triangles, wound to face out of the sphere.
            # At a pole one of them has two corners on the pole, and is
            # left out.
            if ring > 0:
                writer.triangle(a, b, c2)
                writer.triangle(count + a, count + c2, count + b)
            if ring < DOME_RINGS - 1:
                writer.triangle(b, d2, c2)
                writer.triangle(count + b, count + c2, count + d2)
    return cut(writer.build(), keep, 0)


def dome_shoulders(
    whole: BufferGeometry, rig: HumanoidRig, thickness: Float32
) raises -> BufferGeometry:
    """Return a garment's shell replaced by a dome over each shoulder.

    Args:
        whole: The garment's whole shell, cut at its hems, in the pelvis
            frame.
        rig: The rig it was made on.
        thickness: How far inside each dome its lining lies, in meters.

    Returns:
        The domes. The shell as it is when neither side has four points.

    Raises:
        Error: If the mesh has no positions or skin weights, or a side's
            points all lie in one plane.
    """
    var domes = Optional[BufferGeometry](None)
    for right in [True, False]:  # pragma: no branch
        var points = shoulder_points(whole, rig, right)
        if len(points) < 4:
            continue
        var dome = dome_mesh(foot_last(points), whole, rig, thickness)
        if domes:
            domes = merge(domes.value(), dome)
        else:
            domes = dome^
    if not domes:
        return whole.clone()
    return domes.take()
