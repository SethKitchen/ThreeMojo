# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A 4D vector, ported from three.js `src/math/Vector4.js`.

The fourth component is what a `Matrix4` multiplies but a `Vector3` cannot
carry: a position has `w = 1`, a direction `w = 0`, and a point that has
been through a projection has whatever the matrix's bottom row made of it.
`Matrix4.transform_point` builds that `w`, divides by it and throws it
away, and `transform_w` hands it back on its own; `apply_matrix4` here is
the product in full, which is the form a clip-space coordinate has.

Everything else is `Vector3` with one more component. The mutating methods
change the vector in place, as three.js's do, and the operators return a
new one.

Two setters put a rotation into the four numbers as an axis and an angle:
`set_axis_angle_from_quaternion` and `set_axis_angle_from_rotation_matrix`.
The axis goes into `x`, `y` and `z`, and the angle, in radians, into `w`;
`axis_angle` reads the angle back as an `Angle`. The arithmetic, its
thresholds and its fallback axes are three.js's.
"""

from math.matrix4 import Matrix4
from math.quaternion import Quaternion
from math.vector3 import Vector3, _js_round
from std.math import acos, ceil, floor, pi, sqrt, trunc
from units.si import Angle, RADIAN

# How far apart two mirrored entries of a rotation matrix can be for it to
# count as symmetric, which is a turn of nothing or of a half turn:
# three.js's `epsilon` in `setAxisAngleFromRotationMatrix`.
comptime _SYMMETRY_EPSILON = Float32(0.01)
# How near the identity a symmetric matrix must be to count as no turn:
# three.js's `epsilon2`.
comptime _IDENTITY_EPSILON = Float32(0.1)
# The component three.js gives a half turn's axis when the largest
# diagonal entry is too small to divide by: its literal, not the exact
# square root of a half.
comptime _HALF_ROOT_TWO = Float32(0.707106781)


def _is_symmetric(m: Matrix4) -> Bool:
    """Return True if the upper 3x3 of `m` equals its transpose to within
    three.js's `epsilon`."""
    ref e = m.elements
    return (
        abs(e[4] - e[1]) < _SYMMETRY_EPSILON
        and abs(e[8] - e[2]) < _SYMMETRY_EPSILON
        and abs(e[9] - e[6]) < _SYMMETRY_EPSILON
    )


def _is_near_identity(m: Matrix4) -> Bool:
    """Return True if a symmetric upper 3x3 is the identity to within
    three.js's `epsilon2`."""
    ref e = m.elements
    return (
        abs(e[4] + e[1]) < _IDENTITY_EPSILON
        and abs(e[8] + e[2]) < _IDENTITY_EPSILON
        and abs(e[9] + e[6]) < _IDENTITY_EPSILON
        and abs(e[0] + e[5] + e[10] - 3) < _IDENTITY_EPSILON
    )


def _is_largest(a: Float32, b: Float32, c: Float32) -> Bool:
    """Return True if `a` is above both `b` and `c`."""
    return a > b and a > c


