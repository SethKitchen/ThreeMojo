# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Three angles and an order, from three.js `src/math/Euler.js`.

The friendly way to say a rotation: turn this much about x, this much about
y, this much about z. What makes it a *definition* rather than three numbers
is the order, because rotations do not commute. three.js's order names
intrinsic axes -- `XYZ` turns about x, then about the y axis as it now lies,
then about the z axis as it now lies -- which as a matrix is Rx * Ry * Rz, the
last-named rotation being the one a point meets first.

An `Euler` converts to a quaternion or a matrix and comes back from either,
for all six orders, as three.js's `setFromRotationMatrix` and
`setFromQuaternion` do. `Object3D` holds the quaternion as the truth and
`rotation()` decomposes it on request, so the angles are never stale and
never stored twice. What comes back is a snapshot that rebuilds the rotation
to Float32 precision, not the numbers that went in: past a right angle on
the middle axis more than one triple makes the same rotation, and whole
turns are gone, because a rotation does not remember them.

At gimbal lock, where the middle angle is a right angle, the first and third
axes lie along one line and only one combination of their angles is defined;
all of it goes to the first angle and the third is zero, as in three.js. A
middle angle within about three hundredths of a degree of a right angle
reads as locked, and the rotation that reading rebuilds is off by up to that
much. Just outside the lock the split between the first and third angles is
defined but sensitive: a rounding error in the rotation moves angle from one
to the other, while the rotation they rebuild stays right.

