# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's frame: `Rotation` and `Transform` from `LibCarla/source/carla/geom`.

In CARLA's frame, plus x points forward, plus y points right and plus z
points up, so the frame is left-handed. A rotation is a pitch, a yaw and
a roll in degrees. The matrices below are the ones
`Rotation::RotateVector` and `Transform::GetMatrix` write, with the pitch
sign CARLA corrected in 2026.

three.js is right-handed with plus y up. `carla_to_three` swaps y and z,
which also flips the handedness. A CARLA rotation R becomes P R P in the
three.js frame, where P is that swap, and the determinant stays one.
"""

from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.ffi import external_call
from std.math import cos, isfinite, nan, sin
from units.si import DEGREE, Angle, Length


def carla_to_three(point: Vector3) -> Vector3:
    """Return a CARLA point in the three.js frame.

    Args:
        point: Forward, right and up, in meters.

    Returns:
        The same point as three.js x, y and z: forward, up and right.
    """
    return Vector3(point.x, point.z, point.y)


def three_to_carla(point: Vector3) -> Vector3:
    """Return a three.js point in the CARLA frame.

    Args:
        point: A three.js x, y and z, in meters.

    Returns:
        The same point as CARLA forward, right and up.
    """
    return Vector3(point.x, point.z, point.y)


@fieldwise_init
struct _Trig(ImplicitlyCopyable):
    var cp: Float32
    var sp: Float32
    var cy: Float32
    var sy: Float32
    var cr: Float32
    var sr: Float32


struct CarlaRotation(Equatable, ImplicitlyCopyable, Writable):
    """A pitch, a yaw and a roll in degrees, CARLA's `geom::Rotation`."""

    var pitch: Float32
    var yaw: Float32
    var roll: Float32

    def __init__(out self, pitch: Angle, yaw: Angle, roll: Angle):
        """Create a rotation from three angles.

        Args:
            pitch: The turn about the right axis.
            yaw: The turn about the up axis. Plus yaw turns forward to right.
            roll: The turn about the forward axis.
        """
        self.pitch = pitch.to(DEGREE)
        self.yaw = yaw.to(DEGREE)
        self.roll = roll.to(DEGREE)

    def _trig(self) -> _Trig:
        comptime to_radians = Float32(0.017453292519943295)
        var p = self.pitch * to_radians
        var y = self.yaw * to_radians
        var r = self.roll * to_radians
        return _Trig(cos(p), sin(p), cos(y), sin(y), cos(r), sin(r))

    def rotate_vector(self, v: Vector3) -> Vector3:
        """Rotate a vector, CARLA's `Rotation::RotateVector`.

        Args:
            v: A vector in the CARLA frame.

        Returns:
            The rotated vector.
        """
        var t = self._trig()
        return Vector3(
            v.x * (t.cp * t.cy)
            + v.y * (t.cy * t.sp * t.sr - t.sy * t.cr)
            + v.z * (t.cy * t.sp * t.cr + t.sy * t.sr),
            v.x * (t.cp * t.sy)
            + v.y * (t.sy * t.sp * t.sr + t.cy * t.cr)
            + v.z * (t.sy * t.sp * t.cr - t.cy * t.sr),
            v.x * (-t.sp) + v.y * (t.cp * t.sr) + v.z * (t.cp * t.cr),
        )

    def inverse_rotate_vector(self, v: Vector3) -> Vector3:
        """Undo `rotate_vector`, CARLA's `Rotation::InverseRotateVector`.

        Args:
            v: A vector in the CARLA frame.

        Returns:
            The vector turned back by this rotation.
        """
        var t = self._trig()
        return Vector3(
            v.x * (t.cp * t.cy) + v.y * (t.cp * t.sy) + v.z * (-t.sp),
            v.x * (t.cy * t.sp * t.sr - t.sy * t.cr)
            + v.y * (t.sy * t.sp * t.sr + t.cy * t.cr)
            + v.z * (t.cp * t.sr),
            v.x * (t.cy * t.sp * t.cr + t.sy * t.sr)
            + v.y * (t.sy * t.sp * t.cr - t.cy * t.sr)
            + v.z * (t.cp * t.cr),
        )

    def forward_vector(self) -> Vector3:
        """Return where plus x points after this rotation.

        Returns:
            A unit vector in the CARLA frame.
        """
        return self.rotate_vector(Vector3(1, 0, 0))

    def right_vector(self) -> Vector3:
        """Return where plus y points after this rotation.

        Returns:
            A unit vector in the CARLA frame.
        """
        return self.rotate_vector(Vector3(0, 1, 0))

    def up_vector(self) -> Vector3:
        """Return where plus z points after this rotation.

        Returns:
            A unit vector in the CARLA frame.
        """
        return self.rotate_vector(Vector3(0, 0, 1))

    def normalized(self) -> CarlaRotation:
        """Wrap each angle into [-180, 180) degrees, `Rotation::Normalize`.

        Finite angles reduce without loss of whole-turn remainders.
        Both 180 and -180 become -180. Zero keeps the input sign.
        A nonfinite angle becomes NaN.

        Returns:
            The same rotation with each finite angle wrapped.
        """
        var out = self
        out.pitch = _wrap_degrees(self.pitch)
        out.yaw = _wrap_degrees(self.yaw)
        out.roll = _wrap_degrees(self.roll)
        return out

    def __eq__(self, other: Self) -> Bool:
        """Return True if the three angles are equal.

        Args:
            other: The rotation to compare.

        Returns:
            True if pitch, yaw and roll match exactly.
        """
        return (
            self.pitch == other.pitch
            and self.yaw == other.yaw
            and self.roll == other.roll
        )

    def write_to(self, mut writer: Some[Writer]):
        """Write the rotation as CARLA prints it.

        Args:
            writer: The destination.
        """
        writer.write(
            "Rotation(pitch=",
            self.pitch,
            ", yaw=",
            self.yaw,
            ", roll=",
            self.roll,
            ")",
        )


