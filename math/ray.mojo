# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A ray, from three.js `src/math/Ray.js`.

A point and a unit direction: the half-line that starts at the origin and
goes the direction's way forever. It is what a click is once it leaves the
screen, and what `core.raycaster` carries through a scene asking each mesh
whether it is hit. The questions a ray answers are the ones a picker asks:
where along it a sphere, a box, a plane or a triangle is met, and how far
a point is from it.

The direction is unit length, and the constructor makes it so, because
every answer below assumes it: `at(t)` is `t` meters along the ray only
when the direction is one meter long, and the distances and the sphere
test are dot products that lean on the same thing. three.js leaves the
normalizing to the caller and says so in a comment; here a zero direction
is refused, since there is no way to point it.

A hit is an `Optional`. A ray that misses has no point to give, and a
point picked to mean "none" would be a point somewhere. three.js returns
`null` for the same reason. `intersect_*` gives the point and
`intersects_*` gives only whether, because the second is cheaper and is
asked more often.

Every point in a hit is *forward* of the origin. A ray is a half-line: a
sphere behind the origin is not hit, and a plane behind it is not met,
even though the line through both would cross them. An origin inside a
sphere hits it where the ray leaves; an origin inside a box hits where the
ray leaves it too, as three.js's does.

Like `Vector3` and the bounds, a ray holds bare `Float32` meters. The
`Raycaster` is the edge where the units live.
"""

from math.bounds import Box3, Plane, Sphere
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.math import isnan, sqrt


def _stretch(
    low: Float32, high: Float32, origin: Float32, direction: Float32
) -> Tuple[Float32, Float32]:
    """Return where along a ray it lies between two parallel faces, as the
    distance it enters and the distance it leaves.

    Each face's offset from the origin is divided by the direction's
    component along the axis, and the two are ordered by the sign of that
    component so the entry comes first. A component of zero divides to an
    infinite reciprocal, which is what the slab test wants: the ray is
    between the faces for all of `t` or none of it. A face the origin sits
    on exactly then multiplies zero by infinity, which is not a number, and
    the caller takes that end from another axis.

    Args:
        low: The face with the smaller coordinate.
        high: The face with the larger.
        origin: The ray's origin along this axis.
        direction: The ray's direction along this axis.

    Returns:
        The entry distance and the exit distance.
    """
    var inverse = 1 / direction
    if inverse >= 0:
        return ((low - origin) * inverse, (high - origin) * inverse)
    return ((high - origin) * inverse, (low - origin) * inverse)


struct Ray(ImplicitlyCopyable):
    """A half-line: an origin and the unit direction it leaves in."""

    var origin: Vector3
    var direction: Vector3

    def __init__(out self, origin: Vector3, direction: Vector3) raises:
        """Create a ray, making the direction unit length.

        Args:
            origin: Where the ray starts.
            direction: Which way it goes; any length but zero.

        Raises:
            Error: If the direction has no length: no way to point, no ray.
        """
        if direction.length() == 0:
            raise Error("A ray needs a direction with some length")
        var unit = direction
        unit.normalize()
        self.origin = origin
        self.direction = unit

    def at(self, t: Float32) -> Vector3:
        """Return the point `t` meters along this ray, three.js's `at`.

        Args:
            t: How far from the origin. Negative is behind it, where no
                hit ever is but a caller can still ask.

        Returns:
            The point.
        """
        return self.origin + self.direction * t

    def look_at(mut self, target: Vector3) raises:
        """Point this ray at `target`, three.js's `lookAt`.

        Args:
            target: The point to aim at.

        Raises:
            Error: If the target is the origin itself, which is no
                direction.
        """
        var toward = target - self.origin
        if toward.length() == 0:
            raise Error("A ray cannot look at its own origin")
        toward.normalize()
        self.direction = toward

    def recast(mut self, t: Float32):
        """Move the origin `t` meters along the ray, three.js's `recast`:
        the same line, started later.

        Args:
            t: How far to move the origin.
        """
        self.origin = self.at(t)

    def closest_point_to_point(self, point: Vector3) -> Vector3:
        """Return the point of this ray nearest `point`, three.js's
        `closestPointToPoint`.

        The foot of the perpendicular from the point onto the line, unless
        it falls behind the origin, where the ray does not go: then the
        origin, which is the nearest the ray comes.

        Args:
            point: The point to approach.

        Returns:
            The nearest point on the ray.
        """
        var along = (point - self.origin).dot(self.direction)
        if along < 0:
            return self.origin
        return self.at(along)

    def distance_sq_to_point(self, point: Vector3) -> Float32:
        """Return the squared distance from `point` to this ray, three.js's
        `distanceSqToPoint`.

        Args:
            point: The point to measure from.

        Returns:
            The square of the distance to the nearest point of the ray.
        """
        var gap = self.closest_point_to_point(point) - point
        return gap.dot(gap)

    def distance_to_point(self, point: Vector3) -> Float32:
        """Return how far `point` is from this ray, three.js's
        `distanceToPoint`.

        Args:
            point: The point to measure from.

        Returns:
            The distance to the nearest point of the ray.
        """
        return sqrt(self.distance_sq_to_point(point))

    def intersect_sphere(self, sphere: Sphere) -> Optional[Vector3]:
        """Return where this ray first meets `sphere`, three.js's
        `intersectSphere`, or None if it misses.

        The center is dropped onto the ray. The drop's square, against the
        radius squared, says whether the line through the ray crosses the
        sphere at all, and the two crossings sit either side of the foot.
        The nearer crossing is the hit, unless it is behind the origin: an
        origin inside the sphere hits where the ray leaves it, and a sphere
        wholly behind the origin is not hit at all. An empty sphere is hit
        nowhere, rather than its negative radius squaring to a real one.

        Args:
            sphere: The sphere.

        Returns:
            The first point of the sphere the ray reaches, or None.
        """
        if sphere.is_empty():
            return None
        var toward = sphere.center - self.origin
        var foot = toward.dot(self.direction)
        # The drop from the center to the line, as a vector and then
        # squared, rather than as the difference of two squared lengths
        # as three.js has it: for a sphere ten kilometers off, those two
        # agree to every digit a Float32 has, and the two meters that
        # decide the miss are rounded away. This is the drop
        # `intersects_sphere` measures, so the two answers agree.
        var drop = toward - self.direction * foot
        var drop_sq = drop.dot(drop)
        var radius_sq = sphere.radius * sphere.radius
        if drop_sq > radius_sq:
            return None
        var half = sqrt(radius_sq - drop_sq)
        var entering = foot - half
        var leaving = foot + half
        if leaving < 0:
            return None
        if entering < 0:
            return self.at(leaving)
        return self.at(entering)

    def intersects_sphere(self, sphere: Sphere) -> Bool:
        """Return True if this ray meets `sphere`, three.js's
        `intersectsSphere`. An empty sphere is met nowhere.

        Args:
            sphere: The sphere.

        Returns:
            Whether any point of the ray is inside or on it.
        """
        if sphere.is_empty():
            return False
        return (
            self.distance_sq_to_point(sphere.center)
            <= sphere.radius * sphere.radius
        )

    def distance_to_plane(self, plane: Plane) -> Optional[Float32]:
        """Return how far along this ray `plane` is met, three.js's
        `distanceToPlane`, or None if it is not.

        A ray parallel to the plane meets it nowhere, unless it lies in it,
        where every point is on the plane and the distance is zero. A ray
        pointing away from the plane would meet it behind the origin, which
        is not on the ray.

        Args:
            plane: The plane.

        Returns:
            The distance from the origin to the plane along the ray, or
            None.
        """
        var toward = plane.normal.dot(self.direction)
        if toward == 0:
            if plane.distance_to_point(self.origin) == 0:
                return Float32(0)
            return None
        var t = -plane.distance_to_point(self.origin) / toward
        if t < 0:
            return None
        return t

    def intersect_plane(self, plane: Plane) -> Optional[Vector3]:
        """Return where this ray meets `plane`, three.js's
        `intersectPlane`, or None if it does not.

        Args:
            plane: The plane.

        Returns:
            The point, or None. A ray lying in the plane meets it at its
            origin.
        """
        var t = self.distance_to_plane(plane)
        if not Bool(t):
            return None
        return self.at(t.value())

    def intersects_plane(self, plane: Plane) -> Bool:
        """Return True if this ray meets `plane`, three.js's
        `intersectsPlane`: it starts on the plane, or it starts on one side
        and points toward the other.

        Args:
            plane: The plane.

        Returns:
            Whether the ray reaches the plane.
        """
        var height = plane.distance_to_point(self.origin)
        if height == 0:
            return True
        return plane.normal.dot(self.direction) * height < 0

    def intersect_box(self, box: Box3) -> Optional[Vector3]:
        """Return where this ray enters `box`, three.js's `intersectBox`,
        or None if it misses.

        The slab test. Along each axis the ray is between the box's two
        faces for one stretch of `t`, and the box is hit where the three
        stretches overlap, if they do. The nearer end of the overlap is the
        entry, unless it is behind the origin, where the ray started
        inside: then the far end, where the ray leaves. A box wholly behind
        the origin is missed, and so is the empty box.

        A direction of zero along an axis, with the origin on one of that
        axis's faces, gives an end of the stretch that is not a number; see
        `_stretch`. That end is taken from the other axes instead, as
        three.js takes it.

        Args:
            box: The box.

        Returns:
            The first point of the box the ray reaches, or None.
        """
        if box.is_empty():
            return None
        var x = _stretch(box.min.x, box.max.x, self.origin.x, self.direction.x)
        var y = _stretch(box.min.y, box.max.y, self.origin.y, self.direction.y)
        var z = _stretch(box.min.z, box.max.z, self.origin.z, self.direction.z)
        var near = x[0]
        var far = x[1]
        if near > y[1] or y[0] > far:
            return None
        if y[0] > near or isnan(near):
            near = y[0]
        if y[1] < far or isnan(far):
            far = y[1]
        if near > z[1] or z[0] > far:
            return None
        if z[0] > near or isnan(near):
            near = z[0]
        if z[1] < far or isnan(far):
            far = z[1]
        if far < 0:
            return None
        if near >= 0:
            return self.at(near)
        return self.at(far)

    def intersects_box(self, box: Box3) -> Bool:
        """Return True if this ray meets `box`, three.js's `intersectsBox`.

        Args:
            box: The box.

        Returns:
            Whether the ray reaches it. False for the empty box.
        """
        return Bool(self.intersect_box(box))

    def intersect_triangle(
        self, a: Vector3, b: Vector3, c: Vector3, cull_back: Bool
    ) -> Optional[Vector3]:
        """Return where this ray meets the triangle `a`, `b`, `c`,
        three.js's `intersectTriangle`, or None if it misses.

        The triangle's front is the side it winds counter-clockwise from,
        as everywhere in this project. With `cull_back` set, a ray reaching
        it from behind passes through, which is what a `FRONT_SIDE`
        material wants: a pick lands on what is drawn.

        three.js's arithmetic, which is a Moller-Trumbore test written as
        three signed volumes: the ray's direction against the triangle's
        normal says which side it comes from and scales the rest; the
        origin's offset from `a`, crossed with each edge, says whether the
        hit is inside each of two edges; and their sum against the whole
        says whether it is inside the third. A hit behind the origin is a
        miss. A ray in the triangle's plane misses it, and so does a
        degenerate triangle, since neither has a normal to be on a side of.

        Args:
            a: First corner.
            b: Second corner.
            c: Third corner.
            cull_back: Whether a hit from behind counts as a miss.

        Returns:
            The point, or None.
        """
        var edge1 = b - a
        var edge2 = c - a
        var normal = edge1
        normal.cross(edge2)
        var d_dot_n = self.direction.dot(normal)
        var sign = Float32(1)
        if d_dot_n > 0:
            if cull_back:
                return None
        elif d_dot_n < 0:
            sign = -1
            d_dot_n = -d_dot_n
        else:
            return None
        var diff = self.origin - a
        var diff_x_edge2 = diff
        diff_x_edge2.cross(edge2)
        var d_dot_qxe2 = sign * self.direction.dot(diff_x_edge2)
        if d_dot_qxe2 < 0:
            return None
        var edge1_x_diff = edge1
        edge1_x_diff.cross(diff)
        var d_dot_e1xq = sign * self.direction.dot(edge1_x_diff)
        if d_dot_e1xq < 0:
            return None
        if d_dot_qxe2 + d_dot_e1xq > d_dot_n:
            return None
        var q_dot_n = -sign * diff.dot(normal)
        if q_dot_n < 0:
            return None
        return self.at(q_dot_n / d_dot_n)

    def apply_matrix4(mut self, matrix: Matrix4) raises:
        """Carry this ray through `matrix`, three.js's `applyMatrix4`: the
        origin as a point, the direction as a direction, made unit again.

        A raycaster does this with the inverse of a mesh's world matrix, so
        that the mesh's own triangles can be tested where they are stored.

        Args:
            matrix: The transform. Affine: it moves, turns, scales or
                shears, and keeps `w` at one.

        Raises:
            Error: If the matrix projects, since a direction has no image
                under one, or flattens the direction to nothing, which
                leaves the ray no way to point.
        """
        if not matrix.is_affine():
            raise Error("A ray can only be carried through an affine matrix")
        var direction = matrix.transform_direction(self.direction)
        if direction.length() == 0:
            raise Error(
                "A transform that flattens the ray's direction leaves it no"
                " way to point"
            )
        direction.normalize()
        self.origin = matrix.transform_point(self.origin)
        self.direction = direction
