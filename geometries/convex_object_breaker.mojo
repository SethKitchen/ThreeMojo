# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Convex objects cut by planes and broken by impacts, from three.js
`examples/jsm/misc/ConvexObjectBreaker.js`.

A `BreakableObject` is a convex geometry with a place and a turn, and the
mass, the velocities and the flag three.js keeps in its `userData`.
`ConvexObjectBreaker.cut_by_plane` cuts one in two: each side's points,
the corners on that side and the points where edges cross the plane,
become the convex hull of a new object at their mean. `subdivide_by_impact`
cuts one again and again about a point of impact, first round the impact
and then at random, into debris.

**What three.js does, kept.** A cut's pieces are placed at the mean of
their points in the object's frame, moved by the object's position and not
turned, as three.js places them. A piece's size is the largest single
coordinate of its points about the mean, not a distance. A piece of four
points or fewer is dropped. The test for two faces in one plane reads
three.js's normals at the vertex's index, not three times it, as
three.js's `n0.set( normals[ a1 ], normals[ a1 ] + 1, normals[ a1 ] + 2 )`
reads them; so it marks which edges to skip only where three.js marks
them.

**Where this differs.** A cut works in doubles, as three.js's does, and
keeps each piece's place in doubles while `position` is not moved. A
corner that lies within `small_delta` of a cut is on the knife's edge: the
last bit of a double decides its side. So a piece of a piece can differ
from three.js's by a corner, and its place by some centimeters. three.js's pieces are meshes; here they are
`BreakableObject`s, to add to a scene as the caller likes. The random
numbers come from a `SeededRandom`. three.js's `Math.random` is also drawn
by every new mesh and geometry for its uuid; here nothing else draws.
"""

from geometries.convex import convex
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from math.bounds import Plane
from math.quaternion import Quaternion
from math.utils import SeededRandom
from math.vector3 import Vector3
from std.benchmark import black_box
from std.math import cos, pi, sin, sqrt
from units.si import Angle, KILOGRAM, Length, METER, Mass, RADIAN


struct BreakableObject(Copyable, Movable):
    """A convex piece and how it moves, three.js's mesh and the `userData`
    of `prepareBreakableObject`."""

    # The convex surface, with `position` and `normal`, in the object's
    # frame.
    var geometry: BufferGeometry
    var position: Vector3
    var quaternion: Quaternion
    var mass: Mass
    # Meters a second, and radians a second about each axis.
    var velocity: Vector3
    var angular_velocity: Vector3
    # Whether it is big enough to break again.
    var breakable: Bool
    # Where a cut put it, in doubles, as three.js keeps a mesh's position.
    # Read in place of `position` while the two agree; see `_where`.
    var _exact: SIMD[DType.float64, 4]

    def __init__(
        out self,
        var geometry: BufferGeometry,
        position: Vector3,
        quaternion: Quaternion,
        mass: Mass,
        velocity: Vector3,
        angular_velocity: Vector3,
        breakable: Bool,
    ):
        """Create a piece, three.js's `prepareBreakableObject` on a mesh.

        Args:
            geometry: Its convex surface, with `position` and `normal`.
            position: Where it is.
            quaternion: How it is turned.
            mass: Its mass.
            velocity: How fast it moves.
            angular_velocity: How fast it turns.
            breakable: Whether it can break again.
        """
        self.geometry = geometry^
        self.position = position
        self.quaternion = quaternion
        self.mass = mass
        self.velocity = velocity
        self.angular_velocity = angular_velocity
        self.breakable = breakable
        self._exact = SIMD[DType.float64, 4](
            Float64(position.x), Float64(position.y), Float64(position.z), 0
        )

    def __init__(out self, *, copy: Self):
        """Copy a piece, its surface included."""
        self.geometry = copy.geometry.clone()
        self.position = copy.position
        self.quaternion = copy.quaternion
        self.mass = copy.mass
        self.velocity = copy.velocity
        self.angular_velocity = copy.angular_velocity
        self.breakable = copy.breakable
        self._exact = copy._exact


struct ConvexObjectBreaker(Movable):
    """Cuts and breaks convex objects, three.js's `ConvexObjectBreaker`."""

    # The smallest piece that can break again.
    var min_size_for_break: Length
    # How near a corner may be to a plane and count as on it, in meters,
    # and how near two faces' normals may be and count as one plane.
    var small_delta: Float32

    def __init__(
        out self,
        min_size_for_break: Length = Length(1.4, METER),
        small_delta: Float32 = 0.0001,
    ):
        """Create a breaker with three.js's defaults.

        Args:
            min_size_for_break: The smallest piece that can break again.
            small_delta: The tolerance of a cut.
        """
        self.min_size_for_break = min_size_for_break
        self.small_delta = small_delta

    def cut_by_plane(
        self, object: BreakableObject, plane: Plane
    ) raises -> Tuple[Optional[BreakableObject], Optional[BreakableObject]]:
        """Cut an object in two by a plane in the world, three.js's
        `cutByPlane`.

        Args:
            object: The object.
            plane: The plane, in the world.

        Returns:
            The piece behind the plane and the piece in front of it, each
            with half the mass. None for a side of four points or fewer.

        Raises:
            Error: If the object's geometry has no `position` or `normal`,
                or a piece's hull cannot be built.
        """
        var n = plane.normal
        return self._cut(
            object,
            _LocalPlane(
                _D(Float64(n.x), Float64(n.y), Float64(n.z), 0),
                Float64(plane.constant),
            ),
        )

    def _cut(
        self, object: BreakableObject, plane: _LocalPlane
    ) raises -> Tuple[Optional[BreakableObject], Optional[BreakableObject]]:
        """Cut an object by a plane in the world, given in doubles."""
        ref geometry = object.geometry
        ref coords = geometry.attribute_view(String(POSITION)).data
        ref normals = geometry.attribute_view(String(NORMAL)).data
        var point_count = len(coords) // 3
        var indexed = len(geometry.index) > 0
        var face_count = (
            len(geometry.index) // 3 if indexed else point_count // 3
        )
        var delta = self.small_delta
        var segments = List[Bool](length=point_count * point_count, fill=False)

        for i in range(face_count - 1):  # pragma: no branch
            var a1 = _vertex(geometry, indexed, i, 0)
            var b1 = _vertex(geometry, indexed, i, 1)
            var c1 = _vertex(geometry, indexed, i, 2)
            var n0 = _normal_of(normals, a1)
            for j in range(i + 1, face_count):  # pragma: no branch
                var a2 = _vertex(geometry, indexed, j, 0)
                var b2 = _vertex(geometry, indexed, j, 1)
                var c2 = _vertex(geometry, indexed, j, 2)
                var n1 = _normal_of(normals, a2)
                if not (1 - n0.dot(n1) < delta):
                    continue
                var a_shared = a1 == a2 or a1 == b2 or a1 == c2
                var b_shared = b1 == a2 or b1 == b2 or b1 == c2
                if a_shared:
                    if b_shared:
                        segments[a1 * point_count + b1] = True
                        segments[b1 * point_count + a1] = True
                    else:
                        segments[c1 * point_count + a1] = True
                        segments[a1 * point_count + c1] = True
                elif b_shared:
                    segments[c1 * point_count + b1] = True
                    segments[b1 * point_count + c1] = True

        var local = _local_plane(plane, object)
        var delta64 = Float64(delta)
        var points1 = List[_D]()
        var points2 = List[_D]()
        for i in range(face_count):  # pragma: no branch
            var corners: List[Int] = [
                _vertex(geometry, indexed, i, 0),
                _vertex(geometry, indexed, i, 1),
                _vertex(geometry, indexed, i, 2),
            ]
            for segment in range(3):  # pragma: no branch
                var i0 = corners[segment]
                var i1 = corners[(segment + 1) % 3]
                if segments[i0 * point_count + i1]:
                    continue
                segments[i0 * point_count + i1] = True
                segments[i1 * point_count + i0] = True
                var p0 = _corner(coords, i0)
                var p1 = _corner(coords, i1)
                var mark0 = _sort(local, p0, delta64, points1, points2)
                var mark1 = _sort(local, p1, delta64, points1, points2)
                if (mark0 == 1 and mark1 == 2) or (mark0 == 2 and mark1 == 1):
                    var crossing = _crossing(local, p0, p1)
                    points1.append(crossing)
                    points2.append(crossing)
        var half = Mass(object.mass.to(KILOGRAM) * 0.5, KILOGRAM)
        var first = self._piece(object, points1^, half)
        var second = self._piece(object, points2^, half)
        return (first^, second^)

    def _piece(
        self, object: BreakableObject, var points: List[_D], mass: Mass
    ) raises -> Optional[BreakableObject]:
        """Return the hull of one side's points about their mean, or None
        for four points or fewer."""
        var center = _D(0, 0, 0, 0)
        var radius = Float64(0)
        if len(points) > 0:
            for at in range(len(points)):  # pragma: no branch
                center = center + points[at]
            center = center / Float64(len(points))
            for at in range(len(points)):  # pragma: no branch
                points[at] = points[at] - center
                radius = max(
                    radius,
                    max(points[at][0], max(points[at][1], points[at][2])),
                )
            center = center + _where(object)
        if len(points) <= 4:
            return None
        var piece = BreakableObject(
            convex(points),
            Vector3(Float32(center[0]), Float32(center[1]), Float32(center[2])),
            object.quaternion,
            mass,
            object.velocity,
            object.angular_velocity,
            2 * radius > Float64(self.min_size_for_break.to(METER)),
        )
        piece._exact = center
        return piece^

    def subdivide_by_impact(
        self,
        object: BreakableObject,
        point_of_impact: Vector3,
        normal: Vector3,
        max_radial_iterations: Int,
        max_random_iterations: Int,
        mut random: SeededRandom,
    ) raises -> List[BreakableObject]:
        """Break an object into debris about a point of impact, three.js's
        `subdivideByImpact`.

        Each cut goes through the point of impact, first by the plane of
        the impact's normal and the object's center, then round the normal
        at random angles, and last, past `max_radial_iterations`, across
        each piece at random. A piece stops being cut when a random draw
        says so, more likely the more it has been cut, or past both counts.

        Args:
            object: The object.
            point_of_impact: Where it is struck, in the world.
            normal: The direction of the blow.
            max_radial_iterations: How many cuts go round the impact.
            max_random_iterations: How many more cuts go at random.
            random: Where the random numbers come from, in three.js's order.

        Returns:
            The debris.

        Raises:
            Error: If a cut fails.
        """
        var debris = List[BreakableObject]()
        var impact = _d(point_of_impact)
        var blow = _d(normal)
        var tip = impact + blow
        var center = _where(object)
        var context = _Impact(
            impact,
            blow,
            tip,
            center,
            _from_coplanar(impact, center, tip),
            max_radial_iterations,
            max_random_iterations + max_radial_iterations,
        )
        self._subdivide(context, object.copy(), 0, 2 * pi, 0, random, debris)
        return debris^

    def _subdivide(
        self,
        context: _Impact,
        var piece: BreakableObject,
        start_angle: Float64,
        end_angle: Float64,
        iterations: Int,
        mut random: SeededRandom,
        mut debris: List[BreakableObject],
    ) raises:
        """Cut a piece and its halves again, or keep it, three.js's
        `subdivideRadial`."""
        if (
            random.next() < Float64(iterations) * 0.05
            or iterations > context.max_total
        ):
            debris.append(piece^)
            return
        var angle = pi
        var cut = context.first_plane
        if iterations != 0:
            var here = _where(piece)
            if iterations <= context.max_radial:
                angle = (end_angle - start_angle) * (
                    0.2 + 0.6 * random.next()
                ) + start_angle
                var around = _about(
                    context.center - context.impact, context.normal, angle
                )
                cut = _from_coplanar(
                    context.impact, context.tip, around + context.impact
                )
            else:
                angle = (
                    0.5 * Float64(iterations & 1) + 0.2 * (2 - random.next())
                ) * pi
                var across = _about(
                    context.impact - here, context.normal, angle
                )
                cut = _from_coplanar(here, context.normal + here, across + here)
        var halves = self._cut(piece, cut)
        # Each cut runs through the piece: a radial one between the two
        # planes that bound its wedge, a random one through where it is.
        # So both halves hold something, and three.js's checks pass.
        if Bool(halves[0]):  # pragma: no branch
            self._subdivide(
                context,
                halves[0].value().copy(),
                start_angle,
                angle,
                iterations + 1,
                random,
                debris,
            )
        if Bool(halves[1]):  # pragma: no branch
            self._subdivide(
                context,
                halves[1].value().copy(),
                angle,
                end_angle,
                iterations + 1,
                random,
                debris,
            )


