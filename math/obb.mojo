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
  axes through the new matrix, including reflections. three.js adds only
  the translation to the center, multiplies the rotations in the other order, and gives a negative
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
from std.math import isfinite, max, min, sqrt
from std.memory import bitcast

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


def _dot_roundoff(
    coefficients: Array[Float64, 3],
    magnitudes: Array[Float64, 3],
    offset: Float64,
) -> Float64:
    """Bound Float32 rounding in offset plus three scalar products.

    Each operation has error at most u times its exact magnitude plus half
    the smallest subnormal, where u = 2**-24. Propagate each error through
    later additions. Products by zero or signed one, and additions of zero,
    are exact. Fused multiply-add has no greater error than separate steps.
    """
    comptime u = Float64(5.960464477539063e-8)
    comptime tiny = Float64(7.006492321624085e-46)
    var total = abs(offset)
    var products_error = Float64(0)
    var nonzero = Int(offset != 0)
    for row in range(3):  # pragma: no branch
        var factor = abs(coefficients[row])
        var term = factor * magnitudes[row]
        if factor != 1 and term > 0:
            products_error += u * term + tiny
        if term > 0:
            nonzero += 1
        total += term
    # Any ordering of n additions has gamma_n = n*u/(1-n*u). This
    # also covers compiler reassociation and contraction into FMA.
    var additions = Float64(max(0, nonzero - 1))
    return (products_error + additions * (u * total + tiny)) / (
        1 - additions * u
    )


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

        Transform the box's own axes, then normalize them. Reverse the
        first axis when needed to keep a proper rotation. Half sizes stay
        nonnegative. Nonuniform scale is supported only when the transformed
        axes stay perpendicular. A shear that changes their right angles
        is refused, rather than approximated by a box. Normalized axis dot
        products can differ from zero by at most 1e-6 before correction.

        Each half size bounds the geometric image plus Float32 roundoff in
        point formation, transformation, center subtraction and projection.
        The bound uses absolute products, unit roundoff 2**-24 and half the
        smallest subnormal, then rounds outward. Cancellation can require a
        larger allowance for a thin box beside large coordinates. Exact
        signed permutations of axis-aligned boxes at the origin keep exact
        extents.

        Args:
            matrix: A finite affine transform with nonzero box axes.

        Raises:
            Error: If an input is nonfinite, the matrix projects, an axis
                collapses, the transformed axes are not perpendicular within
                1e-6, a positive half size underflows, or a center, half size or
                conservative bound overflows Float32. The box stays unchanged.
        """
        if not matrix.is_affine():
            raise Error("An OBB can only be carried through an affine matrix")
        if not matrix.is_finite():
            raise Error("An OBB transform must be finite")
        _check_half_size(self.half_size)
        var center: Array[Float32, 3] = [
            self.center.x,
            self.center.y,
            self.center.z,
        ]
        # Three center components and nine rotation entries are always present.
        for row in range(3):  # pragma: no branch
            if not isfinite(center[row]):
                raise Error("An OBB center must be finite")
        for index in range(9):  # pragma: no branch
            if not isfinite(self.rotation.elements[index]):
                raise Error("An OBB rotation must be finite")
        # Widen before multiplication: even the largest finite Float32 axes
        # and their squared lengths fit in Float64. Tiny scales stay nonzero.
        var axes = Array[Float64, 9](fill=0)
        var lengths = Array[Float64, 3](fill=0)
        var transformed = Array[Float64, 9](fill=0)
        for column in range(3):  # pragma: no branch
            for row in range(3):  # pragma: no branch
                for lane in range(3):  # pragma: no branch
                    axes[column * 3 + row] += Float64(
                        matrix.elements[lane * 4 + row]
                    ) * Float64(self.rotation.elements[column * 3 + lane])
            var at = column * 3
            lengths[column] = sqrt(
                axes[at] * axes[at]
                + axes[at + 1] * axes[at + 1]
                + axes[at + 2] * axes[at + 2]
            )
            if lengths[column] == 0:
                raise Error("A transform that flattens an axis leaves no OBB")
            for row in range(3):  # pragma: no branch
                transformed[at + row] = axes[at + row]
                axes[at + row] /= lengths[column]
        # Test the image of the box, not the matrix columns: nonuniform
        # world scale can shear an already rotated box.
        for first in range(2):  # pragma: no branch
            for second in range(first + 1, 3):  # pragma: no branch
                var dot = Float64(0)
                for row in range(3):  # pragma: no branch
                    dot += axes[first * 3 + row] * axes[second * 3 + row]
                if abs(dot) > 1e-6:
                    raise Error("An OBB transform cannot shear its axes")
        # Remove accepted Float32 orthogonality drift before storing a proper
        # frame. The support bound below accounts for this rounding correction.
        var xy = axes[0] * axes[3] + axes[1] * axes[4] + axes[2] * axes[5]
        for row in range(3):  # pragma: no branch
            axes[3 + row] -= xy * axes[row]
        var y_length = sqrt(
            axes[3] * axes[3] + axes[4] * axes[4] + axes[5] * axes[5]
        )
        for row in range(3):  # pragma: no branch
            axes[3 + row] /= y_length
        var cross: Array[Float64, 3] = [
            axes[1] * axes[5] - axes[2] * axes[4],
            axes[2] * axes[3] - axes[0] * axes[5],
            axes[0] * axes[4] - axes[1] * axes[3],
        ]
        var handedness = (
            cross[0] * axes[6] + cross[1] * axes[7] + cross[2] * axes[8]
        )
        # The signs of individual axes do not change a centered box. Flip
        # only after applying the matrix to the old axes, never before it.
        if handedness < 0:
            for row in range(3):  # pragma: no branch
                axes[row] = -axes[row]
                cross[row] = -cross[row]
        var turn = Matrix3()
        for row in range(3):  # pragma: no branch
            turn.elements[row] = Float32(axes[row])
            turn.elements[3 + row] = Float32(axes[3 + row])
            turn.elements[6 + row] = Float32(cross[row])
        var half_size = Vector3(
            Float32(Float64(self.half_size.x) * lengths[0]),
            Float32(Float64(self.half_size.y) * lengths[1]),
            Float32(Float64(self.half_size.z) * lengths[2]),
        )
        _check_half_size(half_size)
        for column in range(3):  # pragma: no branch
            if (
                self.half_size.get_component(column) > 0
                and half_size.get_component(column) == 0
            ):
                raise Error("An OBB transformed half size underflows Float32")
        var moved = Array[Float32, 3](fill=0)
        var exact_center = Array[Float64, 3](fill=0)
        for row in range(3):  # pragma: no branch
            var value = Float64(matrix.elements[12 + row])
            for lane in range(3):  # pragma: no branch
                value += Float64(matrix.elements[lane * 4 + row]) * Float64(
                    center[lane]
                )
            exact_center[row] = value
            moved[row] = Float32(value)
            if not isfinite(moved[row]):
                raise Error("An OBB transformed center must fit in Float32")
        # Keep geometry and rounding separate. A world point made from the
        # old center and local coordinates has a bounded formation error.
        # Carry it through the matrix, then bound center subtraction and the
        # contains_point dot. Absolute-product sums cover cancellation even
        # when the box is extremely thin along one of its axes.
        comptime u = Float64(5.960464477539063e-8)
        comptime tiny = Float64(7.006492321624085e-46)
        comptime largest = Float64(3.4028234663852886e38)
        var old_extents: Array[Float64, 3] = [
            Float64(self.half_size.x),
            Float64(self.half_size.y),
            Float64(self.half_size.z),
        ]
        var source_bound = Array[Float64, 3](fill=0)
        var source_error = Array[Float64, 3](fill=0)
        for row in range(3):  # pragma: no branch
            var coefficients = Array[Float64, 3](fill=0)
            source_bound[row] = abs(Float64(center[row]))
            for column in range(3):  # pragma: no branch
                coefficients[column] = Float64(
                    self.rotation.elements[column * 3 + row]
                )
                source_bound[row] += (
                    abs(coefficients[column]) * old_extents[column]
                )
            source_error[row] = _dot_roundoff(
                coefficients, old_extents, Float64(center[row])
            )
            source_bound[row] += source_error[row]
            if source_bound[row] > largest:
                raise Error("An OBB source corner bound must fit in Float32")
        var offset_bound = Array[Float64, 3](fill=0)
        var offset_error = Array[Float64, 3](fill=0)
        for row in range(3):  # pragma: no branch
            var coefficients = Array[Float64, 3](fill=0)
            var point_bound = abs(Float64(matrix.elements[12 + row]))
            for lane in range(3):  # pragma: no branch
                coefficients[lane] = Float64(matrix.elements[lane * 4 + row])
                point_bound += abs(coefficients[lane]) * source_bound[lane]
                offset_error[row] += (
                    abs(coefficients[lane]) * source_error[lane]
                )
                offset_bound[row] += (
                    abs(transformed[lane * 3 + row]) * old_extents[lane]
                )
            var point_error = _dot_roundoff(
                coefficients, source_bound, Float64(matrix.elements[12 + row])
            )
            if point_bound + point_error > largest:
                raise Error(
                    "An OBB transformed corner bound must fit in Float32"
                )
            offset_error[row] += point_error + abs(
                Float64(moved[row]) - exact_center[row]
            )
            if moved[row] != 0:
                offset_error[row] += (
                    u * (point_bound + point_error + abs(Float64(moved[row])))
                    + tiny
                )
            offset_bound[row] += offset_error[row]
        var extents = Array[Float32, 3](fill=0)
        for column in range(3):  # pragma: no branch
            var coefficients = Array[Float64, 3](fill=0)
            var bound = Float64(0)
            var projection_magnitude = Float64(0)
            for row in range(3):  # pragma: no branch
                coefficients[row] = Float64(turn.elements[column * 3 + row])
                bound += abs(coefficients[row]) * offset_error[row]
                projection_magnitude += (
                    abs(coefficients[row]) * offset_bound[row]
                )
            # Exact geometric support in the stored (rounded) frame. This
            # also accounts for the accepted orthogonality correction.
            for other in range(3):  # pragma: no branch
                var dot = Float64(0)
                for row in range(3):  # pragma: no branch
                    dot += coefficients[row] * transformed[other * 3 + row]
                bound += abs(dot) * old_extents[other]
            var roundoff = _dot_roundoff(coefficients, offset_bound, 0)
            bound += roundoff
            # The error model requires finite intermediate dot products too.
            # A large cancelling sum cannot borrow safety from a small result.
            if max(bound, projection_magnitude + roundoff) > largest:
                raise Error("An OBB projection bound must fit in Float32")
            extents[column] = Float32(bound)
            # Round only an inexact downward conversion outward. The checked
            # bound cannot require a step past the largest finite Float32.
            if Float64(extents[column]) < bound:
                var bits = bitcast[DType.uint32](extents[column])
                extents[column] = bitcast[DType.float32](bits + 1)
        var moved_center = Vector3(moved[0], moved[1], moved[2])
        # Commit only after every candidate value has passed its checks.
        self.rotation = turn
        self.half_size = Vector3(extents[0], extents[1], extents[2])
        self.center = moved_center
