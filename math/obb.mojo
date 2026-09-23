# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An oriented bounding box, from three.js `examples/jsm/math/OBB.js`.

An oriented box is a box that can turn: a center, a half size along each of
its own axes, and a rotation that gives those axes. It bounds a turned
object more tightly than an axis-aligned `Box3` does, and two of them are
still quick to test against each other.

The tests are three.js's, from Christer Ericson's *Real-Time Collision
Detection*: the nearest point to a point (5.1.4), the separating axis test
of two boxes (4.4.1), and a box against a plane (5.2.3). A ray is carried
into the box's own frame and tested against an axis-aligned box there.

Like `Box3`, an oriented box holds bare `Float32` meters. The half sizes
must be zero or more and finite. The rotation must be a rotation: every
test reads its columns as the three unit axes of the box.

**Differences from three.js.**

- `intersects_plane` measures the signed distance as `Plane` defines it,
  `dot(normal, center) + constant`. three.js subtracts the constant, so it
  tests the plane mirrored through the origin.
- `apply_matrix4` moves the center by the whole matrix and turns the old
  rotation by the new one. three.js adds only the translation to the
  center, multiplies the rotations in the other order, and gives a negative
  half size under a mirror. The two agree for a box at the origin with no
  rotation, which is how three.js's example uses it.
- `from_box3` refuses an empty box, and `intersects_box3` says an empty box
  meets nothing. three.js makes a box of size zero at the origin from it.
