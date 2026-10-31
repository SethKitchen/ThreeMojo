# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A boot's last: each foot closed in one smooth, convex shape.

A garment made from the skin follows each toe, as a sock does. A boot
does not: its toe box spans the toes, and its sole spans the arch, as the
last it was made on does. `shoe` replaces the part of a boot's shell
below the ankles with, for each foot, a mesh laid on the convex hull of
the shell there:

1. `last_top` is a little above the ankle joints. The shell is cut a
   little below it, so its edge lies inside the last.
2. `foot_lasts` closes the shell's vertices below the top on each side of
   the body in their convex hull, with the points where the shell crosses
   the top, so the hull reaches up to it.
3. A sphere of `LAST_RINGS` rings and `LAST_SECTORS` sectors, stretched to
   the foot's box, is cast from the middle of the foot onto the hull. So
   the last is evenly meshed, even where the hull has long facets over
   the toes and the arch.
4. The last stands `LAST_STAND` out of the hull, so the seam where the
   shaft meets it is a clean step, as a boot's welt is. The flat top of
   the hull lies inside the shaft, and is left out.
5. Each vertex takes the skin weights of the nearest vertex of the shell,
   so the toe box bends with the toes.

This is not a three.js port. See Extensions.

    var lasts = foot_lasts(whole, rig)
    var boot = shoe(piece, lasts, rig)
"""

from std.math import cos, pi, sin, sqrt

from core.buffer_geometry import POSITION, BufferGeometry
from extensions.attire.mesh_ops import MeshWriter, cut, merge
from extensions.attire.skirt import leg_side, skirt_scale, slice_segments
from extensions.humanoid.rig.joints import (
    HIPS,
    LEFT_FOOT,
    RIGHT_FOOT,
    HumanoidRig,
)
from math.convex_hull import ConvexHull
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT

comptime LAST_RISE = Float32(0.02)
"""How far above the ankle joints a last reaches, in meters on the
template."""
comptime LAST_OVERLAP = Float32(0.02)
"""How far below a last's top the shell is cut, in meters on the
template, so the shell's edge lies inside the last."""
comptime LAST_RINGS = 12
"""The rings of the sphere a last is cast from, pole to pole."""
comptime LAST_SECTORS = 18
"""The sectors of the sphere a last is cast from, round its axis."""
comptime LAST_STAND = Float32(0.0015)
"""How far a last stands out of the hull, in meters, so the shell's edge
lies inside it and the seam between them is a clean step."""
comptime LAST_CAP = Float32(0.003)
"""How far below its top a last is cut level, in meters, so its flat top
is left out."""


struct FootLast(Copyable, Movable):
    """One foot's last: the planes of a convex hull round the shell."""

    var center: Vector3
    """A point inside the hull: the mean of the points it closes."""
    var reach: Vector3
    """Half the size of the points' box, on each axis."""
    var top: Float32
    """The height of the highest point."""
    var normals: List[Vector3]
    """The outward unit normal of each face of the hull."""
    var offsets: List[Float32]
    """How far each face's plane lies from the center along its normal."""

    def __init__(out self, center: Vector3, reach: Vector3, top: Float32):
        """Hold a hull with no faces yet.

        Args:
            center: A point inside the hull.
            reach: Half the size of the points' box.
            top: The height of the highest point.
        """
        self.center = center
        self.reach = reach
        self.top = top
        self.normals = List[Vector3]()
        self.offsets = List[Float32]()

    def cast(self, direction: Vector3) -> Float32:
        """Return how far from the center a ray leaves the hull.

        Args:
            direction: A unit direction.

        Returns:
            The distance along the ray to the nearest face it meets on
            its way out, or zero for a hull with no faces.
        """
        var nearest = Float32(0)
        var found = False
        for k in range(len(self.normals)):
            var facing = self.normals[k].dot(direction)
            if facing <= 0:
                continue
            var along = self.offsets[k] / facing
            if not found or along < nearest:
                nearest = along
                found = True
        return nearest

    def cast_from(self, origin: Vector3, direction: Vector3) -> Float32:
        """Return how far from a point inside the hull a ray leaves it.

        Args:
            origin: A point inside the hull.
            direction: A unit direction.

        Returns:
            The distance along the ray to the nearest face it meets on
            its way out, or zero for a hull with no faces or a point
            outside it.
        """
        var nearest = Float32(0)
        var found = False
        var from_center = origin - self.center
        for k in range(len(self.normals)):
            var facing = self.normals[k].dot(direction)
            if facing <= 0:
                continue
            var along = (
                self.offsets[k] - self.normals[k].dot(from_center)
            ) / facing
            if not found or along < nearest:
                nearest = along
                found = True
        return max(Float32(0), nearest)


