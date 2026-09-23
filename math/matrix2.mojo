# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A 2x2 matrix and a 2D box, from three.js `src/math/Matrix2.js` and
`src/math/Box2.js`.

`Matrix2` is stored row by row, `m00 m01 / m10 m11`, and multiplies a
column vector on its right, as `Matrix3` and `Matrix4` do. `Box2` is
`Box3` in the plane, with the same empty box: corners inside out, so that
the first point expanded into it becomes both.
"""

from math.vector2 import Vector2
from std.math import cos, inf, sin, sqrt
from units.si import Angle, RADIAN


@fieldwise_init
struct Matrix2(Equatable, ImplicitlyCopyable):
    """A 2x2 matrix, row by row."""

    var m00: Float32
    var m01: Float32
    var m10: Float32
    var m11: Float32

    @staticmethod
    def identity() -> Matrix2:
        """Return the identity.

        Returns:
            The matrix that changes nothing.
        """
        return Matrix2(1, 0, 0, 1)

    @staticmethod
    def rotation(angle: Angle) -> Matrix2:
        """Return a counterclockwise rotation.

        Args:
            angle: The angle.

        Returns:
            The rotation.
        """
        var c = cos(angle.to(RADIAN))
        var s = sin(angle.to(RADIAN))
        return Matrix2(c, -s, s, c)

    @staticmethod
    def scaling(x: Float32, y: Float32) -> Matrix2:
        """Return a scale along each axis.

        Args:
            x: The factor along x.
            y: The factor along y.

        Returns:
            The scale.
        """
        return Matrix2(x, 0, 0, y)

    def __eq__(self, other: Self) -> Bool:
        """Return True if every element is equal.

        Args:
            other: The other matrix.

        Returns:
            Whether they are equal.
        """
        return (
            self.m00 == other.m00
            and self.m01 == other.m01
            and self.m10 == other.m10
            and self.m11 == other.m11
        )

    def __ne__(self, other: Self) -> Bool:
        """Return True if an element differs.

        Args:
            other: The other matrix.

        Returns:
            Whether they differ.
        """
        return not self == other

    def __mul__(self, other: Self) -> Self:
        """Return `self * other`, which applies `other` first.

        Args:
            other: The matrix on the right.

        Returns:
            The product.
        """
        return Matrix2(
            self.m00 * other.m00 + self.m01 * other.m10,
            self.m00 * other.m01 + self.m01 * other.m11,
            self.m10 * other.m00 + self.m11 * other.m10,
            self.m10 * other.m01 + self.m11 * other.m11,
        )

    def determinant(self) -> Float32:
        """Return the determinant.

        Returns:
            `m00 m11 - m01 m10`.
        """
        return self.m00 * self.m11 - self.m01 * self.m10

    def transposed(self) -> Self:
        """Return the transpose.

        Returns:
            The matrix mirrored across its diagonal.
        """
        return Matrix2(self.m00, self.m10, self.m01, self.m11)

    def inverse(self) raises -> Self:
        """Return the inverse.

        Returns:
            The matrix that undoes this one.

        Raises:
            Error: If the determinant is zero. three.js returns zeros.
        """
        var det = self.determinant()
        if det == 0:
            raise Error("A singular Matrix2 has no inverse")
        var inv = 1 / det
        return Matrix2(
            self.m11 * inv, -self.m01 * inv, -self.m10 * inv, self.m00 * inv
        )

    def transform(self, vector: Vector2) -> Vector2:
        """Return the matrix times a column vector.

        Args:
            vector: The vector.

        Returns:
            The transformed vector.
        """
        return Vector2(
            self.m00 * vector.x + self.m01 * vector.y,
            self.m10 * vector.x + self.m11 * vector.y,
        )


@fieldwise_init
struct Box2(ImplicitlyCopyable):
    """An axis-aligned rectangle: its smallest and largest corner."""

    var min: Vector2
    var max: Vector2

    @staticmethod
    def empty() -> Box2:
        """Return the box that holds no points.

        Returns:
            The box with its corners inside out.
        """
        var far = inf[DType.float32]()
        return Box2(Vector2(far, far), Vector2(-far, -far))

    @staticmethod
    def from_points(points: List[Vector2]) -> Box2:
        """Return the smallest box around every point given.

        Args:
            points: Any number of points, including none.

        Returns:
            Their box, or the empty box for no points.
        """
        var box = Box2.empty()
        for index in range(len(points)):
            box.expand_by_point(points[index])
        return box

    def is_empty(self) -> Bool:
        """Return True if a corner is inside out on some axis.

        Returns:
            Whether the box holds no points.
        """
        return self.max.x < self.min.x or self.max.y < self.min.y

    def expand_by_point(mut self, point: Vector2):
        """Grow the box to hold a point.

        Args:
            point: The point.
        """
        if self.is_empty():
            self.min = point
            self.max = point
            return
        self.min = Vector2(min(self.min.x, point.x), min(self.min.y, point.y))
        self.max = Vector2(max(self.max.x, point.x), max(self.max.y, point.y))

    def union(mut self, other: Box2):
        """Grow the box to hold everything another holds.

        Args:
            other: The other box.
        """
        if other.is_empty():
            return
        self.expand_by_point(other.min)
        self.expand_by_point(other.max)

    def intersect(mut self, other: Box2):
        """Shrink the box to what both hold. Boxes that do not overlap
        leave the empty box.

        Args:
            other: The other box.
        """
        self.min = Vector2(
            max(self.min.x, other.min.x), max(self.min.y, other.min.y)
        )
        self.max = Vector2(
            min(self.max.x, other.max.x), min(self.max.y, other.max.y)
        )
        if self.is_empty():
            self = Box2.empty()

    def center(self) -> Vector2:
        """Return the middle.

        Returns:
            Halfway between the corners.
        """
        return (self.min + self.max) * 0.5

    def size(self) -> Vector2:
        """Return the width and height.

        Returns:
            The size, zero for the empty box.
        """
        if self.is_empty():
            return Vector2(0, 0)
        return self.max - self.min

    def contains_point(self, point: Vector2) -> Bool:
        """Return True if a point lies inside or on the edge.

        Args:
            point: The point.

        Returns:
            Whether the box holds it.
        """
        return (
            point.x >= self.min.x
            and point.x <= self.max.x
            and point.y >= self.min.y
            and point.y <= self.max.y
        )

    def intersects_box(self, other: Box2) -> Bool:
        """Return True if the boxes overlap or touch.

        Args:
            other: The other box.

        Returns:
            Whether they share a point.
        """
        return not (
            other.max.x < self.min.x
            or other.min.x > self.max.x
            or other.max.y < self.min.y
            or other.min.y > self.max.y
        )

    def clamp_point(self, point: Vector2) raises -> Vector2:
        """Return the point of the box nearest a point.

        Args:
            point: The point.

        Returns:
            The point itself if inside, else the nearest edge point.

        Raises:
            Error: If the box is empty.
        """
        if self.is_empty():
            raise Error("An empty box has no nearest point")
        return Vector2(
            max(self.min.x, min(self.max.x, point.x)),
            max(self.min.y, min(self.max.y, point.y)),
        )

    def distance_to_point(self, point: Vector2) raises -> Float32:
        """Return the distance from a point to the box.

        Args:
            point: The point.

        Returns:
            Zero inside.

        Raises:
            Error: If the box is empty.
        """
        var gap = self.clamp_point(point) - point
        return sqrt(gap.dot(gap))
