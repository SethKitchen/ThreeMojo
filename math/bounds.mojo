# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A box, a sphere and a plane, from three.js `src/math/Box3.js`,
`src/math/Sphere.js` and `src/math/Plane.js`.

The three shapes a renderer asks questions of rather than draws: does this
mesh lie inside the view, which mesh did the click land on, which side of
the near plane is this corner. A box and a sphere are *bounds*: shapes that
enclose a set of points, cheap to test and to carry through a transform. A
plane is the thing a frustum is six of.

All three hold bare `Float32` meters, as `Vector3` does, because they are
made of `Vector3`s and are compared with them. The quantities with units
live at the API's edges -- a geometry builder takes a `Length` -- and the
math in the middle is plain numbers, which is also where the GPU reads it.

An *empty* bound is one that holds no points at all, and it is a value
rather than an error, as in three.js: a box whose corners are inside out on
any axis, a sphere with a negative radius. Every operation treats it as the
set it is. Expanding it by a point gives the bound of that one point, which
is what lets a bound be built from any number of points, including none,
without a special first step; a union with it changes nothing; it overlaps
nothing; a transform leaves it empty. A question that needs a point of it,
the nearest point or a distance, has no answer and is refused.

Both transforms take an affine matrix, one that keeps `w` at one. A
projection is refused: a corner crossing `w = 0` has no finite image, and
carrying corners across is no way to bound what it does.