def last_top(rig: HumanoidRig) -> Float32:
    """Return the height a last reaches.

    Args:
        rig: The rig the boot was made on.

    Returns:
        `LAST_RISE` over the higher ankle joint, scaled to the stature.
    """
    var ankle = max(
        rig.joints[RIGHT_FOOT.value].y, rig.joints[LEFT_FOOT.value].y
    )
    return ankle + LAST_RISE * skirt_scale(rig)


def foot_points(
    piece: BufferGeometry, rig: HumanoidRig, right: Bool
) raises -> List[Vector3]:
    """Return the vertices of a shell below the last's top on one side.

    Args:
        piece: A garment's shell.
        rig: The rig it was made on.
        right: Whether to take the right foot's side, or the left's.

    Returns:
        The positions of the trunk and leg vertices below `last_top` on
        that side of the hips, and of the points where the shell crosses
        `last_top` there, so a last reaches up to it. With no vertex below
        the top on that side, none.

    Raises:
        Error: If the mesh has no positions or skin weights.
    """
    var legs = leg_side(piece)
    ref placed = piece.attribute_view(String(POSITION))
    var top = last_top(rig)
    var middle = rig.joints[HIPS.value].x
    var side = rig.joints[RIGHT_FOOT.value].x - middle
    if not right:
        side = rig.joints[LEFT_FOOT.value].x - middle
    var points = List[Vector3]()
    for v in range(placed.count()):
        var p = placed.vector3(v)
        if legs[v] and p.y < top and (p.x - middle) * side > 0:
            points.append(p)
    if len(points) > 0:
        for p in slice_segments(piece, legs, top):
            if (p.x - middle) * side > 0:
                points.append(p)
    return points^