@fieldwise_init
struct Vector4(Equatable, ImplicitlyCopyable):
    """A point or direction in homogeneous coordinates."""

    var x: Float32
    var y: Float32
    var z: Float32
    var w: Float32

    def __init__(out self, *, of: Vector3, w: Float32 = 1.0):
        """Create a vector from a `Vector3` and a fourth component.

        Args:
            of: The first three components.
            w: The fourth. One for a position, zero for a direction.
        """
        self.x = of.x
        self.y = of.y
        self.z = of.z
        self.w = w

    def xyz(self) -> Vector3:
        """Return the first three components, the fourth dropped."""
        return Vector3(self.x, self.y, self.z)

    def dot(self, other: Self) -> Float32:
        """Return the dot product of `self` and `other`.

        Args:
            other: The other vector.

        Returns:
            The dot product, all four components in.
        """
        return (
            self.x * other.x
            + self.y * other.y
            + self.z * other.z
            + self.w * other.w
        )

    def length(self) -> Float32:
        """Return the Euclidean length of the vector, all four components
        in."""
        return sqrt(self.dot(self))

    def add(mut self, other: Self):
        """Add `other` into `self`, component-wise.

        Args:
            other: The vector to add.
        """
        self.x += other.x
        self.y += other.y
        self.z += other.z
        self.w += other.w

    def sub(mut self, other: Self):
        """Subtract `other` from `self`, component-wise.

        Args:
            other: The vector to subtract.
        """
        self.x -= other.x
        self.y -= other.y
        self.z -= other.z
        self.w -= other.w

    def normalize(mut self):
        """Scale `self` to unit length, leaving a zero vector unchanged."""
        var magnitude = self.length()
        if magnitude > 0:
            self.x /= magnitude
            self.y /= magnitude
            self.z /= magnitude
            self.w /= magnitude

    def apply_matrix4(mut self, matrix: Matrix4):
        """Multiply `self` by `matrix`, three.js's `applyMatrix4`.

        The whole product, with nothing divided: a position that goes
        through a projection comes out with the clip-space `w` still in its
        fourth component, which is what `Matrix4.transform_point` divides
        by and `transform_w` reports.

        Args:
            matrix: The matrix to apply.
        """
        ref e = matrix.elements
        var x = self.x
        var y = self.y
        var z = self.z
        var w = self.w
        self.x = e[0] * x + e[4] * y + e[8] * z + e[12] * w
        self.y = e[1] * x + e[5] * y + e[9] * z + e[13] * w
        self.z = e[2] * x + e[6] * y + e[10] * z + e[14] * w
        self.w = e[3] * x + e[7] * y + e[11] * z + e[15] * w

    def __add__(self, other: Self) -> Self:
        """Return the component-wise sum.

        Args:
            other: The vector to add.

        Returns:
            A new vector.
        """
        return Vector4(
            self.x + other.x,
            self.y + other.y,
            self.z + other.z,
            self.w + other.w,
        )

    def __sub__(self, other: Self) -> Self:
        """Return the component-wise difference.

        Args:
            other: The vector to subtract.

        Returns:
            A new vector.
        """
        return Vector4(
            self.x - other.x,
            self.y - other.y,
            self.z - other.z,
            self.w - other.w,
        )

    def __mul__(self, factor: Float32) -> Self:
        """Return this vector scaled by a number.

        Args:
            factor: The scale.

        Returns:
            A new vector.
        """
        return Vector4(
            self.x * factor, self.y * factor, self.z * factor, self.w * factor
        )

    def __neg__(self) -> Self:
        """Return this vector pointing the other way."""
        return Vector4(-self.x, -self.y, -self.z, -self.w)

    def __truediv__(self, divisor: Float32) -> Self:
        """Return this vector divided by a number, three.js's
        `divideScalar`: a multiply by the reciprocal, as there. A zero
        divisor gives infinities, as there.

        Args:
            divisor: The number to divide by.

        Returns:
            The divided vector.
        """
        return self * (1 / divisor)

    def __eq__(self, other: Self) -> Bool:
        """Return True if every component is exactly equal, three.js's
        `equals`.

        Args:
            other: The vector to compare with.

        Returns:
            Whether the two are the same vector.
        """
        return (
            self.x == other.x
            and self.y == other.y
            and self.z == other.z
            and self.w == other.w
        )

    def __ne__(self, other: Self) -> Bool:
        """Return True if any component differs.

        Args:
            other: The vector to compare with.

        Returns:
            Whether the two differ.
        """
        return not self == other

    def get_component(self, index: Int) raises -> Float32:
        """Return one component by its index, three.js's `getComponent`.

        Args:
            index: 0 for x, 1 for y, 2 for z, 3 for w.

        Returns:
            The component.

        Raises:
            Error: If the index is not 0, 1, 2 or 3.
        """
        if index == 0:
            return self.x
        if index == 1:
            return self.y
        if index == 2:
            return self.z
        if index == 3:
            return self.w
        raise Error("A Vector4 component index is 0, 1, 2 or 3")

    def set_component(mut self, index: Int, value: Float32) raises:
        """Set one component by its index, three.js's `setComponent`.

        Args:
            index: 0 for x, 1 for y, 2 for z, 3 for w.
            value: The new component.

        Raises:
            Error: If the index is not 0, 1, 2 or 3. The vector is left as
                it was.
        """
        if index == 0:
            self.x = value
        elif index == 1:
            self.y = value
        elif index == 2:
            self.z = value
        elif index == 3:
            self.w = value
        else:
            raise Error("A Vector4 component index is 0, 1, 2 or 3")

    def negate(mut self):
        """Point this vector the other way, in place, three.js's
        `negate`."""
        self = -self

    def add_scaled_vector(mut self, other: Self, factor: Float32):
        """Add `other` times `factor` into this vector, three.js's
        `addScaledVector`.

        Args:
            other: The vector to add.
            factor: What to scale it by first.
        """
        self = self + other * factor

    def length_sq(self) -> Float32:
        """Return the squared length, three.js's `lengthSq`.

        Returns:
            The dot product of this vector with itself.
        """
        return self.dot(self)

    def manhattan_length(self) -> Float32:
        """Return the sum of the absolute components, three.js's
        `manhattanLength`.

        Returns:
            `|x| + |y| + |z| + |w|`.
        """
        return abs(self.x) + abs(self.y) + abs(self.z) + abs(self.w)

    def set_length(mut self, length: Float32):
        """Scale this vector to `length`, three.js's `setLength`. A zero
        vector stays zero, as `normalize` leaves it.

        Args:
            length: The new length.
        """
        self.normalize()
        self = self * length

    def lerp(mut self, other: Self, alpha: Float32):
        """Move this vector toward `other` by `alpha`, three.js's `lerp`.

        Args:
            other: The vector to move toward.
            alpha: Zero stays, one arrives. Values outside run on.
        """
        self.x += (other.x - self.x) * alpha
        self.y += (other.y - self.y) * alpha
        self.z += (other.z - self.z) * alpha
        self.w += (other.w - self.w) * alpha

    def lerp_vectors(mut self, start: Self, end: Self, alpha: Float32):
        """Set this vector a fraction of the way from `start` to `end`,
        three.js's `lerpVectors`.

        Args:
            start: The vector at an `alpha` of zero.
            end: The vector at an `alpha` of one.
            alpha: How far along.
        """
        self = Vector4(
            start.x + (end.x - start.x) * alpha,
            start.y + (end.y - start.y) * alpha,
            start.z + (end.z - start.z) * alpha,
            start.w + (end.w - start.w) * alpha,
        )

    def multiply(mut self, other: Self):
        """Multiply each component by `other`'s, three.js's `multiply`.

        Args:
            other: The factors.
        """
        self = Vector4(
            self.x * other.x,
            self.y * other.y,
            self.z * other.z,
            self.w * other.w,
        )

    def divide(mut self, other: Self):
        """Divide each component by `other`'s, three.js's `divide`. A zero
        divisor gives an infinity or a not-a-number, as there.

        Args:
            other: The divisors.
        """
        self = Vector4(
            self.x / other.x,
            self.y / other.y,
            self.z / other.z,
            self.w / other.w,
        )

    def min(mut self, other: Self):
        """Keep the smaller of each pair of components, three.js's `min`.

        Args:
            other: The other vector.
        """
        self = Vector4(
            min(self.x, other.x),
            min(self.y, other.y),
            min(self.z, other.z),
            min(self.w, other.w),
        )

    def max(mut self, other: Self):
        """Keep the larger of each pair of components, three.js's `max`.

        Args:
            other: The other vector.
        """
        self = Vector4(
            max(self.x, other.x),
            max(self.y, other.y),
            max(self.z, other.z),
            max(self.w, other.w),
        )

    def clamp(mut self, low: Self, high: Self):
        """Hold each component between the two vectors' components,
        three.js's `clamp`.

        Args:
            low: The smallest value of each component.
            high: The largest. Where it is below `low`, `low` wins, as in
                three.js.
        """
        self = Vector4(
            max(low.x, min(high.x, self.x)),
            max(low.y, min(high.y, self.y)),
            max(low.z, min(high.z, self.z)),
            max(low.w, min(high.w, self.w)),
        )

    def clamp_scalar(mut self, low: Float32, high: Float32):
        """Hold each component between two numbers, three.js's
        `clampScalar`.

        Args:
            low: The smallest value.
            high: The largest.
        """
        self.clamp(Vector4(low, low, low, low), Vector4(high, high, high, high))

    def clamp_length(mut self, low: Float32, high: Float32):
        """Hold this vector's length between two numbers, keeping its
        direction, three.js's `clampLength`.

        A zero vector is divided by one and then scaled, as in three.js, so
        it stays zero.

        Args:
            low: The shortest length.
            high: The longest.
        """
        var length = self.length()
        var divisor = length if length != 0 else Float32(1)
        self = self / divisor * max(low, min(high, length))

    def floor(mut self):
        """Round each component down, three.js's `floor`."""
        self = Vector4(
            floor(self.x), floor(self.y), floor(self.z), floor(self.w)
        )

    def ceil(mut self):
        """Round each component up, three.js's `ceil`."""
        self = Vector4(ceil(self.x), ceil(self.y), ceil(self.z), ceil(self.w))

    def round(mut self):
        """Round each component to the nearest whole number, a half up,
        three.js's `round`."""
        self = Vector4(
            _js_round(self.x),
            _js_round(self.y),
            _js_round(self.z),
            _js_round(self.w),
        )

    def round_to_zero(mut self):
        """Drop each component's fraction, three.js's `roundToZero`."""
        self = Vector4(
            trunc(self.x), trunc(self.y), trunc(self.z), trunc(self.w)
        )

    def set_from_matrix_position(mut self, matrix: Matrix4):
        """Set this vector to a matrix's last column, three.js's
        `setFromMatrixPosition`: the translation, and the last entry of the
        bottom row in `w`.

        Args:
            matrix: The matrix to read.
        """
        ref e = matrix.elements
        self = Vector4(e[12], e[13], e[14], e[15])

    def axis_angle(self) -> Angle:
        """Return `w` as an angle, which is where the two axis-angle setters
        put it.

        Returns:
            The angle, `w` radians.
        """
        return Angle(self.w, RADIAN)

    def set_axis_angle_from_quaternion(mut self, quaternion: Quaternion):
        """Set this vector to a rotation's axis and angle, three.js's
        `setAxisAngleFromQuaternion`.

        The axis goes into `x`, `y` and `z` and the angle, in radians from
        zero to a whole turn, into `w`. A turn too small to have an axis
        gets +x, as in three.js.

        Args:
            quaternion: The rotation. It must be unit length, as three.js
                assumes: a `w` past one gives an angle that is not a number,
                there and here.
        """
        self.w = 2 * acos(quaternion.w)
        var s = sqrt(1 - quaternion.w * quaternion.w)
        if s < 0.0001:
            self.x = 1
            self.y = 0
            self.z = 0
        else:
            self.x = quaternion.x / s
            self.y = quaternion.y / s
            self.z = quaternion.z / s

    def set_axis_angle_from_rotation_matrix(mut self, matrix: Matrix4):
        """Set this vector to the axis and angle of a rotation matrix,
        three.js's `setAxisAngleFromRotationMatrix`.

        The axis goes into `x`, `y` and `z` and the angle, in radians, into
        `w`. A symmetric matrix is no turn or a half turn. No turn gives
        (1, 0, 0, 0). A half turn takes its axis from the largest diagonal
        entry. When that entry is too small to divide by, the axis is one
        of three.js's three fixed axes. The thresholds are three.js's.

        Args:
            matrix: A matrix whose upper 3x3 is a pure rotation, as three.js
                assumes. Anything else gives three.js's numbers, which are
                not an axis and an angle.
        """
        ref e = matrix.elements
        var m11 = e[0]
        var m12 = e[4]
        var m13 = e[8]
        var m21 = e[1]
        var m22 = e[5]
        var m23 = e[9]
        var m31 = e[2]
        var m32 = e[6]
        var m33 = e[10]
        if _is_symmetric(matrix):
            if _is_near_identity(matrix):
                self = Vector4(1, 0, 0, 0)
                return
            var xx = (m11 + 1) / 2
            var yy = (m22 + 1) / 2
            var zz = (m33 + 1) / 2
            var xy = (m12 + m21) / 4
            var xz = (m13 + m31) / 4
            var yz = (m23 + m32) / 4
            var x: Float32
            var y: Float32
            var z: Float32
            if _is_largest(xx, yy, zz):
                if xx < _SYMMETRY_EPSILON:
                    x = 0
                    y = _HALF_ROOT_TWO
                    z = _HALF_ROOT_TWO
                else:
                    x = sqrt(xx)
                    y = xy / x
                    z = xz / x
            elif yy > zz:
                if yy < _SYMMETRY_EPSILON:
                    x = _HALF_ROOT_TWO
                    y = 0
                    z = _HALF_ROOT_TWO
                else:
                    y = sqrt(yy)
                    x = xy / y
                    z = yz / y
            elif zz < _SYMMETRY_EPSILON:
                x = _HALF_ROOT_TWO
                y = _HALF_ROOT_TWO
                z = 0
            else:
                z = sqrt(zz)
                x = xz / z
                y = yz / z
            self = Vector4(x, y, z, Float32(pi))
            return
        var s = sqrt(
            (m32 - m23) * (m32 - m23)
            + (m13 - m31) * (m13 - m31)
            + (m21 - m12) * (m21 - m12)
        )
        # three.js guards the divide, although a matrix that is not
        # symmetric has an `s` of at least a hundredth. Kept so that the
        # same input gives the same numbers.
        s = s if s >= 0.001 else Float32(1)
        self.x = (m32 - m23) / s
        self.y = (m13 - m31) / s
        self.z = (m21 - m12) / s
        self.w = acos((m11 + m22 + m33 - 1) / 2)