A plane is stored as a unit normal and a constant, so a point's signed
distance is one dot product and an add. The constructor normalizes both,
because every question a plane answers assumes the normal is unit and a
plane built from three points has no reason to have one. A zero normal is
refused: it is not a plane.
"""

from math.matrix3 import Matrix3
from math.matrix4 import Matrix4
from math.triangle import Line3, Triangle
from math.vector3 import Vector3
from std.math import inf, sqrt


@fieldwise_init
struct Box3(Equatable, ImplicitlyCopyable):
    """An axis-aligned box: its smallest and largest corner."""

    var min: Vector3
    var max: Vector3

    @staticmethod
    def empty() -> Box3:
        """Return the box that holds no points.

        Its corners are inside out, the smallest at plus infinity and the
        largest at minus, so that the first point expanded into it becomes
        both corners: every comparison an expansion makes goes the point's
        way.

        Returns:
            The empty box.
        """
        var far = inf[DType.float32]()
        return Box3(Vector3(far, far, far), Vector3(-far, -far, -far))

    @staticmethod
    def from_points(points: List[Vector3]) -> Box3:
        """Return the smallest box around every point given.

        Args:
            points: Any number of points, including none.

        Returns:
            Their box, or the empty box for no points.
        """
        var box = Box3.empty()
        for index in range(len(points)):
            box.expand_by_point(points[index])
        return box

    def is_empty(self) -> Bool:
        """Return True if this box holds no points: a corner is inside out
        on some axis. A box of one point is not empty."""
        return (
            self.max.x < self.min.x
            or self.max.y < self.min.y
            or self.max.z < self.min.z
        )

    def expand_by_point(mut self, point: Vector3):
        """Grow this box to hold `point` as well. An empty box becomes the
        box of that one point, whatever its inside-out corners held.

        Args:
            point: The point to take in.
        """
        if self.is_empty():
            self.min = point
            self.max = point
            return
        self.min = Vector3(
            min(self.min.x, point.x),
            min(self.min.y, point.y),
            min(self.min.z, point.z),
        )
        self.max = Vector3(
            max(self.max.x, point.x),
            max(self.max.y, point.y),
            max(self.max.z, point.z),
        )

    def union(mut self, other: Box3):
        """Grow this box to hold everything `other` holds, three.js's
        `union`.

        The smaller of the two smallest corners and the larger of the two
        largest. An empty box holds nothing to take in, so taking one in
        changes nothing, and an empty box that takes one in becomes it --
        asked outright rather than left to the arithmetic, which a finite
        inside-out corner would fool.

        Args:
            other: The box to take in.
        """
        if other.is_empty():
            return
        if self.is_empty():
            self = other
            return
        self.min = Vector3(
            min(self.min.x, other.min.x),
            min(self.min.y, other.min.y),
            min(self.min.z, other.min.z),
        )
        self.max = Vector3(
            max(self.max.x, other.max.x),
            max(self.max.y, other.max.y),
            max(self.max.z, other.max.z),
        )

    def center(self) -> Vector3:
        """Return the middle of this box, or the origin for an empty one."""
        if self.is_empty():
            return Vector3(0, 0, 0)
        return (self.min + self.max) * 0.5

    def size(self) -> Vector3:
        """Return this box's extent along each axis, or zero for an empty
        one."""
        if self.is_empty():
            return Vector3(0, 0, 0)
        return self.max - self.min

    def contains_point(self, point: Vector3) -> Bool:
        """Return True if `point` lies in this box, its faces included.

        Args:
            point: The point to test.

        Returns:
            Whether it is inside or on the surface.
        """
        return (
            point.x >= self.min.x
            and point.x <= self.max.x
            and point.y >= self.min.y
            and point.y <= self.max.y
            and point.z >= self.min.z
            and point.z <= self.max.z
        )

    def _nearest(self, point: Vector3) -> Vector3:
        """Return the point of this box nearest `point`, the box assumed
        not empty: the point itself inside, else the nearest surface point."""
        return Vector3(
            min(max(point.x, self.min.x), self.max.x),
            min(max(point.y, self.min.y), self.max.y),
            min(max(point.z, self.min.z), self.max.z),
        )

    def clamp_point(self, point: Vector3) raises -> Vector3:
        """Return the point of this box nearest `point`: the point itself
        if it is inside, else the nearest point on the surface.

        Args:
            point: The point to bring inside.

        Returns:
            The nearest point of the box.

        Raises:
            Error: If the box is empty. It has no points, so none is
                nearest, and an inside-out corner is not an answer.
        """
        if self.is_empty():
            raise Error("An empty box has no nearest point")
        return self._nearest(point)

    def distance_to_point(self, point: Vector3) raises -> Float32:
        """Return how far `point` is from this box: zero inside it.

        Args:
            point: The point to measure from.

        Returns:
            The distance to the nearest point of the box.

        Raises:
            Error: If the box is empty; see `clamp_point`.
        """
        return (self.clamp_point(point) - point).length()

    def intersects_box(self, other: Box3) -> Bool:
        """Return True if the two boxes share any point, a shared face
        included. An empty box shares none.

        Args:
            other: The other box.

        Returns:
            Whether they overlap.
        """
        if self.is_empty() or other.is_empty():
            return False
        return not (
            other.max.x < self.min.x
            or other.min.x > self.max.x
            or other.max.y < self.min.y
            or other.min.y > self.max.y
            or other.max.z < self.min.z
            or other.min.z > self.max.z
        )

    def intersects_sphere(self, sphere: Sphere) -> Bool:
        """Return True if `sphere` reaches into this box.

        The point of the box nearest the sphere's center is the one that
        decides it. An empty box or an empty sphere reaches nothing.

        Args:
            sphere: The sphere.

        Returns:
            Whether they overlap.
        """
        if self.is_empty() or sphere.is_empty():
            return False
        return (
            self._nearest(sphere.center) - sphere.center
        ).length() <= sphere.radius

    def apply_matrix4(mut self, matrix: Matrix4) raises:
        """Transform this box, and take the box around what comes out.

        A transformed box is not a box unless the transform only scales and
        translates, so this carries the eight corners across and bounds
        them again. What comes out can be larger than the shape it stood
        for; it is still a bound. An empty box stays empty, because its
        inside-out corners would otherwise become finite nonsense.

        Args:
            matrix: The transform to apply. Affine: it moves, turns, scales
                or shears, and keeps `w` at one.

        Raises:
            Error: If the matrix projects. A corner crossing `w = 0` has no
                finite image, and eight carried corners are no bound on it.
        """
        if not matrix.is_affine():
            raise Error("A bound can only be carried through an affine matrix")
        if self.is_empty():
            return
        var corners = List[Vector3]()
        for index in range(8):  # pragma: no branch
            var x = self.min.x
            if index & 1 != 0:
                x = self.max.x
            var y = self.min.y
            if index & 2 != 0:
                y = self.max.y
            var z = self.min.z
            if index & 4 != 0:
                z = self.max.z
            corners.append(matrix.transform_point(Vector3(x, y, z)))
        self = Box3.from_points(corners)

    def bounding_sphere(self) -> Sphere:
        """Return the sphere around this box: its center, and half its
        diagonal as the radius. Empty for an empty box.

        Returns:
            The sphere.
        """
        if self.is_empty():
            return Sphere.empty()
        return Sphere(self.center(), self.size().length() * 0.5)

    @staticmethod
    def from_center_and_size(center: Vector3, size: Vector3) -> Box3:
        """Return the box of a size centered on a point, three.js's
        `setFromCenterAndSize`.

        Args:
            center: The middle.
            size: The extent along each axis. A negative one gives an
                empty box.

        Returns:
            The box.
        """
        var half = size * 0.5
        return Box3(center - half, center + half)

    def __eq__(self, other: Self) -> Bool:
        """Return True if both corners are exactly equal, three.js's
        `equals`.

        Args:
            other: The box to compare with.

        Returns:
            Whether the corners match.
        """
        return self.min == other.min and self.max == other.max

    def __ne__(self, other: Self) -> Bool:
        """Return True if a corner differs.

        Args:
            other: The box to compare with.

        Returns:
            Whether the two differ.
        """
        return not self == other

    def expand_by_vector(mut self, amount: Vector3):
        """Grow this box by `amount` on every side, three.js's
        `expandByVector`. A negative amount shrinks it. The empty box stays
        empty, because its corners are infinite.

        Args:
            amount: How far to move each face out, per axis.
        """
        self.min = self.min - amount
        self.max = self.max + amount

    def expand_by_scalar(mut self, amount: Float32):
        """Grow this box by `amount` on every side, three.js's
        `expandByScalar`.

        Args:
            amount: How far to move each face out.
        """
        self.expand_by_vector(Vector3(amount, amount, amount))

    def translate(mut self, offset: Vector3):
        """Move this box by `offset`, three.js's `translate`.

        Args:
            offset: How far.
        """
        self.min = self.min + offset
        self.max = self.max + offset

    def intersect(mut self, other: Box3):
        """Shrink this box to what both boxes hold, three.js's `intersect`.
        Boxes that do not overlap leave the empty box.

        Args:
            other: The other box.
        """
        self.min.max(other.min)
        self.max.min(other.max)
        if self.is_empty():
            self = Box3.empty()

    def contains_box(self, other: Box3) -> Bool:
        """Return True if `other` lies wholly inside this box, its faces
        included, three.js's `containsBox`. The empty box lies inside every
        box.

        Args:
            other: The box to test.

        Returns:
            Whether this box holds all of it.
        """
        return (
            self.min.x <= other.min.x
            and other.max.x <= self.max.x
            and self.min.y <= other.min.y
            and other.max.y <= self.max.y
            and self.min.z <= other.min.z
            and other.max.z <= self.max.z
        )

    def get_parameter(self, point: Vector3) raises -> Vector3:
        """Return where a point lies in this box as a fraction of each
        side, three.js's `getParameter`: zero at `min`, one at `max`.

        Args:
            point: The point.

        Returns:
            The fractions.

        Raises:
            Error: If the box has no extent on an axis, or is empty.
                three.js divides by zero there.
        """
        var extent = self.max - self.min
        if extent.x <= 0 or extent.y <= 0 or extent.z <= 0:
            raise Error("A box with no extent on an axis has no fractions")
        return Vector3(
            (point.x - self.min.x) / extent.x,
            (point.y - self.min.y) / extent.y,
            (point.z - self.min.z) / extent.z,
        )

    def intersects_plane(self, plane: Plane) -> Bool:
        """Return True if `plane` passes through this box, three.js's
        `intersectsPlane`. The empty box meets no plane.

        Args:
            plane: The plane.

        Returns:
            Whether they meet, a touching face included.
        """
        return plane.intersects_box(self)

    def intersects_triangle(self, triangle: Triangle) -> Bool:
        """Return True if `triangle` reaches into this box, three.js's
        `intersectsTriangle`: the separating axis test over the box's
        three face normals, the triangle's normal and the nine cross
        products of their edges. The empty box meets no triangle.

        Args:
            triangle: The triangle.

        Returns:
            Whether they share a point.
        """
        if self.is_empty():
            return False
        var center = self.center()
        var extents = self.max - center
        var v0 = triangle.a - center
        var v1 = triangle.b - center
        var v2 = triangle.c - center
        var f0 = v1 - v0
        var f1 = v2 - v1
        var f2 = v0 - v2
        var edges: Array[Vector3, 3] = [f0, f1, f2]
        for edge in range(3):  # pragma: no branch
            var f = edges[edge]
            var axes: Array[Vector3, 3] = [
                Vector3(0, -f.z, f.y),
                Vector3(f.z, 0, -f.x),
                Vector3(-f.y, f.x, 0),
            ]
            for axis in range(3):  # pragma: no branch
                if _separates(axes[axis], v0, v1, v2, extents):
                    return False
        var faces: Array[Vector3, 3] = [
            Vector3(1, 0, 0),
            Vector3(0, 1, 0),
            Vector3(0, 0, 1),
        ]
        for face in range(3):  # pragma: no branch
            if _separates(faces[face], v0, v1, v2, extents):
                return False
        var normal = f0
        normal.cross(f1)
        return not _separates(normal, v0, v1, v2, extents)


@fieldwise_init
struct Sphere(Equatable, ImplicitlyCopyable):
    """A sphere: a center and a radius. A negative radius is the empty
    sphere, as in three.js."""

    var center: Vector3
    var radius: Float32

    @staticmethod
    def empty() -> Sphere:
        """Return the sphere that holds no points: radius minus one.

        Returns:
            The empty sphere.
        """
        return Sphere(Vector3(0, 0, 0), -1)

    @staticmethod
    def from_points(points: List[Vector3]) -> Sphere:
        """Return a sphere around every point given.

        three.js's `setFromPoints` without a center: the center of the
        points' box, and the radius the farthest point is from it. Not the
        smallest sphere possible -- that is a harder problem -- but a bound,
        found in two passes.

        Args:
            points: Any number of points, including none.

        Returns:
            Their sphere, or the empty sphere for no points.
        """
        if len(points) == 0:
            return Sphere.empty()
        var center = Box3.from_points(points).center()
        var farthest = Float32(0)
        for index in range(len(points)):  # pragma: no branch
            var reach = (points[index] - center).length()
            if reach > farthest:
                farthest = reach
        return Sphere(center, farthest)

    def is_empty(self) -> Bool:
        """Return True if this sphere holds no points. A radius of zero is
        one point, not none."""
        return self.radius < 0

    def contains_point(self, point: Vector3) -> Bool:
        """Return True if `point` lies in this sphere, its surface included.

        Args:
            point: The point to test.

        Returns:
            Whether it is inside or on the surface.
        """
        return (point - self.center).length() <= self.radius

    def distance_to_point(self, point: Vector3) raises -> Float32:
        """Return how far `point` is outside this sphere: negative inside.

        Args:
            point: The point to measure from.

        Returns:
            The distance to the surface, signed.

        Raises:
            Error: If the sphere is empty. It has no surface to measure
                from, and its negative radius is not an answer.
        """
        if self.is_empty():
            raise Error("An empty sphere has no surface to measure from")
        return (point - self.center).length() - self.radius

    def intersects_sphere(self, other: Sphere) -> Bool:
        """Return True if the two spheres share any point. An empty sphere
        shares none, whatever the sum of the radii says.

        Args:
            other: The other sphere.

        Returns:
            Whether they overlap or touch.
        """
        if self.is_empty() or other.is_empty():
            return False
        return (
            other.center - self.center
        ).length() <= self.radius + other.radius

    def intersects_box(self, box: Box3) -> Bool:
        """Return True if this sphere reaches into `box`.

        Args:
            box: The box.

        Returns:
            Whether they overlap.
        """
        return box.intersects_sphere(self)

    def expand_by_point(mut self, point: Vector3):
        """Grow this sphere to hold `point` as well, by as little as
        possible: it moves toward the point and grows by half the distance
        left over. An empty sphere becomes the sphere of that one point.

        Args:
            point: The point to take in.
        """
        if self.is_empty():
            self.center = point
            self.radius = 0
            return
        var toward = point - self.center
        var reach = toward.length()
        if reach > self.radius:
            var growth = (reach - self.radius) * 0.5
            self.center.add(toward * (growth / reach))
            self.radius += growth

    def apply_matrix4(mut self, matrix: Matrix4) raises:
        """Transform this sphere: its center goes through the matrix and
        its radius grows by a bound on the most the matrix stretches any
        direction.

        A sphere cannot follow a nonuniform scale, so it grows by the most
        any direction is stretched and stays a bound. three.js grows by the
        longest axis, which is that stretch only while the axes are at
        right angles: a parent scaled (2, 1, 1) above a child turned 45
        degrees stretches the diagonal to two while no axis is longer than
        1.58, and a sphere grown by 1.58 misses points it held. This grows
        by `Matrix4.max_stretch` instead, which never falls short. An empty
        sphere stays empty, rather than a scale of zero turning its
        negative radius into a point.

        Args:
            matrix: The transform to apply. Affine: it moves, turns, scales
                or shears, and keeps `w` at one.

        Raises:
            Error: If the matrix projects; see `Box3.apply_matrix4`.
        """
        if not matrix.is_affine():
            raise Error("A bound can only be carried through an affine matrix")
        if self.is_empty():
            return
        self.center = matrix.transform_point(self.center)
        self.radius *= matrix.max_stretch()

    def bounding_box(self) -> Box3:
        """Return the box around this sphere. Empty for an empty sphere.

        Returns:
            The box.
        """
        if self.is_empty():
            return Box3.empty()
        var reach = Vector3(self.radius, self.radius, self.radius)
        return Box3(self.center - reach, self.center + reach)

    @staticmethod
    def from_points_around(points: List[Vector3], center: Vector3) -> Sphere:
        """Return the sphere centered on `center` that reaches every point
        given, three.js's `setFromPoints` with its optional center.

        Args:
            points: Any number of points, including none.
            center: The center to use.

        Returns:
            The sphere. With no points, the radius is zero, as in three.js.
        """
        var farthest = Float32(0)
        for index in range(len(points)):
            farthest = max(farthest, center.distance_to_squared(points[index]))
        return Sphere(center, sqrt(farthest))

    def __eq__(self, other: Self) -> Bool:
        """Return True if the centers and the radii are exactly equal,
        three.js's `equals`.

        Args:
            other: The sphere to compare with.

        Returns:
            Whether the two match.
        """
        return self.center == other.center and self.radius == other.radius

    def __ne__(self, other: Self) -> Bool:
        """Return True if the center or the radius differs.

        Args:
            other: The sphere to compare with.

        Returns:
            Whether the two differ.
        """
        return not self == other

    def intersects_plane(self, plane: Plane) -> Bool:
        """Return True if `plane` passes through this sphere, three.js's
        `intersectsPlane`. The empty sphere meets no plane.

        Args:
            plane: The plane.

        Returns:
            Whether they meet, a touching surface included.
        """
        return plane.intersects_sphere(self)

    def clamp_point(self, point: Vector3) raises -> Vector3:
        """Return the point of this sphere nearest `point`, three.js's
        `clampPoint`: the point itself inside, else the nearest point on
        the surface.

        Args:
            point: The point to bring inside.

        Returns:
            The nearest point of the sphere.

        Raises:
            Error: If the sphere is empty. three.js takes its radius of
                minus one as a radius of one.
        """
        if self.is_empty():
            raise Error("An empty sphere has no nearest point")
        if self.center.distance_to_squared(point) <= self.radius * self.radius:
            return point
        var toward = point - self.center
        toward.normalize()
        return toward * self.radius + self.center

    def translate(mut self, offset: Vector3):
        """Move this sphere by `offset`, three.js's `translate`.

        Args:
            offset: How far.
        """
        self.center.add(offset)

    def union(mut self, other: Sphere):
        """Grow this sphere to hold all of `other` as well, three.js's
        `union`: expand by the two points of `other` farthest along the
        line between the centers.

        Args:
            other: The sphere to take in. The empty sphere changes nothing.
        """
        if other.is_empty():
            return
        if self.is_empty():
            self = other
            return
        if self.center == other.center:
            self.radius = max(self.radius, other.radius)
            return
        var reach = other.center - self.center
        reach.set_length(other.radius)
        self.expand_by_point(other.center + reach)
        self.expand_by_point(other.center - reach)


struct Plane(Equatable, ImplicitlyCopyable):
    """A plane: the points where `dot(normal, point) + constant` is zero.

    `normal` is unit length and points to the plane's front, the side where
    that expression is positive. `constant` is then minus the distance of
    the plane from the origin along the normal.
    """

    var normal: Vector3
    var constant: Float32

    def __init__(out self, normal: Vector3, constant: Float32) raises:
        """Create a plane, normalizing the normal and the constant with it.

        Args:
            normal: Which way the plane faces. Any length but zero; it is
                scaled to unit length, and `constant` by the same amount, so
                the plane described does not move.
            constant: Minus the plane's distance from the origin along
                `normal`, at whatever length `normal` was given.

        Raises:
            Error: If the normal has no length: no direction, no plane.
        """
        var length = normal.length()
        if length == 0:
            raise Error("A plane needs a normal with some length")
        self.normal = normal * (1 / length)
        self.constant = constant / length

    @staticmethod
    def from_normal_and_point(normal: Vector3, point: Vector3) raises -> Plane:
        """Return the plane through `point` facing `normal`.

        Args:
            normal: Which way the plane faces; any length but zero.
            point: A point on the plane.

        Returns:
            The plane.

        Raises:
            Error: If the normal has no length.
        """
        return Plane(normal, -normal.dot(point))

    @staticmethod
    def from_coplanar_points(
        a: Vector3, b: Vector3, c: Vector3
    ) raises -> Plane:
        """Return the plane through three points, facing the side they are
        counter-clockwise from.

        The normal is `(c - b) x (a - b)`, three.js's choice, which is the
        front of a triangle wound `a`, `b`, `c` counter-clockwise.

        Args:
            a: First point.
            b: Second point.
            c: Third point.

        Returns:
            The plane.

        Raises:
            Error: If the points lie on one line, or two of them coincide,
                which leaves no plane to choose.
        """
        var normal = c - b
        normal.cross(a - b)
        if normal.length() == 0:
            raise Error("Three points on one line do not make a plane")
        return Plane(normal, -normal.dot(a))

    def distance_to_point(self, point: Vector3) -> Float32:
        """Return how far `point` is in front of this plane: negative
        behind it, zero on it.

        Args:
            point: The point to measure.

        Returns:
            The signed distance.
        """
        return self.normal.dot(point) + self.constant

    def distance_to_sphere(self, sphere: Sphere) raises -> Float32:
        """Return how far `sphere` is in front of this plane: negative if
        it crosses or lies behind.

        Args:
            sphere: The sphere to measure.

        Returns:
            The signed distance of its nearest point.

        Raises:
            Error: If the sphere is empty: it has no nearest point.
        """
        if sphere.is_empty():
            raise Error("An empty sphere has no nearest point to a plane")
        return self.distance_to_point(sphere.center) - sphere.radius

    def project_point(self, point: Vector3) -> Vector3:
        """Return the point of this plane nearest `point`.

        Args:
            point: The point to project.

        Returns:
            Its foot on the plane.
        """
        return point - self.normal * self.distance_to_point(point)

    def coplanar_point(self) -> Vector3:
        """Return a point on this plane: the one nearest the origin."""
        return self.normal * (-self.constant)

    def negate(mut self):
        """Turn this plane around: the same points, facing the other way."""
        self.normal = -self.normal
        self.constant = -self.constant

    def translate(mut self, offset: Vector3):
        """Move this plane by `offset`, without turning it.

        Args:
            offset: How far to move it.
        """
        self.constant -= self.normal.dot(offset)

    def intersects_sphere(self, sphere: Sphere) -> Bool:
        """Return True if `sphere` crosses this plane. An empty sphere
        crosses nothing.

        Args:
            sphere: The sphere.

        Returns:
            Whether the plane passes through it.
        """
        if sphere.is_empty():
            return False
        return abs(self.distance_to_point(sphere.center)) <= sphere.radius

    def intersects_box(self, box: Box3) -> Bool:
        """Return True if `box` crosses this plane. An empty box crosses
        nothing.

        The box's extent along the normal runs from its most-behind corner
        to its most-in-front one, and each axis contributes whichever of its
        two faces the normal's sign puts on which side. three.js's test.

        Args:
            box: The box.

        Returns:
            Whether the plane passes through it, a touching face included.
        """
        if box.is_empty():
            return False
        var nearest = Float32(0)
        var farthest = Float32(0)
        if self.normal.x > 0:
            nearest += self.normal.x * box.min.x
            farthest += self.normal.x * box.max.x
        else:
            nearest += self.normal.x * box.max.x
            farthest += self.normal.x * box.min.x
        if self.normal.y > 0:
            nearest += self.normal.y * box.min.y
            farthest += self.normal.y * box.max.y
        else:
            nearest += self.normal.y * box.max.y
            farthest += self.normal.y * box.min.y
        if self.normal.z > 0:
            nearest += self.normal.z * box.min.z
            farthest += self.normal.z * box.max.z
        else:
            nearest += self.normal.z * box.max.z
            farthest += self.normal.z * box.min.z
        return nearest <= -self.constant and farthest >= -self.constant

    def __eq__(self, other: Self) -> Bool:
        """Return True if the normals and the constants are exactly equal,
        three.js's `equals`. A plane and its negation hold the same points
        and are not equal, as there.

        Args:
            other: The plane to compare with.

        Returns:
            Whether the two match.
        """
        return self.normal == other.normal and self.constant == other.constant

    def __ne__(self, other: Self) -> Bool:
        """Return True if the normal or the constant differs.

        Args:
            other: The plane to compare with.

        Returns:
            Whether the two differ.
        """
        return not self == other

    def intersect_line(self, line: Line3) -> Optional[Vector3]:
        """Return where a segment crosses this plane, three.js's
        `intersectLine`.

        Args:
            line: The segment.

        Returns:
            The crossing point, or None if the segment stops short of the
            plane or runs parallel to it. A segment in the plane gives its
            start, as in three.js.
        """
        var direction = line.delta()
        var denominator = self.normal.dot(direction)
        if denominator == 0:
            if self.distance_to_point(line.start) == 0:
                return line.start
            return None
        var t = -(line.start.dot(self.normal) + self.constant) / denominator
        if t < 0 or t > 1:
            return None
        return line.start + direction * t

    def intersects_line(self, line: Line3) -> Bool:
        """Return True if the segment's two ends lie on opposite sides of
        this plane, three.js's `intersectsLine`. An end on the plane does
        not count, as there.

        Args:
            line: The segment.

        Returns:
            Whether it crosses.
        """
        var start = self.distance_to_point(line.start)
        var end = self.distance_to_point(line.end)
        return (start < 0 and end > 0) or (end < 0 and start > 0)

    def apply_matrix4(mut self, matrix: Matrix4) raises:
        """Carry this plane through a transform, three.js's `applyMatrix4`.

        A point of the plane goes through the matrix, and the normal goes
        through the normal matrix, `Matrix3.normal_matrix`.

        Args:
            matrix: The transform.

        Raises:
            Error: If the transform collapses a dimension, which leaves no
                normal matrix. three.js builds one of zeros and gives a
                plane with no normal.
        """
        self.apply_matrix4(matrix, Matrix3.normal_matrix(matrix))

    def apply_matrix4(mut self, matrix: Matrix4, normal_matrix: Matrix3) raises:
        """Carry this plane through a transform whose normal matrix the
        caller already has, three.js's `applyMatrix4` with its optional
        second argument.

        Args:
            matrix: The transform.
            normal_matrix: The normal matrix of `matrix`.

        Raises:
            Error: If the normal comes out with no length.
        """
        var point = matrix.transform_point(self.coplanar_point())
        var normal = normal_matrix.transform(self.normal)
        if normal.length() == 0:
            raise Error("A plane carried through a collapse has no normal")
        normal.normalize()
        self.normal = normal
        self.constant = -point.dot(normal)


def _separates(
    axis: Vector3, v0: Vector3, v1: Vector3, v2: Vector3, extents: Vector3
) -> Bool:
    """Return True if `axis` separates a triangle from a box centered on
    the origin, the test three.js's `satForAxes` makes per axis.

    Args:
        axis: The axis to project onto. A zero axis separates nothing.
        v0: The first corner, relative to the box's center.
        v1: The second corner.
        v2: The third corner.
        extents: Half the box's size.

    Returns:
        Whether the two projections do not overlap.
    """
    var reach = (
        extents.x * abs(axis.x)
        + extents.y * abs(axis.y)
        + extents.z * abs(axis.z)
    )
    var p0 = v0.dot(axis)
    var p1 = v1.dot(axis)
    var p2 = v2.dot(axis)
    return max(-max(p0, max(p1, p2)), min(p0, min(p1, p2))) > reach