@fieldwise_init
struct _Impact(ImplicitlyCopyable):
    """What every cut of one impact shares, in doubles."""

    var impact: _D
    var normal: _D
    var tip: _D
    var center: _D
    var first_plane: _LocalPlane
    var max_radial: Int
    var max_total: Int


def _vertex(
    geometry: BufferGeometry, indexed: Bool, face: Int, corner: Int
) -> Int:
    """Return a face's corner as a vertex, three.js's `getVertexIndex`."""
    var at = face * 3 + corner
    return geometry.index[at] if indexed else at


def _normal_of(normals: List[Float32], at: Int) -> Vector3:
    """Return three.js's reading of a normal, kept: the index, not three
    times it."""
    return Vector3(normals[at], normals[at] + 1, normals[at] + 2)


# A point in doubles, as three.js computes a cut: x, y, z and an unused
# fourth.
comptime _D = SIMD[DType.float64, 4]


def _corner(coords: List[Float32], at: Int) -> _D:
    """Return one corner of a geometry, in doubles."""
    return _D(
        Float64(coords[3 * at]),
        Float64(coords[3 * at + 1]),
        Float64(coords[3 * at + 2]),
        0,
    )


def _mul(a: Float64, b: Float64) -> Float64:
    """Return a product rounded on its own, as JavaScript rounds it: never
    fused into a sum."""
    return black_box(a * b)