def _wrap_degrees(angle: Float32) -> Float32:
    """Wrap to [-180, 180), keep signed zero, and map nonfinite to NaN."""
    # Most comparisons already use this interval. Keep their bits directly.
    if angle >= -180.0 and angle < 180.0:
        return angle
    if not isfinite(angle):
        return nan[DType.float32]()
    # fmodf reduces the significand, without subtracting a rounded quotient.
    # Keep negative small angles unchanged: adding 360 can erase low bits.
    var out = external_call["fmodf", Float32](angle, Float32(360))
    if out < -180.0:
        out += 360.0
    if out >= 180.0:
        out -= 360.0
    return out


struct CarlaTransform(ImplicitlyCopyable):
    """A location and a rotation, CARLA's `geom::Transform`."""

    # Forward, right and up, in meters.
    var location: Vector3
    var rotation: CarlaRotation

    def __init__(
        out self, x: Length, y: Length, z: Length, rotation: CarlaRotation
    ):
        """Create a transform from a location and a rotation.

        Args:
            x: Forward.
            y: Right.
            z: Up.
            rotation: The rotation, applied before the translation.
        """
        self.location = Vector3(x.value, y.value, z.value)
        self.rotation = rotation

    def transform_point(self, point: Vector3) -> Vector3:
        """Rotate, then translate, `Transform::TransformPoint`.

        Args:
            point: A point in this transform's local frame.

        Returns:
            The point in the parent frame.
        """
        return self.rotation.rotate_vector(point) + self.location

    def inverse_transform_point(self, point: Vector3) -> Vector3:
        """Undo `transform_point`, `Transform::InverseTransformPoint`.

        Args:
            point: A point in the parent frame.

        Returns:
            The point in this transform's local frame.
        """
        return self.rotation.inverse_rotate_vector(point - self.location)

    def matrix(self) -> Matrix4:
        """Return the 4x4 form, `Transform::GetMatrix`, in the CARLA frame.

        Returns:
            A matrix that takes local CARLA points to parent CARLA points.
        """
        var t = self.rotation._trig()
        var m = Matrix4()
        m.set(
            t.cp * t.cy,
            t.cy * t.sp * t.sr - t.sy * t.cr,
            t.cy * t.sp * t.cr + t.sy * t.sr,
            self.location.x,
            t.cp * t.sy,
            t.sy * t.sp * t.sr + t.cy * t.cr,
            t.sy * t.sp * t.cr - t.cy * t.sr,
            self.location.y,
            -t.sp,
            t.cp * t.sr,
            t.cp * t.cr,
            self.location.z,
            0,
            0,
            0,
            1,
        )
        return m

    def three_matrix(self) -> Matrix4:
        """Return this transform in the three.js frame.

        Returns:
            P M P, where M is `matrix` and P swaps y and z. It places a
            three.js node as CARLA places the actor.
        """
        var swap = Matrix4()
        swap.set(1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1)
        return swap * self.matrix() * swap

    def camera_matrix(self) -> Matrix4:
        """Return a three.js camera matrix that looks where this actor looks.

        A CARLA camera looks along its plus x. A three.js camera looks
        along its minus z. A quarter turn about y joins the two.

        Returns:
            `three_matrix` times a turn of -90 degrees about y.
        """
        var turn = Matrix4()
        turn.set(0, 0, -1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1)
        return self.three_matrix() * turn