def foot_last(points: List[Vector3]) raises -> FootLast:
    """Return the last that closes some points.

    Args:
        points: Four points or more, not all in one plane.

    Returns:
        The last: their convex hull's planes round their mean.

    Raises:
        Error: If there are fewer than four points, or they all lie in one
            plane.
    """
    var hull = ConvexHull(points)
    var low = points[0]
    var high = points[0]
    var sum = Vector3(0, 0, 0)
    for p in points:  # pragma: no branch
        low = Vector3(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
        high = Vector3(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
        sum = sum + p
    var center = sum * (1 / Float32(len(points)))
    var last = FootLast(center, (high - low) * 0.5, high.y)
    for face in range(hull.face_count()):  # pragma: no branch
        var n = hull.face_normal(face)
        var corner = points[hull.face_vertex(face, 0)]
        last.normals.append(n)
        last.offsets.append(n.dot(corner - center))
    return last^


def foot_lasts(
    whole: BufferGeometry, rig: HumanoidRig
) raises -> List[FootLast]:
    """Return the lasts of a boot's two feet.

    Args:
        whole: The boot's whole shell, cut at its hems, with nothing
            hidden, in the pelvis frame.
        rig: The rig it was made on.

    Returns:
        A last for each foot whose side holds four points or more, the
        right foot's first.

    Raises:
        Error: If the mesh has no positions or skin weights, or a foot's
            points all lie in one plane.
    """
    var lasts = List[FootLast]()
    for right in [True, False]:  # pragma: no branch
        var points = foot_points(whole, rig, right)
        if len(points) >= 4:
            lasts.append(foot_last(points))
    return lasts^


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


def _direction(last: FootLast, ring: Int, sector: Int) -> Vector3:
    """Return the unit direction of one vertex of the stretched sphere."""
    var down = Float32(pi) * Float32(ring) / Float32(LAST_RINGS)
    var round = 2 * Float32(pi) * Float32(sector) / Float32(LAST_SECTORS)
    var d = Vector3(
        last.reach.x * sin(down) * cos(round),
        last.reach.y * cos(down),
        last.reach.z * sin(down) * sin(round),
    )
    # The box of four points or more has some size: the length is not
    # zero.
    return d * (1 / max(d.length(), Float32(1e-12)))


def _corner(ring: Int, sector: Int) -> Int:
    """Return the vertex of the stretched sphere at a ring and a sector.

    A pole is one vertex. The sectors wrap round.
    """
    if ring == 0:
        return 0
    if ring == LAST_RINGS:
        return 1 + (LAST_RINGS - 1) * LAST_SECTORS
    return 1 + (ring - 1) * LAST_SECTORS + sector % LAST_SECTORS


def last_mesh(last: FootLast, piece: BufferGeometry) raises -> BufferGeometry:
    """Return the mesh of one last.

    Args:
        last: The last.
        piece: The garment's shell, whose attributes the last takes and
            whose nearest vertex gives each of its vertices its weights.

    Returns:
        The last, with the garment's attributes and normals.

    Raises:
        Error: If the mesh has no positions or skin weights.
    """
    ref placed = piece.attribute_view(String(POSITION))
    ref bones = piece.attribute_view(String(SKIN_INDEX))
    ref weights = piece.attribute_view(String(SKIN_WEIGHT))
    var points = List[Vector3](capacity=placed.count())
    for v in range(placed.count()):
        points.append(placed.vector3(v))
    var writer = MeshWriter(piece)
    var at = List[Int]()
    var heights = List[Float32]()
    for ring in range(LAST_RINGS + 1):  # pragma: no branch
        var sectors = LAST_SECTORS
        if ring == 0 or ring == LAST_RINGS:
            sectors = 1
        for sector in range(sectors):  # pragma: no branch
            var direction = _direction(last, ring, sector)
            var p = last.center + direction * (
                last.cast(direction) + LAST_STAND
            )
            var source = _nearest(points, p)
            var four = List[Int](length=4, fill=0)
            var share = List[Float32](length=4, fill=0)
            if source >= 0:
                for c in range(4):  # pragma: no branch
                    four[c] = Int(bones.component(source, c))
                    share[c] = weights.component(source, c)
            at.append(writer.add(p, 1, four, share))
            heights.append(p.y)
    for ring in range(LAST_RINGS):  # pragma: no branch
        for sector in range(LAST_SECTORS):  # pragma: no branch
            var a = _corner(ring, sector)
            var b = _corner(ring, sector + 1)
            var c = _corner(ring + 1, sector)
            var d = _corner(ring + 1, sector + 1)
            # Each quad is two triangles. At a pole one of them has two
            # corners on the pole, and is left out.
            if ring > 0:
                writer.triangle(at[a], at[b], at[c])
            if ring < LAST_RINGS - 1:
                writer.triangle(at[b], at[d], at[c])
    # The flat top lies inside the shaft. Cut it off along a level, so the
    # last's rim is straight.
    var mesh = writer.build()
    var rim = last.top - LAST_CAP
    var below = List[Float32](capacity=len(heights))
    for y in heights:  # pragma: no branch
        below.append(rim - y)
    return cut(mesh, below, 0)


def shoe(
    piece: BufferGeometry, lasts: List[FootLast], rig: HumanoidRig
) raises -> BufferGeometry:
    """Return a boot with its shell below the ankles replaced by lasts.

    Args:
        piece: The boot's shell, cut at its hems.
        lasts: Its lasts, as `foot_lasts` gives. With none the piece is
            returned as it is.
        rig: The rig it was made on.

    Returns:
        The boot: its shell above the cut, and each last.

    Raises:
        Error: If the mesh has no positions or skin weights.
    """
    if len(lasts) == 0:
        return piece.clone()
    var legs = leg_side(piece)
    ref placed = piece.attribute_view(String(POSITION))
    var below = last_top(rig) - LAST_OVERLAP * skirt_scale(rig)
    var values = List[Float32](capacity=placed.count())
    for v in range(placed.count()):
        var value = Float32(1)
        if legs[v]:
            value = placed.vector3(v).y - below
        values.append(value)
    var boot = cut(piece, values, 0)
    for last in lasts:  # pragma: no branch
        boot = merge(boot, last_mesh(last, piece))
    return boot^