def _dot(a: _D, b: _D) -> Float64:
    """Return a dot product of the first three numbers, in three.js's
    order, each product rounded on its own."""
    return _mul(a[0], b[0]) + _mul(a[1], b[1]) + _mul(a[2], b[2])


@fieldwise_init
struct _LocalPlane(ImplicitlyCopyable):
    """A plane in an object's frame, in doubles, three.js's
    `tempPlane_Cut`."""

    var normal: _D
    var constant: Float64


def _sort(
    plane: _LocalPlane,
    point: _D,
    delta: Float64,
    mut behind: List[_D],
    mut front: List[_D],
) -> Int:
    """Put a corner on its side of a plane, or on both when it lies on it.

    Returns:
        Two in front, one behind, three on the plane: three.js's marks.
    """
    var distance = _dot(plane.normal, point) + plane.constant
    if distance > delta:
        front.append(point)
        return 2
    if distance < -delta:
        behind.append(point)
        return 1
    behind.append(point)
    front.append(point)
    return 3


def _crossing(plane: _LocalPlane, start: _D, end: _D) -> _D:
    """Return where an edge that crosses a plane meets it, three.js's
    `intersectLine`. The edge's ends lie on either side, so it meets."""
    var direction = end - start
    var t = -(_dot(start, plane.normal) + plane.constant) / _dot(
        plane.normal, direction
    )
    return _D(
        start[0] + _mul(direction[0], t),
        start[1] + _mul(direction[1], t),
        start[2] + _mul(direction[2], t),
        0,
    )


