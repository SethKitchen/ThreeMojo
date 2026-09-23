# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A rotation as four numbers, ported from three.js `src/math/Quaternion.js`.

A quaternion is the form a rotation takes when it has to be *composed* and
*interpolated* rather than merely applied. A matrix composes but has nine
numbers doing the work of three, and interpolating two of them element by
element gives something that is not a rotation. Three Euler angles interpolate
but compose in an order-dependent way and lock up when two axes align. A unit
quaternion does both: multiplying two gives the composed rotation, and
`slerp` slides from one to another along the shortest arc at constant speed.

`Object3D` holds one of these as its rotation, so `rotate_y` is one multiply
rather than a matrix product, and an animation can blend two poses.

Conventions match three.js: `(x, y, z, w)` with `w` the real part, a unit
quaternion is a rotation, and `a * b` applies `b` first and then `a`, exactly
as the matrices `a.to_matrix() * b.to_matrix()` would.
"""

from math.euler import Euler
from math.matrix4 import Matrix4
from math.utils import SeededRandom
from math.vector3 import Vector3
from std.math import acos, atan2, cos, pi, sin, sqrt
from units.si import Angle, RADIAN

# Below this, two quaternions are close enough that slerp falls back to a
# straight line: the arc's sine is too small to divide by safely, and the
# difference is below what Float32 can express anyway.
comptime SLERP_EPSILON = Float32(1e-6)


# How near to opposite two directions are before `from_unit_vectors`
# picks a half turn. three.js: `Number.EPSILON`, scaled to Float32.
comptime HALF_TURN_EPSILON = Float32(1e-6)


@fieldwise_init
struct Quaternion(Equatable, ImplicitlyCopyable):
    """A rotation as (x, y, z, w), the identity being (0, 0, 0, 1)."""

    var x: Float32
    var y: Float32
    var z: Float32
    var w: Float32

    @staticmethod
    def identity() -> Quaternion:
        """Return the rotation that changes nothing."""
        return Quaternion(0, 0, 0, 1)

    @staticmethod
    def from_axis_angle(axis: Vector3, angle: Angle) -> Quaternion:
        """Return the rotation of `angle` about `axis`.

        Args:
            axis: The axis to turn about, which must be unit length; it is
                used as given, as three.js does.
            angle: How far to turn, counter-clockwise looking down the axis.

        Returns:
            The rotation.
        """
        var half = angle.value / 2
        var s = sin(half)
        return Quaternion(axis.x * s, axis.y * s, axis.z * s, cos(half))

    @staticmethod
    def from_unit_vectors(v_from: Vector3, v_to: Vector3) -> Quaternion:
        """Return the shortest rotation that turns one direction onto
        another. three.js: `setFromUnitVectors`.

        Opposite directions have no one shortest rotation; the half turn
        is taken about an axis perpendicular to `v_from`, as three.js
        takes it.

        Args:
            v_from: The direction to turn, unit length.
            v_to: Where it ends up, unit length.

        Returns:
            The rotation, normalized.
        """
        var r = v_from.dot(v_to) + 1
        var turn: Quaternion
        if r < HALF_TURN_EPSILON:
            if abs(v_from.x) > abs(v_from.z):
                turn = Quaternion(-v_from.y, v_from.x, 0, 0)
            else:
                turn = Quaternion(0, -v_from.z, v_from.y, 0)
        else:
            var axis = v_from
            axis.cross(v_to)
            turn = Quaternion(axis.x, axis.y, axis.z, r)
        turn.normalize()
        return turn

    @staticmethod
    def from_matrix(matrix: Matrix4) -> Quaternion:
        """Return the rotation the upper-left 3x3 of `matrix` performs.

        three.js's `setFromRotationMatrix`: pick whichever of the trace and
        the three diagonal terms is largest, because each formula divides by
        a root of it and the largest keeps that division well away from
        zero. The matrix must be a pure rotation; a scale in it comes out as
        a wrong rotation rather than an error, as in three.js.

        Args:
            matrix: A rotation matrix.

        Returns:
            The unit quaternion for it.
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
        var trace = m11 + m22 + m33
        if trace > 0:
            var s = Float32(0.5) / sqrt(trace + 1)
            return Quaternion(
                (m32 - m23) * s,
                (m13 - m31) * s,
                (m21 - m12) * s,
                Float32(0.25) / s,
            )
        if m11 > m22 and m11 > m33:
            var s = 2 * sqrt(1 + m11 - m22 - m33)
            return Quaternion(
                Float32(0.25) * s,
                (m12 + m21) / s,
                (m13 + m31) / s,
                (m32 - m23) / s,
            )
        if m22 > m33:
            var s = 2 * sqrt(1 + m22 - m11 - m33)
            return Quaternion(
                (m12 + m21) / s,
                Float32(0.25) * s,
                (m23 + m32) / s,
                (m13 - m31) / s,
            )
        var s = 2 * sqrt(1 + m33 - m11 - m22)
        return Quaternion(
            (m13 + m31) / s,
            (m23 + m32) / s,
            Float32(0.25) * s,
            (m21 - m12) / s,
        )

    def to_matrix(self) -> Matrix4:
        """Return this rotation as a matrix with no translation or scale.

        three.js's `makeRotationFromQuaternion`, which is `compose` with a
        unit scale and no position.

        Returns:
            The rotation matrix.
        """
        var x2 = self.x + self.x
        var y2 = self.y + self.y
        var z2 = self.z + self.z
        var xx = self.x * x2
        var xy = self.x * y2
        var xz = self.x * z2
        var yy = self.y * y2
        var yz = self.y * z2
        var zz = self.z * z2
        var wx = self.w * x2
        var wy = self.w * y2
        var wz = self.w * z2
        var matrix = Matrix4()
        matrix.set(
            1 - (yy + zz),
            xy - wz,
            xz + wy,
            0,
            xy + wz,
            1 - (xx + zz),
            yz - wx,
            0,
            xz - wy,
            yz + wx,
            1 - (xx + yy),
            0,
            0,
            0,
            0,
            1,
        )
        return matrix^

    def multiply(mut self, other: Self):
        """Set `self` to `self * other`: apply `other`, then what self was.

        The same order as `Matrix4.multiply`, so rotating on a *local* axis
        is `quaternion.multiply(turn)` and on a world axis `premultiply`.
        """
        var ax = self.x
        var ay = self.y
        var az = self.z
        var aw = self.w
        var bx = other.x
        var by = other.y
        var bz = other.z
        var bw = other.w
        self.x = ax * bw + aw * bx + ay * bz - az * by
        self.y = ay * bw + aw * by + az * bx - ax * bz
        self.z = az * bw + aw * bz + ax * by - ay * bx
        self.w = aw * bw - ax * bx - ay * by - az * bz

    def premultiply(mut self, other: Self):
        """Set `self` to `other * self`: apply what self was, then `other`."""
        var left = other
        left.multiply(self)
        self = left

    def dot(self, other: Self) -> Float32:
        """Return the four-component dot product."""
        return (
            self.x * other.x
            + self.y * other.y
            + self.z * other.z
            + self.w * other.w
        )

    def length(self) -> Float32:
        """Return the Euclidean length of the four components."""
        return sqrt(self.dot(self))

    def normalize(mut self):
        """Scale `self` to unit length; a zero quaternion becomes the identity.

        A rotation is only a rotation at unit length, and a long chain of
        multiplies drifts. three.js makes the same choice for zero: there is
        no direction to keep, so the answer is "no rotation".
        """
        var magnitude = self.length()
        if magnitude == 0:
            self = Quaternion.identity()
            return
        self.x /= magnitude
        self.y /= magnitude
        self.z /= magnitude
        self.w /= magnitude

    def conjugate(self) -> Self:
        """Return the opposite rotation, which for a unit quaternion is the
        inverse."""
        return Quaternion(-self.x, -self.y, -self.z, self.w)

    def rotate(self, v: Vector3) -> Vector3:
        """Return `v` turned by this rotation.

        three.js's `Vector3.applyQuaternion`: the product `q * v * q^-1` with
        the middle step written out, rather than building the matrix first.
        """
        var tx = 2 * (self.y * v.z - self.z * v.y)
        var ty = 2 * (self.z * v.x - self.x * v.z)
        var tz = 2 * (self.x * v.y - self.y * v.x)
        return Vector3(
            v.x + self.w * tx + self.y * tz - self.z * ty,
            v.y + self.w * ty + self.z * tx - self.x * tz,
            v.z + self.w * tz + self.x * ty - self.y * tx,
        )

    def slerp(self, other: Self, t: Float32) -> Self:
        """Return the rotation a fraction `t` of the way from self to `other`.

        Along the shortest arc at constant angular speed, which is what makes
        an animation between two poses turn evenly rather than speeding up
        in the middle as a straight-line blend would.

        Args:
            other: Where to arrive at `t` of one.
            t: How far along, zero to one.

        Returns:
            The interpolated unit rotation.
        """
        # A rotation and its negation are the same rotation. Taking the
        # negation when the two point away from each other is what picks the
        # short arc rather than the long way round.
        var target = other
        var cos_half = self.dot(other)
        if cos_half < 0:
            target = Quaternion(-other.x, -other.y, -other.z, -other.w)
            cos_half = -cos_half
        # Already there, or as close as a Float32 can tell.
        if cos_half >= 1:
            return self
        var sin_half_squared = 1 - cos_half * cos_half
        # So close that the arc is a line: blend straight and renormalize,
        # because the sine we would divide by is nearly zero.
        if sin_half_squared <= SLERP_EPSILON:
            var blend = Quaternion(
                self.x + (target.x - self.x) * t,
                self.y + (target.y - self.y) * t,
                self.z + (target.z - self.z) * t,
                self.w + (target.w - self.w) * t,
            )
            blend.normalize()
            return blend
        var sin_half = sqrt(sin_half_squared)
        var half = atan2(sin_half, cos_half)
        var keep = sin((1 - t) * half) / sin_half
        var take = sin(t * half) / sin_half
        return Quaternion(
            self.x * keep + target.x * take,
            self.y * keep + target.y * take,
            self.z * keep + target.z * take,
            self.w * keep + target.w * take,
        )

    @staticmethod
    def slerp_quaternions(start: Self, end: Self, t: Float32) -> Self:
        """Return the rotation a fraction `t` of the way from `start` to
        `end`, three.js's `slerpQuaternions`.

        Args:
            start: The rotation at a `t` of zero.
            end: The rotation at a `t` of one.
            t: How far along.

        Returns:
            `start.slerp(end, t)`.
        """
        return start.slerp(end, t)

    @staticmethod
    def from_euler(euler: Euler) raises -> Quaternion:
        """Return the rotation three angles describe, three.js's
        `setFromEuler`. `Euler.to_quaternion` does the arithmetic.

        Args:
            euler: The angles and their order.

        Returns:
            The rotation.

        Raises:
            Error: If the order does not name three different axes.
        """
        return euler.to_quaternion()

    @staticmethod
    def random(mut generator: SeededRandom) -> Quaternion:
        """Return a rotation drawn evenly from all rotations, three.js's
        `random`: Shoemake's method, with the three numbers drawn in
        three.js's order.

        Args:
            generator: Where the numbers come from.

        Returns:
            A unit quaternion.
        """
        var theta1 = 2 * pi * generator.next()
        var theta2 = 2 * pi * generator.next()
        var x0 = generator.next()
        var r1 = sqrt(1 - x0)
        var r2 = sqrt(x0)
        return Quaternion(
            Float32(r1 * sin(theta1)),
            Float32(r1 * cos(theta1)),
            Float32(r2 * sin(theta2)),
            Float32(r2 * cos(theta2)),
        )

    def __eq__(self, other: Self) -> Bool:
        """Return True if all four components are exactly equal, three.js's
        `equals`. A quaternion and its negation are the same rotation and
        still not equal, as there.

        Args:
            other: The quaternion to compare with.

        Returns:
            Whether the two are the same four numbers.
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
            other: The quaternion to compare with.

        Returns:
            Whether the two differ.
        """
        return not self == other

    def __mul__(self, other: Self) -> Self:
        """Return `self * other`, three.js's `multiplyQuaternions`: apply
        `other`, then `self`.

        Args:
            other: The rotation applied first.

        Returns:
            The product.
        """
        var product = self
        product.multiply(other)
        return product

    def length_sq(self) -> Float32:
        """Return the squared length of the four components, three.js's
        `lengthSq`.

        Returns:
            The dot product with itself.
        """
        return self.dot(self)

    def invert(mut self):
        """Replace this rotation by its inverse, three.js's `invert`. For
        a unit quaternion that is the conjugate, and three.js takes the
        conjugate whatever the length; so does this.
        """
        self = self.conjugate()

    def angle_to(self, other: Self) -> Angle:
        """Return the angle of the turn from this rotation to `other`,
        three.js's `angleTo`.

        Args:
            other: The other rotation, unit length.

        Returns:
            From zero to a half turn: the short way round.
        """
        var cosine = max(Float32(-1), min(Float32(1), self.dot(other)))
        return Angle(2 * acos(abs(cosine)), RADIAN)

    def rotate_towards(mut self, other: Self, step: Angle):
        """Turn this rotation toward `other` by at most `step`, three.js's
        `rotateTowards`. It arrives when `other` is within the step.

        Args:
            other: The rotation to turn toward, unit length.
            step: The most to turn.
        """
        var angle = self.angle_to(other).value
        if angle == 0:
            return
        self = self.slerp(other, min(Float32(1), step.value / angle))
