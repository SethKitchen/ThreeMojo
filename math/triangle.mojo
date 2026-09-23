# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A triangle and a line segment, from three.js `src/math/Triangle.js` and
`src/math/Line3.js`.

Both hold bare `Float32` meters, as `Vector3` does. A degenerate triangle,
one whose corners lie on a line, has no normal and no barycentric
coordinates; three.js answers those with a zero vector or `null`, and
here a question that has no answer is refused.
"""

from math.bounds import Plane
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.math import sqrt


def _cross(a: Vector3, b: Vector3) -> Vector3:
    """Return the cross product of two vectors."""
    var out = a
    out.cross(b)
    return out


@fieldwise_init
struct Triangle(ImplicitlyCopyable):
    """Three corners, counterclockwise when seen from the front."""

    var a: Vector3
    var b: Vector3
    var c: Vector3

    def raw_normal(self) -> Vector3:
        """Return the unnormalized normal, twice the area long.

        Returns:
            `(c - b) x (a - b)`, three.js's order.
        """
        return _cross(self.c - self.b, self.a - self.b)

    def area(self) -> Float32:
        """Return the triangle's area.

        Returns:
            Half the length of the cross product of two edges.
        """
        return self.raw_normal().length() / 2

    def is_degenerate(self) -> Bool:
        """Return True if the corners lie on one line.

        Returns:
            Whether the area is zero.
        """
        return self.raw_normal().length() == 0

    def normal(self) raises -> Vector3:
        """Return the unit normal. three.js: `getNormal`.

        Returns:
            The normal, facing the side the corners turn counterclockwise.

        Raises:
            Error: If the triangle is degenerate.
        """
        if self.is_degenerate():
            raise Error("A degenerate triangle has no normal")
        var out = self.raw_normal()
        out.normalize()
        return out

    def midpoint(self) -> Vector3:
        """Return the average of the corners. three.js: `getMidpoint`.

        Returns:
            The centroid.
        """
        return (self.a + self.b + self.c) * (Float32(1) / 3)

    def plane(self) raises -> Plane:
        """Return the plane the triangle lies in. three.js: `getPlane`.

        Returns:
            The plane, its normal the triangle's.

        Raises:
            Error: If the triangle is degenerate.
        """
        return Plane.from_normal_and_point(self.normal(), self.a)

    def barycoord(self, point: Vector3) raises -> Vector3:
        """Return a point's barycentric coordinates. three.js:
        `getBarycoord`.

        The point is projected onto the triangle's plane first.

        Args:
            point: The point.

        Returns:
            The weights of `a`, `b` and `c`, which sum to one.

        Raises:
            Error: If the triangle is degenerate.
        """
        var found = self._weights(point)
        if not Bool(found):
            raise Error("A degenerate triangle has no barycentric coordinates")
        return found.value()

    def _weights(self, point: Vector3) -> Optional[Vector3]:
        """Return a point's barycentric coordinates, or None for a
        degenerate triangle.

        The formula uses dot products within the plane, so it answers for
        the point's projection onto the plane.
        """
        var v0 = self.c - self.a
        var v1 = self.b - self.a
        var v2 = point - self.a
        var dot00 = v0.dot(v0)
        var dot01 = v0.dot(v1)
        var dot02 = v0.dot(v2)
        var dot11 = v1.dot(v1)
        var dot12 = v1.dot(v2)
        var denom = dot00 * dot11 - dot01 * dot01
        if denom == 0:
            return None
        var inverse = 1 / denom
        var u = (dot11 * dot02 - dot01 * dot12) * inverse
        var v = (dot00 * dot12 - dot01 * dot02) * inverse
        return Vector3(1 - u - v, v, u)

    def contains_point(self, point: Vector3) raises -> Bool:
        """Return True if a point, projected onto the plane, lies inside
        or on the edge. three.js: `containsPoint`.

        Args:
            point: The point.

        Returns:
            Whether every barycentric weight is at least zero.

        Raises:
            Error: If the triangle is degenerate.
        """
        var weights = self.barycoord(point)
        return weights.x >= 0 and weights.y >= 0 and weights.z >= 0

    def interpolate(
        self, point: Vector3, at_a: Vector3, at_b: Vector3, at_c: Vector3
    ) raises -> Vector3:
        """Return a value mixed from three corner values by a point's
        barycentric weights. three.js: `getInterpolation`.

        Args:
            point: The point.
            at_a: The value at `a`.
            at_b: The value at `b`.
            at_c: The value at `c`.

        Returns:
            The mixed value.

        Raises:
            Error: If the triangle is degenerate.
        """
        var w = self.barycoord(point)
        return at_a * w.x + at_b * w.y + at_c * w.z

    def is_front_facing(self, direction: Vector3) -> Bool:
        """Return True if a ray along `direction` meets the front.
        three.js: `isFrontFacing`.

        Args:
            direction: The ray's direction.

        Returns:
            Whether the normal points against the direction.
        """
        return self.raw_normal().dot(direction) < 0

    def closest_point_to_point(self, point: Vector3) -> Vector3:
        """Return the point of the triangle nearest a point. three.js:
        `closestPointToPoint`.

        A point whose projection onto the plane falls inside answers with
        the projection. Any other point, and every point near a degenerate
        triangle, answers with the nearest point of the three edges.

        Args:
            point: The point.

        Returns:
            The nearest point, on the face, an edge or a corner.
        """
        var found = self._weights(point)
        if Bool(found):
            var w = found.value()
            if w.x >= 0 and w.y >= 0 and w.z >= 0:
                return self.a * w.x + self.b * w.y + self.c * w.z
        var best = _nearest_on_segment(point, self.a, self.b)
        var other = _nearest_on_segment(point, self.b, self.c)
        if _gap(other, point) < _gap(best, point):
            best = other
        other = _nearest_on_segment(point, self.c, self.a)
        if _gap(other, point) < _gap(best, point):
            best = other
        return best


def _gap(a: Vector3, b: Vector3) -> Float32:
    """Return the squared distance between two points."""
    var d = a - b
    return d.dot(d)


def _nearest_on_segment(
    point: Vector3, start: Vector3, end: Vector3
) -> Vector3:
    """Return the point of a segment nearest a point. A segment of no
    length answers with its one point."""
    var line = end - start
    var length_sq = line.dot(line)
    if length_sq == 0:
        return start
    var t = (point - start).dot(line) / length_sq
    return start + line * _unit(t)


@fieldwise_init
struct Line3(ImplicitlyCopyable):
    """A segment from `start` to `end`."""

    var start: Vector3
    var end: Vector3

    def delta(self) -> Vector3:
        """Return the segment as a vector, from start to end.

        Returns:
            `end - start`.
        """
        return self.end - self.start

    def center(self) -> Vector3:
        """Return the midpoint.

        Returns:
            Halfway from start to end.
        """
        return (self.start + self.end) * 0.5

    def distance(self) -> Float32:
        """Return the segment's length.

        Returns:
            The distance from start to end.
        """
        return self.delta().length()

    def at(self, t: Float32) -> Vector3:
        """Return the point a fraction `t` of the way along the line.

        Args:
            t: Zero at the start, one at the end. Outside that range the
                point lies on the line beyond the segment.

        Returns:
            The point.
        """
        return self.start + self.delta() * t

    def closest_point_parameter(
        self, point: Vector3, clamp: Bool
    ) raises -> Float32:
        """Return the fraction along the line of the point nearest a
        point. three.js: `closestPointToPointParameter`.

        Args:
            point: The point.
            clamp: True to keep the fraction within the segment.

        Returns:
            The fraction.

        Raises:
            Error: If the segment has no length.
        """
        var line = self.delta()
        var length_sq = line.dot(line)
        if length_sq == 0:
            raise Error("A segment of no length has no direction")
        var t = (point - self.start).dot(line) / length_sq
        if clamp:
            t = max(Float32(0), min(Float32(1), t))
        return t

    def closest_point(self, point: Vector3, clamp: Bool) raises -> Vector3:
        """Return the point of the line nearest a point. three.js:
        `closestPointToPoint`.

        Args:
            point: The point.
            clamp: True to keep the answer within the segment.

        Returns:
            The nearest point.

        Raises:
            Error: If the segment has no length.
        """
        return self.at(self.closest_point_parameter(point, clamp))

    def apply_matrix4(mut self, matrix: Matrix4):
        """Transform both ends.

        Args:
            matrix: The transform.
        """
        self.start = matrix.transform_point(self.start)
        self.end = matrix.transform_point(self.end)

    def distance_to_line(self, other: Line3) -> Float32:
        """Return the shortest distance between two segments. three.js:
        `distanceSqToLine3`, square-rooted.

        Ericson's closest points of two segments, 5.1.9, with each
        degenerate case handled on its own.

        Args:
            other: The other segment.

        Returns:
            The distance.
        """
        var d1 = self.delta()
        var d2 = other.delta()
        var r = self.start - other.start
        var a = d1.dot(d1)
        var e = d2.dot(d2)
        var f = d2.dot(r)
        var s = Float32(0)
        var t = Float32(0)
        if a == 0 and e == 0:
            return r.length()
        if a == 0:
            t = _unit(f / e)
        else:
            var c = d1.dot(r)
            if e == 0:
                s = _unit(-c / a)
            else:
                var b = d1.dot(d2)
                var denom = a * e - b * b
                s = _unit((b * f - c * e) / denom) if denom != 0 else 0
                t = (b * s + f) / e
                if t < 0:
                    t = 0
                    s = _unit(-c / a)
                elif t > 1:
                    t = 1
                    s = _unit((b - c) / a)
        var gap = (self.start + d1 * s) - (other.start + d2 * t)
        return sqrt(gap.dot(gap))


def _unit(value: Float32) -> Float32:
    """Return `value` limited to the range from zero to one."""
    return max(Float32(0), min(Float32(1), value))
