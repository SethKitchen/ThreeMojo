# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A hood's cowl: the head closed in one loose, smooth shape.

A garment made from the skin follows the ears, the nape and the hollow
under the chin, as a balaclava does. A hood does not: it hangs loose
round the head, from the crown down to the neck, and frames the face.
`hang_cowl` replaces the part of a hood's shell above the middle of the
neck with a mesh laid on the convex hull of the shell there:

1. `cowl_bottom` is at the base of the neck. The shell is cut a little
   below it, so its edge lies inside the cowl.
2. The shell's vertices above the bottom are closed in their convex
   hull. The hull spans the ears, the nape and the hollow under the
   chin.
3. A sphere of `COWL_RINGS` rings and `COWL_SECTORS` sectors, stretched
   to the hood's box, is cast from its middle onto the hull, `COWL_STAND`
   out of it, so the hood stands a little loose. The sphere's pole looks
   forward through the face, so its rings run round the face's opening.
4. The cowl is cut open at the face along the same oval as a fitted
   hood, and level at its bottom. A lining a fabric's thickness inside it
   shows where the face's opening looks into the hood.
5. Each vertex takes the skin weights of the nearest vertex of the shell,
   so the cowl turns with the head and the neck.

This is not a three.js port. See Extensions.

    var cowl = head_cowl(whole, rig)
    var hood = hang_cowl(piece, cowl, rig, True, thickness)
"""

from std.math import cos, pi, sin

from core.buffer_geometry import POSITION, BufferGeometry
from extensions.attire.cover import face_oval
from extensions.attire.last import FootLast, foot_last
from extensions.attire.mesh_ops import MeshWriter, cut, merge
from extensions.attire.skirt import leg_side, skirt_scale
from extensions.humanoid.rig.joints import HEAD, NECK, HumanoidRig
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT

comptime COWL_RINGS = 18
"""The rings of the sphere a cowl is cast from, pole to pole."""
comptime COWL_SECTORS = 28
"""The sectors of the sphere a cowl is cast from, round its axis."""
comptime COWL_STAND = Float32(0.006)
"""How far a cowl stands out of the hull, in meters on the template."""
comptime COWL_DROP = Float32(1.0)
"""How far down the neck a cowl reaches, from the skull, in neck lengths."""
comptime COWL_OVERLAP = Float32(0.015)
"""How far below a cowl's bottom the shell is cut, in meters on the
template, so the shell's edge lies inside the cowl."""
comptime COWL_RIM = Float32(0.004)
"""How far above its bottom a cowl is cut level, in meters on the
template, so its flat bottom is left out."""


def cowl_bottom(rig: HumanoidRig) -> Float32:
    """Return the height a cowl reaches down to.

    Args:
        rig: The rig the hood was made on.

    Returns:
        `COWL_DROP` of the way down the neck from the skull.
    """
    var skull = rig.joints[HEAD.value].y
    var base = rig.joints[NECK.value].y
    return skull + (base - skull) * COWL_DROP


def head_cowl(whole: BufferGeometry, rig: HumanoidRig) raises -> List[FootLast]:
    """Return the hull a hood's cowl is cast onto.

    Args:
        whole: The hood's whole shell, cut at its hems, with nothing
            hidden, in the pelvis frame.
        rig: The rig it was made on.

    Returns:
        One hull, of the shell's vertices above `cowl_bottom`, or none if
        fewer than four lie there.

    Raises:
        Error: If the mesh has no positions or skin weights, or the points
            all lie in one plane.
    """
    var legs = leg_side(whole)
    ref placed = whole.attribute_view(String(POSITION))
    var bottom = cowl_bottom(rig)
    var points = List[Vector3]()
    for v in range(placed.count()):
        var p = placed.vector3(v)
        if legs[v] and p.y > bottom:
            points.append(p)
    var hulls = List[FootLast]()
    if len(points) >= 4:
        hulls.append(foot_last(points))
    return hulls^


def _nearest(points: List[Vector3], p: Vector3) -> Int:
    """Return the index of the point nearest `p`, or -1 for none."""
    var best = -1
    var closest = Float32(1e30)
    for k in range(len(points)):
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
    if ring == COWL_RINGS:
        return 1 + (COWL_RINGS - 1) * COWL_SECTORS
    return 1 + (ring - 1) * COWL_SECTORS + sector % COWL_SECTORS