def _where(object: BreakableObject) -> _D:
    """Return where an object is, in doubles: where the cut that made it
    put it, unless `position` has been moved since."""
    var exact = object._exact
    var p = object.position
    if (
        Float32(exact[0]) == p.x
        and Float32(exact[1]) == p.y
        and Float32(exact[2]) == p.z
    ):
        return exact
    return _d(p)


def _d(v: Vector3) -> _D:
    """Return a vector in doubles."""
    return _D(Float64(v.x), Float64(v.y), Float64(v.z), 0)


def _cross(a: _D, b: _D) -> _D:
    """Return three.js's `crossVectors`, in doubles."""
    return _D(
        _mul(a[1], b[2]) - _mul(a[2], b[1]),
        _mul(a[2], b[0]) - _mul(a[0], b[2]),
        _mul(a[0], b[1]) - _mul(a[1], b[0]),
        0,
    )


def _unit(a: _D) -> _D:
    """Return three.js's `normalize`: the vector over its length, or itself
    when it has none."""
    var length = sqrt(_dot(a, a))
    return a / (length if length != 0 else 1.0)


def _from_coplanar(a: _D, b: _D, c: _D) -> _LocalPlane:
    """Return three.js's `setFromCoplanarPoints`, in doubles."""
    var normal = _unit(_cross(c - b, a - b))
    return _LocalPlane(normal, -_dot(a, normal))