Every conversion refuses an order that does not name three different axes.
`EulerOrder(0, 0, 1)` is the right type holding a wrong value, and composing
Rx * Rx * Ry for it would be a rotation nobody asked for.
"""

from math.matrix4 import Matrix4, rotation_x, rotation_y, rotation_z
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import asin, atan2
from units.si import Angle, RADIAN

# The three axes, as the index each rotation helper answers to.
comptime AXIS_X = 0
comptime AXIS_Y = 1
comptime AXIS_Z = 2

# Past this the middle angle's sine is one to Float32 precision: the outer
# two axes have folded onto each other and only one combination of their
# angles is defined. three.js's threshold, so both ports lock at the same
# angle.
comptime LOCK_THRESHOLD = Float32(0.9999999)


@fieldwise_init
struct EulerOrder(Equatable, ImplicitlyCopyable, Writable):
    """Which axis three Euler angles turn about first, second and third.

    three.js's `Euler.order`, as a type rather than a string. Held as the
    three axis indices rather than a code, so composing the rotation is a
    loop and not a branch per order.
    """

    var first: Int
    var second: Int
    var third: Int

    def is_valid(self) -> Bool:
        """Return True if this names three different axes.

        The six named orders are valid. `EulerOrder(0, 0, 1)` is the right
        type holding a wrong value, and every `Euler` conversion refuses it.
        """
        var each_an_axis = (
            _is_axis(self.first)
            and _is_axis(self.second)
            and _is_axis(self.third)
        )
        return (
            each_an_axis
            and self.first != self.second
            and self.second != self.third
            and self.first != self.third
        )

    def is_cyclic(self) -> Bool:
        """Return True if the axes run x, y, z round: `XYZ`, `YZX` or `ZXY`.

        The other three run the cycle backwards, and every sign in the
        decomposition flips with them.
        """
        return self.second == (self.first + 1) % 3


def _is_axis(axis: Int) -> Bool:
    """Return True if `axis` is one of the three axis indices."""
    return axis >= AXIS_X and axis <= AXIS_Z


def _clamp_unit(value: Float32) -> Float32:
    """Return `value` held to minus one through one, so `asin` never sees a
    rounding error past the edge."""
    return max(Float32(-1), min(Float32(1), value))


def _check_order(order: EulerOrder) raises:
    """Refuse an order that does not name three different axes."""
    if not order.is_valid():
        raise Error("An Euler order must name three different axes")


# The six orders three.js accepts. `XYZ` is its default and this port's.
comptime XYZ = EulerOrder(AXIS_X, AXIS_Y, AXIS_Z)
comptime YXZ = EulerOrder(AXIS_Y, AXIS_X, AXIS_Z)
comptime ZXY = EulerOrder(AXIS_Z, AXIS_X, AXIS_Y)
comptime ZYX = EulerOrder(AXIS_Z, AXIS_Y, AXIS_X)
comptime YZX = EulerOrder(AXIS_Y, AXIS_Z, AXIS_X)
comptime XZY = EulerOrder(AXIS_X, AXIS_Z, AXIS_Y)


def _unit_axis(axis: Int) -> Vector3:
    """Return the unit vector along one of the three axes."""
    if axis == AXIS_X:
        return Vector3(1, 0, 0)
    if axis == AXIS_Y:
        return Vector3(0, 1, 0)
    return Vector3(0, 0, 1)


@fieldwise_init
struct Euler(ImplicitlyCopyable):
    """Three angles about the three axes, applied in `order`."""

    var x: Angle
    var y: Angle
    var z: Angle
    var order: EulerOrder

    @staticmethod
    def from_matrix(matrix: Matrix4, order: EulerOrder = XYZ) raises -> Euler:
        """Return the angles that compose, in `order`, to the rotation in
        `matrix`.

        three.js's `setFromRotationMatrix`, with its six cases folded into
        one. For an order (i, j, k) the product Ri * Rj * Rk puts the sine
        of the middle angle, alone, at row i column k: with a plus sign when
        the axes run x, y, z round and a minus sign when they run backwards.
        The outer two angles come out of the same row and column as an
        `atan2` each, under the same sign rule. The six cases three.js
        spells out are this formula six times, and a test holds it to
        `to_matrix` for every one.

        When the middle angle is a right angle the first and third axes lie
        along one line and only one combination of their angles is defined:
        gimbal lock. All of it goes to the first angle and the third is
        zero, as in three.js, at the same threshold.

        Args:
            matrix: A pure rotation. A scale in it comes out as wrong angles
                rather than an error, as in three.js and in
                `Quaternion.from_matrix`; `Matrix4.is_rotation` tells.
            order: Which axis the returned angles turn about first, second
                and third.

        Returns:
            Three angles that `to_matrix` turns back into `matrix`, to
            Float32 precision away from lock and to the width of the lock
            at it. Not the angles that built it: whole turns are gone, and
            past a right angle in the middle another triple may come back.

        Raises:
            Error: If `order` does not name three different axes.
        """
        _check_order(order)
        var i = order.first
        var j = order.second
        var k = order.third
        var sign = Float32(1)
        if not order.is_cyclic():
            sign = -1
        var middle_sine = sign * matrix.get(i, k)
        var middle = asin(_clamp_unit(middle_sine))
        var first: Float32
        var third: Float32
        if abs(middle_sine) < LOCK_THRESHOLD:
            first = atan2(-sign * matrix.get(j, k), matrix.get(k, k))
            third = atan2(-sign * matrix.get(i, j), matrix.get(i, i))
        else:
            first = atan2(sign * matrix.get(k, j), matrix.get(j, j))
            third = 0
        return _angles_by_axis(order, first, middle, third)

    @staticmethod
    def from_quaternion(
        quaternion: Quaternion, order: EulerOrder = XYZ
    ) raises -> Euler:
        """Return the angles that compose, in `order`, to `quaternion`.

        three.js's `setFromQuaternion`: the quaternion becomes a matrix and
        `from_matrix` reads the angles out of that. The quaternion must be
        unit length, as every one this library makes is.

        Args:
            quaternion: A unit quaternion.
            order: Which axis the returned angles turn about first, second
                and third.

        Returns:
            Three angles that `to_quaternion` turns back into the same
            rotation.

        Raises:
            Error: If `order` does not name three different axes.
        """
        return Euler.from_matrix(quaternion.to_matrix(), order)

    def _angle_about(self, axis: Int) -> Angle:
        """Return the angle this holds for one axis."""
        if axis == AXIS_X:
            return self.x
        if axis == AXIS_Y:
            return self.y
        return self.z

    def to_quaternion(self) raises -> Quaternion:
        """Return the rotation these angles describe.

        Composed from three axis-angle rotations in the named order, which
        is by definition what the order means, rather than from a table of
        six expanded formulas that could each hide a sign error. It agrees
        with `to_matrix` to Float32 precision, and a test says so for every
        order.

        Returns:
            The unit quaternion.

        Raises:
            Error: If the order does not name three different axes. The
                order is a plain field, so it can be wrong after the angles
                were set, and this is where that is caught.
        """
        _check_order(self.order)
        var combined = Quaternion.identity()
        combined.multiply(
            Quaternion.from_axis_angle(
                _unit_axis(self.order.first),
                self._angle_about(self.order.first),
            )
        )
        combined.multiply(
            Quaternion.from_axis_angle(
                _unit_axis(self.order.second),
                self._angle_about(self.order.second),
            )
        )
        combined.multiply(
            Quaternion.from_axis_angle(
                _unit_axis(self.order.third),
                self._angle_about(self.order.third),
            )
        )
        return combined

    def to_matrix(self) raises -> Matrix4:
        """Return the rotation these angles describe, as a matrix.

        The product of the three axis rotations in the named order, which is
        exactly three.js's `makeRotationFromEuler` for that order.

        Returns:
            The rotation matrix.

        Raises:
            Error: If the order does not name three different axes.
        """
        _check_order(self.order)
        var combined = _rotation_about(self.order.first, self)
        combined.multiply(_rotation_about(self.order.second, self))
        combined.multiply(_rotation_about(self.order.third, self))
        return combined^


def _rotation_about(axis: Int, euler: Euler) -> Matrix4:
    """Return the matrix rotation about one axis by that axis's angle."""
    if axis == AXIS_X:
        return rotation_x(euler.x)
    if axis == AXIS_Y:
        return rotation_y(euler.y)
    return rotation_z(euler.z)


def _angles_by_axis(
    order: EulerOrder, first: Float32, second: Float32, third: Float32
) -> Euler:
    """Return an `Euler` whose x, y and z are the radians about the axes
    `order` names first, second and third."""
    var about = Array[Float32, 3](fill=0.0)
    about[order.first] = first
    about[order.second] = second
    about[order.third] = third
    return Euler(
        Angle(about[0], RADIAN),
        Angle(about[1], RADIAN),
        Angle(about[2], RADIAN),
        order,
    )
