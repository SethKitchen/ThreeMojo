# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A box, a sphere and a plane, from three.js `src/math/Box3.js`,
`src/math/Sphere.js` and `src/math/Plane.js`.

The three shapes a renderer asks questions of rather than draws: does this
mesh lie inside the view, which mesh did the click land on, which side of
the near plane is this corner. A box and a sphere are *bounds*: the smallest
of their kind around a set of points, cheap to test and to carry through a
transform. A plane is the thing a frustum is six of.

All three hold bare `Float32` meters, as `Vector3` does, because they are
made of `Vector3`s and are compared with them. The quantities with units
live at the API's edges -- a geometry builder takes a `Length` -- and the
math in the middle is plain numbers, which is also where the GPU reads it.

An *empty* bound is one that holds no points at all, and it is a value
rather than an error, as in three.js: a box whose corners are inside out,
a sphere with a negative radius. Expanding an empty bound by a point gives
the bound of that one point, which is what lets a bound be built from any
number of points, including none, without a special first step.

A plane is stored as a unit normal and a constant, so a point's signed
distance is one dot product and an add. The constructor normalizes both,
because every question a plane answers assumes the normal is unit and a
plane built from three points has no reason to have one. A zero normal is
refused: it is not a plane.
"""

from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.math import inf, sqrt


@fieldwise_init
struct Box3(ImplicitlyCopyable):
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
        """Grow this box to hold `point` as well.

        Args:
            point: The point to take in.
        """
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
        largest, corner by corner rather than point by point: an empty
        box's inside-out infinities then lose every comparison, and taking
        one in changes nothing.

        Args:
            other: The box to take in.
        """
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

    def clamp_point(self, point: Vector3) -> Vector3:
        """Return the point of this box nearest `point`: the point itself
        if it is inside, else the nearest point on the surface.

        Args:
            point: The point to bring inside.

        Returns:
            The nearest point of the box.
        """
        return Vector3(
            min(max(point.x, self.min.x), self.max.x),
            min(max(point.y, self.min.y), self.max.y),
            min(max(point.z, self.min.z), self.max.z),
        )

    def distance_to_point(self, point: Vector3) -> Float32:
        """Return how far `point` is from this box: zero inside it.

        Args:
            point: The point to measure from.

        Returns:
            The distance to the nearest point of the box.
        """
        return (self.clamp_point(point) - point).length()

    def intersects_box(self, other: Box3) -> Bool:
        """Return True if the two boxes share any point, a shared face
        included.

        Args:
            other: The other box.

        Returns:
            Whether they overlap.
        """
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
        decides it, and `clamp_point` finds that point.

        Args:
            sphere: The sphere.

        Returns:
            Whether they overlap.
        """
        return self.distance_to_point(sphere.center) <= sphere.radius

    def apply_matrix4(mut self, matrix: Matrix4):
        """Transform this box, and take the box around what comes out.

        A transformed box is not a box unless the transform only scales and
        translates, so this carries the eight corners across and bounds
        them again. What comes out can be larger than the shape it stood
        for; it is still a bound. An empty box stays empty, because its
        infinite corners would otherwise become finite nonsense.

        Args:
            matrix: The transform to apply.
        """
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


@fieldwise_init
struct Sphere(ImplicitlyCopyable):
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

    def distance_to_point(self, point: Vector3) -> Float32:
        """Return how far `point` is outside this sphere: negative inside.

        Args:
            point: The point to measure from.

        Returns:
            The distance to the surface, signed.
        """
        return (point - self.center).length() - self.radius

    def intersects_sphere(self, other: Sphere) -> Bool:
        """Return True if the two spheres share any point.

        Args:
            other: The other sphere.

        Returns:
            Whether they overlap or touch.
        """
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

    def apply_matrix4(mut self, matrix: Matrix4):
        """Transform this sphere: its center goes through the matrix and
        its radius grows by the most the matrix stretches anything.

        A sphere cannot follow a nonuniform scale, so it takes the largest
        one and stays a bound, as three.js's does.

        Args:
            matrix: The transform to apply.
        """
        self.center = matrix.transform_point(self.center)
        self.radius *= matrix.max_scale()

    def bounding_box(self) -> Box3:
        """Return the box around this sphere. Empty for an empty sphere.

        Returns:
            The box.
        """
        if self.is_empty():
            return Box3.empty()
        var reach = Vector3(self.radius, self.radius, self.radius)
        return Box3(self.center - reach, self.center + reach)


struct Plane(ImplicitlyCopyable):
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

    def distance_to_sphere(self, sphere: Sphere) -> Float32:
        """Return how far `sphere` is in front of this plane: negative if
        it crosses or lies behind.

        Args:
            sphere: The sphere to measure.

        Returns:
            The signed distance of its nearest point.
        """
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
        """Return True if `sphere` crosses this plane.

        Args:
            sphere: The sphere.

        Returns:
            Whether the plane passes through it.
        """
        return abs(self.distance_to_point(sphere.center)) <= sphere.radius

    def intersects_box(self, box: Box3) -> Bool:
        """Return True if `box` crosses this plane.

        The box's extent along the normal runs from its most-behind corner
        to its most-in-front one, and each axis contributes whichever of its
        two faces the normal's sign puts on which side. three.js's test.

        Args:
            box: The box.

        Returns:
            Whether the plane passes through it, a touching face included.
        """
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