def _about(v: _D, axis: _D, angle: Float64) -> _D:
    """Return three.js's `applyAxisAngle`: the quaternion of the turn,
    applied, in doubles."""
    var s = sin(angle / 2)
    var qx = axis[0] * s
    var qy = axis[1] * s
    var qz = axis[2] * s
    var qw = cos(angle / 2)
    var tx = 2 * (_mul(qy, v[2]) - _mul(qz, v[1]))
    var ty = 2 * (_mul(qz, v[0]) - _mul(qx, v[2]))
    var tz = 2 * (_mul(qx, v[1]) - _mul(qy, v[0]))
    return _D(
        v[0] + _mul(qw, tx) + _mul(qy, tz) - _mul(qz, ty),
        v[1] + _mul(qw, ty) + _mul(qz, tx) - _mul(qx, tz),
        v[2] + _mul(qw, tz) + _mul(qx, ty) - _mul(qy, tx),
        0,
    )


def _local_plane(plane: _LocalPlane, object: BreakableObject) -> _LocalPlane:
    """Return a plane in an object's frame, three.js's
    `transformPlaneToLocalSpace`: its turn undone, and its translation taken
    off after, as three.js takes it. The frame is three.js's `compose`, in
    doubles."""
    var anchor = _where(object)
    var q = object.quaternion
    var x = Float64(q.x)
    var y = Float64(q.y)
    var z = Float64(q.z)
    var w = Float64(q.w)
    var x2 = x + x
    var y2 = y + y
    var z2 = z + z
    var xx = x * x2
    var xy = x * y2
    var xz = x * z2
    var yy = y * y2
    var yz = y * z2
    var zz = z * z2
    var wx = w * x2
    var wy = w * y2
    var wz = w * z2
    var e: List[Float64] = [
        1 - (yy + zz),
        xy + wz,
        xz - wy,
        0,
        xy - wz,
        1 - (xx + zz),
        yz + wx,
        0,
        xz + wy,
        yz - wx,
        1 - (xx + yy),
        0,
        anchor[0],
        anchor[1],
        anchor[2],
        1,
    ]
    var p = plane.normal * -plane.constant
    var reference = _D(
        _mul(e[0], p[0]) + _mul(e[1], p[1]) + _mul(e[2], p[2]) - e[12],
        _mul(e[4], p[0]) + _mul(e[5], p[1]) + _mul(e[6], p[2]) - e[13],
        _mul(e[8], p[0]) + _mul(e[9], p[1]) + _mul(e[10], p[2]) - e[14],
        0,
    )
    var n = plane.normal
    var normal = _D(
        _mul(e[0], n[0]) + _mul(e[1], n[1]) + _mul(e[2], n[2]),
        _mul(e[4], n[0]) + _mul(e[5], n[1]) + _mul(e[6], n[2]),
        _mul(e[8], n[0]) + _mul(e[9], n[1]) + _mul(e[10], n[2]),
        0,
    )
    return _LocalPlane(normal, -_dot(reference, normal))
