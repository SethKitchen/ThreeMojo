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

An `Euler` converts *to* a quaternion or a matrix; it does not come back
from one. three.js reads angles out of a rotation matrix for all six orders,
and `Object3D.rotation` there stays in step with the quaternion by doing so.
Here `Object3D` holds the quaternion as the truth and an `Euler` is a thing
you set it from, which is all the examples and the tests have needed. The
decomposition is a well-defined next step, not a missing half.
"""

from math.matrix4 import Matrix4, rotation_x, rotation_y, rotation_z
from math.quaternion import Quaternion
from math.vector3 import Vector3
from units.si import Angle

# The three axes, as the index each rotation helper answers to.
comptime AXIS_X = 0
comptime AXIS_Y = 1
comptime AXIS_Z = 2


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

    def _angle_about(self, axis: Int) -> Angle:
        """Return the angle this holds for one axis."""
        if axis == AXIS_X:
            return self.x
        if axis == AXIS_Y:
            return self.y
        return self.z

    def to_quaternion(self) -> Quaternion:
        """Return the rotation these angles describe.

        Composed from three axis-angle rotations in the named order, which
        is by definition what the order means, rather than from a table of
        six expanded formulas that could each hide a sign error. It agrees
        with `to_matrix` to Float32 precision, and a test says so for every
        order.

        Returns:
            The unit quaternion.
        """
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

    def to_matrix(self) -> Matrix4:
        """Return the rotation these angles describe, as a matrix.

        The product of the three axis rotations in the named order, which is
        exactly three.js's `makeRotationFromEuler` for that order.

        Returns:
            The rotation matrix.
        """
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
