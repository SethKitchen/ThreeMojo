# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Contacts between two shapes: the narrow phase.

Each test gives a list of contact points. A point has a position, a unit
normal from the first shape to the second, and a depth. A positive depth
is an overlap. A negative depth is a gap no wider than the margin: the
solver uses it to stop a fast body at the surface, not after it.

- Two round shapes, a sphere or a capsule, meet at the nearest points of
  their segments, from `Line3.closest_points_to_line`.
- A round shape and a polyhedron meet at the minimum of the polyhedron's
  signed distance along the segment. The signed distance of a convex
  solid is a convex function, so a golden-section search finds it. Each
  end of a capsule is tested as well, so a capsule lying on a face rests
  on two points.
- Two polyhedra use the separating-axis test of Dirk Gregorius, "The
  Separating Axis Test between Convex Polyhedra" (GDC 2013): the face
  normals of each, then the cross products of their edges. A face contact
  clips the incident face against the sides of the reference face
  (Sutherland-Hodgman), which gives up to eight points. An edge contact
  gives the nearest points of the two edges.
- A triangle of a static mesh is a polyhedron with one face. A round
  shape against a triangle uses `triangle_sphere_intersect` and
  `triangle_capsule_intersect` from `math.octree`.
"""

from extensions.carla.physics.shape import (
    Polyhedron,
    cross,
    unit_or,
)
from math.bounds import Sphere
from math.capsule import Capsule
from math.octree import triangle_capsule_intersect, triangle_sphere_intersect
from math.triangle import Line3, Triangle
from math.vector3 import Vector3
from std.math import inf, sqrt

# A face contact beats a better edge contact unless the edge is better by
# this ratio and this distance. Gregorius's tolerances.
comptime _EDGE_RATIO = Float32(0.9)
comptime _EDGE_SLACK = Float32(0.005)
comptime _FACE_RATIO = Float32(0.98)
comptime _FACE_SLACK = Float32(0.001)
comptime _GOLDEN = Float32(0.6180339887)


@fieldwise_init
struct ContactPoint(ImplicitlyCopyable):
    """Where two shapes touch."""

    # Halfway between the two surfaces, in meters.
    var point: Vector3
    # The unit normal, from the first shape to the second.
    var normal: Vector3
    # The overlap, in meters. Negative for a gap.
    var depth: Float32


struct WorldShape(Copyable, Movable):
    """A shape placed in the world, in the form the tests read."""

    var kind: Int
    # The segment of a round shape. A sphere has both ends at its center.
    var start: Vector3
    var end: Vector3
    var radius: Float32
    # The corners, faces and edges of a box or a hull.
    var polyhedron: Polyhedron

    @staticmethod
    def round(start: Vector3, end: Vector3, radius: Float32) -> WorldShape:
        """Return a sphere or a capsule.

        Args:
            start: One end of the segment.
            end: The other end. The same point for a sphere.
            radius: The radius, in meters.

        Returns:
            The shape.
        """
        return WorldShape(0, start, end, radius, Polyhedron())

    @staticmethod
    def solid(var polyhedron: Polyhedron) -> WorldShape:
        """Return a box or a hull.

        Args:
            polyhedron: The solid, in the world.

        Returns:
            The shape.
        """
        return WorldShape(1, Vector3(0, 0, 0), Vector3(0, 0, 0), 0, polyhedron^)

    def __init__(
        out self,
        kind: Int,
        start: Vector3,
        end: Vector3,
        radius: Float32,
        var polyhedron: Polyhedron,
    ):
        """Create a shape. Use `round` or `solid`.

        Args:
            kind: 0 for a round shape, 1 for a polyhedron.
            start: One end of the segment.
            end: The other end.
            radius: The radius.
            polyhedron: The solid.
        """
        self.kind = kind
        self.start = start
        self.end = end
        self.radius = radius
        self.polyhedron = polyhedron^

    def is_round(self) -> Bool:
        """Return True for a sphere or a capsule.

        Returns:
            Whether the shape is a segment with a radius.
        """
        return self.kind == 0


def flipped(points: List[ContactPoint]) -> List[ContactPoint]:
    """Return contacts with each normal turned around.

    Args:
        points: The contacts.

    Returns:
        The same points, with the normals from the second shape to the
        first.
    """
    var out = List[ContactPoint]()
    for p in points:
        out.append(ContactPoint(p.point, -p.normal, p.depth))
    return out^


def collide(
    a: WorldShape, b: WorldShape, margin: Float32
) -> List[ContactPoint]:
    """Return the contacts of two shapes.

    Args:
        a: The first shape.
        b: The second shape.
        margin: The widest gap that still gives a contact, in meters.

    Returns:
        The contacts, with normals from `a` to `b`. Empty if they are
        apart by more than the margin.
    """
    if a.is_round() and b.is_round():
        return round_round(a, b, margin)
    if a.is_round():
        return flipped(round_polyhedron(a, b.polyhedron, margin))
    if b.is_round():
        return round_polyhedron(b, a.polyhedron, margin)
    return polyhedron_polyhedron(a.polyhedron, b.polyhedron, margin)


def round_round(
    a: WorldShape, b: WorldShape, margin: Float32
) -> List[ContactPoint]:
    """Return the contact of two spheres or capsules.

    Args:
        a: The first shape.
        b: The second shape.
        margin: The widest gap that still gives a contact.

    Returns:
        One contact, or none.
    """
    var on_a = Vector3(0, 0, 0)
    var on_b = Vector3(0, 0, 0)
    _ = Line3(a.start, a.end).closest_points_to_line(
        Line3(b.start, b.end), on_a, on_b
    )
    var out = List[ContactPoint]()
    var gap = (on_b - on_a).length()
    var depth = a.radius + b.radius - gap
    if depth < -margin:
        return out^
    var normal = unit_or(on_b - on_a, Vector3(0, 0, 1))
    var point = (on_a + normal * a.radius + on_b - normal * b.radius) * 0.5
    out.append(ContactPoint(point, normal, depth))
    return out^


@fieldwise_init
struct SignedDistance(ImplicitlyCopyable):
    """How far a point is from a solid, and which way is out."""

    # Negative inside, in meters.
    var distance: Float32
    # The nearest point of the surface.
    var surface: Vector3
    # The unit direction from the surface to the point, or the outward
    # normal of the nearest face for a point inside.
    var normal: Vector3


def signed_distance(poly: Polyhedron, x: Vector3) -> SignedDistance:
    """Return the signed distance of a point from a convex solid.

    Args:
        poly: The solid.
        x: The point.

    Returns:
        The distance, the nearest surface point and the outward direction.
    """
    var best = -inf[DType.float32]()
    var face = 0
    # A polyhedron has one face at least.
    for f in range(poly.face_count()):  # pragma: no branch
        var s = poly.normals[f].dot(x) - poly.offsets[f]
        if s > best:
            best = s
            face = f
    if best <= 0:
        return SignedDistance(
            best, x - poly.normals[face] * best, poly.normals[face]
        )
    var nearest = x
    var gap = inf[DType.float32]()
    for f in range(poly.face_count()):  # pragma: no branch
        if poly.normals[f].dot(x) - poly.offsets[f] <= 0:
            continue
        var first = poly.face_corners[poly.face_start[f]]
        # A face has three corners at least: one triangle of the fan.
        for k in range(
            poly.face_start[f] + 1, poly.face_start[f + 1] - 1
        ):  # pragma: no branch
            var q = Triangle(
                poly.vertices[first],
                poly.vertices[poly.face_corners[k]],
                poly.vertices[poly.face_corners[k + 1]],
            ).closest_point_to_point(x)
            var d = (x - q).length()
            if d < gap:
                gap = d
                nearest = q
    return SignedDistance(
        gap, nearest, unit_or(x - nearest, poly.normals[face])
    )


def _point_contact(
    x: Vector3, radius: Float32, poly: Polyhedron, margin: Float32
) -> List[ContactPoint]:
    """Return the contact of a sphere and a polyhedron, normal from the
    polyhedron to the sphere."""
    var out = List[ContactPoint]()
    var sd = signed_distance(poly, x)
    var depth = radius - sd.distance
    if depth < -margin:
        return out^
    var point = (sd.surface + x - sd.normal * radius) * 0.5
    out.append(ContactPoint(point, sd.normal, depth))
    return out^


def round_polyhedron(
    round: WorldShape, poly: Polyhedron, margin: Float32
) -> List[ContactPoint]:
    """Return the contacts of a sphere or capsule and a polyhedron.

    Args:
        round: The sphere or capsule.
        poly: The polyhedron.
        margin: The widest gap that still gives a contact.

    Returns:
        The contacts, with normals from the polyhedron to the round shape.
    """
    var out = _point_contact(round.start, round.radius, poly, margin)
    if round.start == round.end:
        return out^
    out.extend(_point_contact(round.end, round.radius, poly, margin))
    # Golden-section search for the deepest point of the segment.
    var low = Float32(0)
    var high = Float32(1)
    var axis = round.end - round.start
    for _ in range(24):  # pragma: no branch
        var m1 = high - (high - low) * _GOLDEN
        var m2 = low + (high - low) * _GOLDEN
        var d1 = signed_distance(poly, round.start + axis * m1).distance
        var d2 = signed_distance(poly, round.start + axis * m2).distance
        if d1 < d2:
            high = m2
        else:
            low = m1
    var t = (low + high) * 0.5
    if t > 0.05 and t < 0.95:
        out.extend(
            _point_contact(round.start + axis * t, round.radius, poly, margin)
        )
    return out^


def _projection_range(
    poly: Polyhedron, axis: Vector3
) -> Tuple[Float32, Float32]:
    var low = poly.vertices[0].dot(axis)
    var high = low
    # A polyhedron has three corners at least.
    for i in range(1, len(poly.vertices)):  # pragma: no branch
        var p = poly.vertices[i].dot(axis)
        low = min(low, p)
        high = max(high, p)
    return (low, high)


@fieldwise_init
struct _Axis(ImplicitlyCopyable):
    var separation: Float32
    var index: Int
    var normal: Vector3


def _face_axis(a: Polyhedron, b: Polyhedron) -> _Axis:
    """Return the face of `a` that best separates `b`."""
    var best = _Axis(-inf[DType.float32](), 0, Vector3(0, 0, 1))
    # A polyhedron has one face at least.
    for f in range(a.face_count()):  # pragma: no branch
        var s = -b.support(-a.normals[f]) - a.offsets[f]
        if s > best.separation:
            best = _Axis(s, f, a.normals[f])
    return best


def _edge_axis(a: Polyhedron, b: Polyhedron) -> _Axis:
    """Return the cross product of two edges that best separates the two,
    pointing from `a` to `b`."""
    var best = _Axis(-inf[DType.float32](), -1, Vector3(0, 0, 1))
    var toward = b.center() - a.center()
    # A polyhedron has three edges at least.
    for i in range(len(a.edge_a)):  # pragma: no branch
        var da = a.vertices[a.edge_b[i]] - a.vertices[a.edge_a[i]]
        for j in range(len(b.edge_a)):  # pragma: no branch
            var db = b.vertices[b.edge_b[j]] - b.vertices[b.edge_a[j]]
            var axis = cross(da, db)
            var length = axis.length()
            if length < 1e-6 * da.length() * db.length():
                continue
            axis = axis / length
            if axis.dot(toward) < 0:
                axis = -axis
            var s = (
                _projection_range(b, axis)[0] - _projection_range(a, axis)[1]
            )
            if s > best.separation:
                best = _Axis(s, i, axis)
    return best


def polyhedron_polyhedron(
    a: Polyhedron, b: Polyhedron, margin: Float32
) -> List[ContactPoint]:
    """Return the contacts of two convex polyhedra.

    Args:
        a: The first solid.
        b: The second solid.
        margin: The widest gap that still gives a contact.

    Returns:
        Up to eight contacts, with normals from `a` to `b`.
    """
    var out = List[ContactPoint]()
    var face_a = _face_axis(a, b)
    if face_a.separation > margin:
        return out^
    var face_b = _face_axis(b, a)
    if face_b.separation > margin:
        return out^
    var edge = _edge_axis(a, b)
    if edge.separation > margin:
        return out^
    var face_best = max(face_a.separation, face_b.separation)
    if edge.separation > _EDGE_RATIO * face_best + _EDGE_SLACK:
        out.append(_edge_contact(a, b, edge))
        return out^
    if face_b.separation > _FACE_RATIO * face_a.separation + _FACE_SLACK:
        return flipped(face_contact(b, face_b.index, a, margin))
    return face_contact(a, face_a.index, b, margin)


def _supporting(poly: Polyhedron, axis: Vector3) -> List[Int]:
    """Return the corners that reach farthest along an axis."""
    var top = poly.support(axis)
    var out = List[Int]()
    for i in range(len(poly.vertices)):  # pragma: no branch
        if poly.vertices[i].dot(axis) > top - 1e-4:
            out.append(i)
    return out^


def _edge_contact(a: Polyhedron, b: Polyhedron, edge: _Axis) -> ContactPoint:
    """Return the contact of an edge of `a` and an edge of `b`: the nearest
    points of the features that reach farthest toward each other."""
    var on_a = _supporting(a, edge.normal)
    var on_b = _supporting(b, -edge.normal)
    var pa = Vector3(0, 0, 0)
    var pb = Vector3(0, 0, 0)
    _ = Line3(
        a.vertices[on_a[0]], a.vertices[on_a[len(on_a) - 1]]
    ).closest_points_to_line(
        Line3(b.vertices[on_b[0]], b.vertices[on_b[len(on_b) - 1]]), pa, pb
    )
    return ContactPoint((pa + pb) * 0.5, edge.normal, -edge.separation)


def clip_polygon(
    points: List[Vector3], normal: Vector3, offset: Float32
) -> List[Vector3]:
    """Keep the part of a convex polygon on one side of a plane, one step
    of Sutherland-Hodgman.

    Args:
        points: The polygon's corners, in order. It can be empty.
        normal: The plane's normal.
        offset: The plane is `normal . x = offset`.

    Returns:
        The corners where `normal . x <= offset`, with a new corner where
        each edge crosses the plane.
    """
    var out = List[Vector3]()
    for i in range(len(points)):
        var p = points[i]
        var q = points[(i + 1) % len(points)]
        var dp = normal.dot(p) - offset
        var dq = normal.dot(q) - offset
        if dp <= 0:
            out.append(p)
        if (dp <= 0) != (dq <= 0):
            out.append(p + (q - p) * (dp / (dp - dq)))
    return out^


def face_contact(
    reference: Polyhedron, face: Int, incident: Polyhedron, margin: Float32
) -> List[ContactPoint]:
    """Return the contacts of one face of a solid and the face of another
    that faces it most.

    The incident face is clipped against the sides of the reference face.
    Each corner left within the margin of the reference face is a
    contact, up to eight.

    Args:
        reference: The solid whose face is the reference.
        face: Which face of `reference`.
        incident: The other solid.
        margin: The widest gap that still gives a contact.

    Returns:
        The contacts, with the reference face's normal. Empty if the clip
        leaves nothing.
    """
    var n = reference.normals[face]
    var d = reference.offsets[face]
    var facing = 0
    var most = inf[DType.float32]()
    # A polyhedron has one face at least.
    for f in range(incident.face_count()):  # pragma: no branch
        var c = incident.normals[f].dot(n)
        if c < most:
            most = c
            facing = f
    var polygon = List[Vector3]()
    # A face has three corners at least.
    for k in range(
        incident.face_start[facing], incident.face_start[facing + 1]
    ):  # pragma: no branch
        polygon.append(incident.vertices[incident.face_corners[k]])
    var first = reference.face_start[face]
    var count = reference.face_start[face + 1] - first
    for i in range(count):  # pragma: no branch
        var p = reference.vertices[reference.face_corners[first + i]]
        var q = reference.vertices[
            reference.face_corners[first + (i + 1) % count]
        ]
        var side = unit_or(cross(q - p, n), n)
        polygon = clip_polygon(polygon, side, side.dot(p))
    var out = List[ContactPoint]()
    for p in polygon:
        var s = n.dot(p) - d
        if s <= margin and len(out) < 8:
            out.append(ContactPoint(p - n * (s * 0.5), n, -s))
    return out^


def mesh_contacts(
    triangle: Triangle, shape: WorldShape, margin: Float32
) raises -> List[ContactPoint]:
    """Return the contacts of one triangle of a static mesh and a shape.

    A triangle is solid only from its front. A shape whose middle is
    behind it does not touch it.

    Args:
        triangle: The triangle. Its front is where (b - a) x (c - a)
            points.
        shape: The moving shape.
        margin: The widest gap that still gives a contact.

    Returns:
        The contacts, with normals from the triangle to the shape.

    Raises:
        Error: If the shape's radius is negative.
    """
    var out = List[ContactPoint]()
    if not shape.is_round():
        var face = Polyhedron.triangle(triangle)
        if face.normals[0].dot(shape.polyhedron.center()) < face.offsets[0]:
            return out^
        return polyhedron_polyhedron(face, shape.polyhedron, margin)
    var reach = shape.radius + margin
    if shape.start == shape.end:
        var hit = triangle_sphere_intersect(
            Sphere(shape.start, reach), triangle
        )
        if Bool(hit):
            var c = hit.value()
            out.append(ContactPoint(c.point, c.normal, c.depth - margin))
        return out^
    var hit = triangle_capsule_intersect(
        Capsule(shape.start, shape.end, reach), triangle
    )
    if Bool(hit):
        var c = hit.value()
        out.append(ContactPoint(c.point, c.normal, c.depth - margin))
    return out^