def cowl_mesh(
    hull: FootLast,
    piece: BufferGeometry,
    rig: HumanoidRig,
    open_face: Bool,
    thickness: Float32,
) raises -> BufferGeometry:
    """Return the mesh of a cowl, open at the face and at its bottom.

    Args:
        hull: The hull from `head_cowl`.
        piece: The hood's shell, whose attributes the cowl takes and whose
            nearest vertex gives each of its vertices its weights.
        rig: The rig the hood was made on.
        open_face: Whether to cut it open at the face.
        thickness: How far inside the cowl its lining lies, in meters.

    Returns:
        The cowl and its lining, with the hood's attributes and normals.
        The lining shows where the face's opening looks into the hood.

    Raises:
        Error: If the mesh has no positions or skin weights.
    """
    ref placed = piece.attribute_view(String(POSITION))
    ref bones = piece.attribute_view(String(SKIN_INDEX))
    ref weights = piece.attribute_view(String(SKIN_WEIGHT))
    var points = List[Vector3](capacity=placed.count())
    for v in range(placed.count()):
        points.append(placed.vector3(v))
    var stand = COWL_STAND * skirt_scale(rig)
    var writer = MeshWriter(piece)
    var keep = List[Float32]()
    var floor = cowl_bottom(rig) + COWL_RIM * skirt_scale(rig)
    var lining = List[Vector3]()
    var linings = List[List[Int]]()
    var linings_weights = List[List[Float32]]()
    for ring in range(COWL_RINGS + 1):  # pragma: no branch
        var sectors = COWL_SECTORS
        if ring == 0 or ring == COWL_RINGS:
            sectors = 1
        for sector in range(sectors):  # pragma: no branch
            var down = Float32(pi) * Float32(ring) / Float32(COWL_RINGS)
            var round = (
                2 * Float32(pi) * Float32(sector) / Float32(COWL_SECTORS)
            )
            # The pole looks forward, through the face, so the rings run
            # round the face's opening and the cut along it is smooth.
            var d = Vector3(
                hull.reach.x * sin(down) * cos(round),
                hull.reach.y * sin(down) * sin(round),
                hull.reach.z * cos(down),
            )
            d = d * (1 / max(d.length(), Float32(1e-12)))
            var p = hull.center + d * (hull.cast(d) + stand)
            var source = _nearest(points, p)
            var four = List[Int](length=4, fill=0)
            var share = List[Float32](length=4, fill=0)
            if source >= 0:
                for c in range(4):  # pragma: no branch
                    four[c] = Int(bones.component(source, c))
                    share[c] = weights.component(source, c)
            # Open at the face, and level at the bottom.
            var keep_here = p.y - floor
            if open_face:
                keep_here = min(keep_here, face_oval(rig, p))
            keep.append(keep_here)
            _ = writer.add(p, 1, four, share)
            lining.append(p - d * thickness)
            linings.append(four^)
            linings_weights.append(share^)
    # The lining: the same sphere, a thickness in, facing in.
    var count = len(lining)
    for k in range(count):  # pragma: no branch
        keep.append(keep[k])
        _ = writer.add(lining[k], 1, linings[k], linings_weights[k])
    for ring in range(COWL_RINGS):  # pragma: no branch
        for sector in range(COWL_SECTORS):  # pragma: no branch
            var a = _corner(ring, sector)
            var b = _corner(ring, sector + 1)
            var c = _corner(ring + 1, sector)
            var d = _corner(ring + 1, sector + 1)
            # Each quad is two triangles, wound to face out of a sphere
            # whose pole looks forward. At a pole one of them has two
            # corners on the pole, and is left out.
            if ring > 0:
                writer.triangle(a, c, b)
                writer.triangle(count + a, count + b, count + c)
            if ring < COWL_RINGS - 1:
                writer.triangle(b, c, d)
                writer.triangle(count + b, count + d, count + c)
    return cut(writer.build(), keep, 0)


def hang_cowl(
    piece: BufferGeometry,
    hulls: List[FootLast],
    rig: HumanoidRig,
    open_face: Bool,
    thickness: Float32,
) raises -> BufferGeometry:
    """Return a hood with its shell above the neck replaced by a cowl.

    Args:
        piece: The hood's shell, cut at its hems.
        hulls: Its hull, as `head_cowl` gives. With none the piece is
            returned as it is.
        rig: The rig it was made on.
        open_face: Whether to cut the cowl open at the face.
        thickness: How far inside the cowl its lining lies, in meters.

    Returns:
        The hood: its shell below the cut, and the cowl.

    Raises:
        Error: If the mesh has no positions or skin weights.
    """
    if len(hulls) == 0:
        return piece.clone()
    ref placed = piece.attribute_view(String(POSITION))
    var below = cowl_bottom(rig) - COWL_OVERLAP * skirt_scale(rig)
    var values = List[Float32](capacity=placed.count())
    for v in range(placed.count()):
        values.append(below - placed.vector3(v).y)
    var hood = cut(piece, values, 0)
    return merge(hood, cowl_mesh(hulls[0], piece, rig, open_face, thickness))