"""

from math.bounds import Box3, Plane, Sphere
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4
from math.ray import Ray
from math.vector3 import Vector3
from std.math import isfinite, max, min

# three.js's default `epsilon` for `intersectsOBB`: JavaScript's
# `Number.EPSILON`, the gap between one and the next `Float64`.
comptime OBB_EPSILON = Float32(2.220446049250313e-16)


def _clamp(value: Float32, low: Float32, high: Float32) -> Float32:
    """Return three.js's `MathUtils.clamp`, `max(low, min(high, value))`.

    Args:
        value: The number.
        low: The smallest answer.
        high: The largest answer.

    Returns:
        The clamped number.
    """
    return max(low, min(high, value))


def _check_half_size(half_size: Vector3) raises:
    """Refuse a half size that is negative or not finite.

    Args:
        half_size: The half size.

    Raises:
        Error: If a component is negative or not finite.
    """
    var good = (
        isfinite(half_size.x)
        and isfinite(half_size.y)
        and isfinite(half_size.z)
        and half_size.x >= 0
        and half_size.y >= 0
        and half_size.z >= 0
    )
    if not good:
        raise Error("An OBB's half size must be finite and not negative")


struct OBB(ImplicitlyCopyable):
    """A box with its own axes. three.js: `OBB`."""

    var center: Vector3
    # Half the box's extent along each of its own axes.
    var half_size: Vector3
    # The box's axes, as the columns of a rotation.
    var rotation: Matrix3

    def __init__(out self):
        """Create three.js's default box: a point at the origin, unturned."""
        self.center = Vector3(0, 0, 0)
        self.half_size = Vector3(0, 0, 0)
        self.rotation = Matrix3()

    def __init__(
        out self, center: Vector3, half_size: Vector3, rotation: Matrix3
    ) raises:
        """Create a box. three.js: the constructor and `set`.

        Args:
            center: The middle of the box.
            half_size: Half its extent along each of its axes, in meters.
            rotation: Its axes, as the columns of a rotation.

        Raises:
            Error: If a half size is negative or not finite.
        """
        _check_half_size(half_size)
        self.center = center
        self.half_size = half_size
        self.rotation = rotation

    @staticmethod
    def from_box3(box: Box3) raises -> OBB:
        """Return the oriented box that is an axis-aligned box. three.js:
        `fromBox3`.

        Args:
            box: The box.

        Returns:
            The same box, unturned.

        Raises:
            Error: If the box is empty, which has no center, or reaches to
                infinity.
        """
        if box.is_empty():
            raise Error("An empty box has no oriented box")
        return OBB(box.center(), box.size() * 0.5, Matrix3())

    def __eq__(self, other: Self) -> Bool:
        """Return whether two boxes are the same, exactly. three.js:
        `equals`.

        Args:
            other: The other box.

        Returns:
            Whether the centers, half sizes and rotations are equal.
        """
        return (
            self.center.x == other.center.x
            and self.center.y == other.center.y
            and self.center.z == other.center.z
            and self.half_size.x == other.half_size.x
            and self.half_size.y == other.half_size.y
            and self.half_size.z == other.half_size.z
            and self.rotation == other.rotation
        )

    def __ne__(self, other: Self) -> Bool:
        """Return whether two boxes differ.

        Args:
            other: The other box.

        Returns:
            Whether any part differs.
        """
        return not (self == other)

    def axis(self, index: Int) raises -> Vector3:
        """Return one of the box's axes. three.js: `extractBasis`.

        Args:
            index: 0 for x, 1 for y, 2 for z.

        Returns:
            The column of the rotation.

        Raises:
            Error: If the index is not 0, 1 or 2.
        """
        if index < 0 or index > 2:
            raise Error("An OBB has three axes")
        ref e = self.rotation.elements
        return Vector3(e[index * 3], e[index * 3 + 1], e[index * 3 + 2])

    def size(self) -> Vector3:
        """Return the box's full extent along each of its axes. three.js:
        `getSize`.

        Returns:
            Twice the half size.
        """
        return self.half_size * 2

    def clamp_point(self, point: Vector3) -> Vector3:
        """Return the point of the box nearest a point. three.js:
        `clampPoint`.

        Args:
            point: The point.

        Returns:
            The point itself if it is inside, else the nearest point of the
            surface.
        """
        ref e = self.rotation.elements
        var x_axis = Vector3(e[0], e[1], e[2])
        var y_axis = Vector3(e[3], e[4], e[5])
        var z_axis = Vector3(e[6], e[7], e[8])
        var v1 = point - self.center
        var target = self.center
        var x = _clamp(v1.dot(x_axis), -self.half_size.x, self.half_size.x)
        target.add(x_axis * x)
        var y = _clamp(v1.dot(y_axis), -self.half_size.y, self.half_size.y)
        target.add(y_axis * y)
        var z = _clamp(v1.dot(z_axis), -self.half_size.z, self.half_size.z)
        target.add(z_axis * z)
        return target

    def contains_point(self, point: Vector3) -> Bool:
        """Return whether a point is in the box, its faces included.
        three.js: `containsPoint`.

        Args:
            point: The point.

        Returns:
            Whether it is inside.
        """
        ref e = self.rotation.elements
        var v1 = point - self.center
        return (
            abs(v1.dot(Vector3(e[0], e[1], e[2]))) <= self.half_size.x
            and abs(v1.dot(Vector3(e[3], e[4], e[5]))) <= self.half_size.y
            and abs(v1.dot(Vector3(e[6], e[7], e[8]))) <= self.half_size.z
        )

    def intersects_box3(self, box: Box3) raises -> Bool:
        """Return whether an axis-aligned box meets this one. three.js:
        `intersectsBox3`.

        Args:
            box: The box.

        Returns:
            Whether they overlap. False for an empty box.

        Raises:
            Error: If the box reaches to infinity.
        """
        if box.is_empty():
            return False
        return self.intersects_obb(OBB.from_box3(box))

    def intersects_sphere(self, sphere: Sphere) -> Bool:
        """Return whether a sphere meets the box. three.js:
        `intersectsSphere`.

        Args:
            sphere: The sphere.

        Returns:
            Whether the point of the box nearest the sphere's center is
            within the radius. False for an empty sphere.
        """
        var gap = self.clamp_point(sphere.center) - sphere.center
        return gap.dot(gap) <= sphere.radius * sphere.radius and (
            sphere.radius >= 0
        )

    def intersects_obb(
        self, other: OBB, epsilon: Float32 = OBB_EPSILON
    ) -> Bool:
        """Return whether another oriented box meets this one. three.js:
        `intersectsOBB`.

        Ericson's separating axis test: two boxes are apart if and only if
        one of fifteen axes separates them. The axes are the three of each
        box and the nine cross products of one box's axis with the other's.

        Args:
            other: The other box.
            epsilon: A small number added to each term of the rotation
                between the boxes. It keeps two parallel edges, whose cross
                product is near zero, from separating boxes that touch.

        Returns:
            Whether no axis separates them.
        """
        var ae = self.half_size
        var be = other.half_size
        ref ea = self.rotation.elements
        ref eb = other.rotation.elements
        var a0 = Vector3(ea[0], ea[1], ea[2])
        var a1 = Vector3(ea[3], ea[4], ea[5])
        var a2 = Vector3(ea[6], ea[7], ea[8])
        var b0 = Vector3(eb[0], eb[1], eb[2])
        var b1 = Vector3(eb[3], eb[4], eb[5])
        var b2 = Vector3(eb[6], eb[7], eb[8])
        # R[i][j]: axis i of this box against axis j of the other.
        var r00 = a0.dot(b0)
        var r01 = a0.dot(b1)
        var r02 = a0.dot(b2)
        var r10 = a1.dot(b0)
        var r11 = a1.dot(b1)
        var r12 = a1.dot(b2)
        var r20 = a2.dot(b0)
        var r21 = a2.dot(b1)
        var r22 = a2.dot(b2)
        # The other box's center, in this box's frame.
        var v1 = other.center - self.center
        var t0 = v1.dot(a0)
        var t1 = v1.dot(a1)
        var t2 = v1.dot(a2)
        var q00 = abs(r00) + epsilon
        var q01 = abs(r01) + epsilon
        var q02 = abs(r02) + epsilon
        var q10 = abs(r10) + epsilon
        var q11 = abs(r11) + epsilon
        var q12 = abs(r12) + epsilon
        var q20 = abs(r20) + epsilon
        var q21 = abs(r21) + epsilon
        var q22 = abs(r22) + epsilon
        # L = A0, A1, A2.
        if abs(t0) > ae.x + (be.x * q00 + be.y * q01 + be.z * q02):
            return False
        if abs(t1) > ae.y + (be.x * q10 + be.y * q11 + be.z * q12):
            return False
        if abs(t2) > ae.z + (be.x * q20 + be.y * q21 + be.z * q22):
            return False
        # L = B0, B1, B2.
        if (
            abs(t0 * r00 + t1 * r10 + t2 * r20)
            > (ae.x * q00 + ae.y * q10 + ae.z * q20) + be.x
        ):
            return False
        if (
            abs(t0 * r01 + t1 * r11 + t2 * r21)
            > (ae.x * q01 + ae.y * q11 + ae.z * q21) + be.y
        ):
            return False
        if (
            abs(t0 * r02 + t1 * r12 + t2 * r22)
            > (ae.x * q02 + ae.y * q12 + ae.z * q22) + be.z
        ):
            return False
        # L = A0 x B0, A0 x B1, A0 x B2.
        if abs(t2 * r10 - t1 * r20) > (ae.y * q20 + ae.z * q10) + (
            be.y * q02 + be.z * q01
        ):
            return False
        if abs(t2 * r11 - t1 * r21) > (ae.y * q21 + ae.z * q11) + (
            be.x * q02 + be.z * q00
        ):
            return False
        if abs(t2 * r12 - t1 * r22) > (ae.y * q22 + ae.z * q12) + (
            be.x * q01 + be.y * q00
        ):
            return False
        # L = A1 x B0, A1 x B1, A1 x B2.
        if abs(t0 * r20 - t2 * r00) > (ae.x * q20 + ae.z * q00) + (
            be.y * q12 + be.z * q11
        ):
            return False
        if abs(t0 * r21 - t2 * r01) > (ae.x * q21 + ae.z * q01) + (
            be.x * q12 + be.z * q10
        ):
            return False
        if abs(t0 * r22 - t2 * r02) > (ae.x * q22 + ae.z * q02) + (
            be.x * q11 + be.y * q10
        ):
            return False
        # L = A2 x B0, A2 x B1, A2 x B2.
        if abs(t1 * r00 - t0 * r10) > (ae.x * q10 + ae.y * q00) + (
            be.y * q22 + be.z * q21
        ):
            return False
        if abs(t1 * r01 - t0 * r11) > (ae.x * q11 + ae.y * q01) + (
            be.x * q22 + be.z * q20
        ):
            return False
        if abs(t1 * r02 - t0 * r12) > (ae.x * q12 + ae.y * q02) + (
            be.x * q21 + be.y * q20
        ):
            return False
        return True

    def intersects_plane(self, plane: Plane) -> Bool:
        """Return whether a plane passes through the box. three.js:
        `intersectsPlane`, with the sign of the constant corrected: see the
        module docstring.

        Args:
            plane: The plane.

        Returns:
            Whether the center is within the box's reach of the plane.
        """
        ref e = self.rotation.elements
        var r = (
            self.half_size.x * abs(plane.normal.dot(Vector3(e[0], e[1], e[2])))
            + self.half_size.y
            * abs(plane.normal.dot(Vector3(e[3], e[4], e[5])))
            + self.half_size.z
            * abs(plane.normal.dot(Vector3(e[6], e[7], e[8])))
        )
        return abs(plane.distance_to_point(self.center)) <= r

    def _frame(self) -> Matrix4:
        """Return the matrix from the box's frame to the world: its rotation,
        then its center.

        Returns:
            The matrix.
        """
        ref e = self.rotation.elements
        var matrix = Matrix4()
        matrix.set(
            e[0],
            e[3],
            e[6],
            self.center.x,
            e[1],
            e[4],
            e[7],
            self.center.y,
            e[2],
            e[5],
            e[8],
            self.center.z,
            0,
            0,
            0,
            1,
        )
        return matrix^

    def intersect_ray(self, ray: Ray) raises -> Optional[Vector3]:
        """Return where a ray meets the box, or None. three.js:
        `intersectRay`.

        The ray is carried into the box's frame, met with the axis-aligned
        box there, and the point is carried back.

        Args:
            ray: The ray.

        Returns:
            The nearest point forward of the origin, or None for a miss.
            An origin inside the box meets it where the ray leaves.

        Raises:
            Error: If the rotation is singular. It has no inverse to carry
                the ray through.
        """
        var matrix = self._frame()
        var inverse = Matrix4(copy=matrix)
        inverse.invert()
        var local = ray
        local.apply_matrix4(inverse)
        var met = local.intersect_box(Box3(-self.half_size, self.half_size))
        if not Bool(met):
            return None
        return matrix.transform_point(met.value())

    def intersects_ray(self, ray: Ray) raises -> Bool:
        """Return whether a ray meets the box. three.js: `intersectsRay`.

        Args:
            ray: The ray.

        Returns:
            Whether it meets the box forward of its origin.

        Raises:
            Error: If the rotation is singular.
        """
        return Bool(self.intersect_ray(ray))

    def apply_matrix4(mut self, matrix: Matrix4) raises:
        """Carry the box through a transform. three.js: `applyMatrix4`.

        The scale of each column of the matrix scales the half size along
        the same axis, and the rotation left turns the box's axes. The
        answer is exact for a box with no rotation, or a matrix whose three
        scales are equal. Otherwise the transform shears the box, and no
        oriented box is exact.

        Args:
            matrix: An affine transform.

        Raises:
            Error: If the matrix projects, or flattens an axis to nothing.
        """
        if not matrix.is_affine():
            raise Error("An OBB can only be carried through an affine matrix")
        ref e = matrix.elements
        var sx = Vector3(e[0], e[1], e[2]).length()
        var sy = Vector3(e[4], e[5], e[6]).length()
        var sz = Vector3(e[8], e[9], e[10]).length()
        if sx == 0 or sy == 0 or sz == 0:
            raise Error("A transform that flattens an axis leaves no OBB")
        var mirror = sx
        if matrix.determinant() < 0:
            mirror = -sx
        var turn = Matrix3.from_matrix4(matrix)
        var inv_x = 1 / mirror
        var inv_y = 1 / sy
        var inv_z = 1 / sz
        turn.elements[0] *= inv_x
        turn.elements[1] *= inv_x
        turn.elements[2] *= inv_x
        turn.elements[3] *= inv_y
        turn.elements[4] *= inv_y
        turn.elements[5] *= inv_y
        turn.elements[6] *= inv_z
        turn.elements[7] *= inv_z
        turn.elements[8] *= inv_z
        self.rotation.premultiply(turn)
        self.half_size = Vector3(
            self.half_size.x * sx, self.half_size.y * sy, self.half_size.z * sz
        )
        self.center = matrix.transform_point(self.center)
