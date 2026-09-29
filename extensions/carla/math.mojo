# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's `geom::Math` and the small vector types around it.

The source is `LibCarla/source/carla/geom/Math.cpp` and the headers
`Vector2D.h`, `Vector3D.h`, `Vector3DInt.h`, `Location.h`,
`RightHandedVector3D.h`, `Velocity.h`, `Acceleration.h`,
`AngularVelocity.h`, `Quaternion.h`, `Rotation.h` and `Transform.h`.

This module adds only what ThreeMojo does not have. The rest is reused:

- A CARLA `Vector3D` or `Location` is a `math.vector3.Vector3` in meters,
  and a `Vector2D` is a `math.vector2.Vector2`. `Dot`, `Cross`,
  `Distance` and `DistanceSquared` are `Vector3.dot`, `Vector3.cross`,
  `Vector3.distance_to` and `Vector3.distance_to_squared`.
- `Math::Clamp` and `Math::LinearLerp` are `math.utils.clamp` and
  `math.utils.lerp`, which compute the same products in the same order.
- `Math::ToDegrees`, `ToRadians`, `Pi` and `Pi2` are the `Angle` unit
  conversions in `units.si`.
- `Math::GetForwardVector`, `GetRightVector` and `GetUpVector` are
  `CarlaRotation.forward_vector`, `right_vector` and `up_vector`. They
  multiply the same matrix row by a unit axis, so they give the same
  numbers.
- A CARLA `Quaternion` is a `math.quaternion.Quaternion`. The Hamilton
  product, the conjugate, the length, `UnitQuaternion` and
  `RotatedVector` are its `*`, `conjugate`, `length`, `normalize` and
  `rotate`. This module adds the conversions to and from a CARLA
  rotation, which flip the handedness, and CARLA's `Inverse`.

**Differences from CARLA.** The helpers take and return unit types where
CARLA passes bare floats: an arc length is a `Length`, a heading an
`Angle` and a curvature an `InverseLength`. `Vector3D`'s
`operator/(float, Vector3D)` is not ported: it divides the vector by the
number, which reads as the opposite.
"""

from extensions.carla.transform import CarlaRotation, CarlaTransform
from math.matrix4 import Matrix4
from math.quaternion import Quaternion
from math.utils import clamp
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.ffi import external_call
from std.math import asin, atan2, cos, floor, pi, sin, sqrt
from units.si import (
    DEGREE,
    DEGREE_PER_SECOND,
    METER,
    METER_PER_SECOND,
    METER_PER_SECOND_SQUARED,
    RADIAN,
    Acceleration,
    Angle,
    AngularVelocity,
    InverseLength,
    Length,
    Velocity,
)

# Twice the machine epsilon of a `float`, CARLA's `MakeUnitVector` default.
comptime UNIT_VECTOR_EPSILON: Float32 = 2.0 * 1.1920928955078125e-07


# --- Math ---------------------------------------------------------------


def dot_2d(a: Vector3, b: Vector3) -> Float32:
    """Return the dot product of the x and y parts, `Math::Dot2D`.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        The sum a.x b.x + a.y b.y.
    """
    return a.x * b.x + a.y * b.y


def distance_squared_2d(a: Vector3, b: Vector3) -> Float32:
    """Return the squared distance in the x-y plane, `DistanceSquared2D`.

    Args:
        a: The first point, in meters.
        b: The second point, in meters.

    Returns:
        The squared distance, in square meters.
    """
    var dx = b.x - a.x
    var dy = b.y - a.y
    return dx * dx + dy * dy


def distance_2d(a: Vector3, b: Vector3) -> Length:
    """Return the distance in the x-y plane, `Math::Distance2D`.

    Args:
        a: The first point, in meters.
        b: The second point, in meters.

    Returns:
        The distance. The z parts do not count.
    """
    return Length(sqrt(distance_squared_2d(a, b)), METER)


def vector_angle(a: Vector3, b: Vector3) -> Angle:
    """Return the angle between two vectors, `Math::GetVectorAngle`.

    Unlike `Vector3.angle_to`, this is CARLA's formula as it is: the
    cosine is not clamped, so a rounding past one gives NaN, and a zero
    vector gives NaN.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        The arc cosine of a . b / (|a| |b|).
    """
    # The C library's `acosf`: `std.math.acos` gives zero for a NaN or a
    # cosine past one, where C++ gives NaN.
    var cosine = a.dot(b) / (a.length() * b.length())
    return Angle(external_call["acosf", Float32](cosine), RADIAN)


def distance_segment_to_point(
    p: Vector3, v: Vector3, w: Vector3
) -> Tuple[Length, Length]:
    """Project a point on a segment in the x-y plane,
    `Math::DistanceSegmentToPoint`.

    Args:
        p: The point.
        v: The start of the segment.
        w: The end of the segment.

    Returns:
        The distance from `v` to the projection along the segment, and the
        distance from `p` to the projection. The z parts do not count. A
        segment of no length gives zero and the distance from `v` to `p`.
    """
    var l2 = distance_squared_2d(v, w)
    var l = sqrt(l2)
    if l2 == 0.0:
        return (Length(0, METER), distance_2d(v, p))
    var dot_p_w = dot_2d(p - v, w - v)
    var t = clamp(dot_p_w / l2, 0, 1)
    var projection = v + (w - v) * t
    return (Length(t * l, METER), distance_2d(projection, p))


def rotate_point_on_origin_2d(p: Vector3, angle: Angle) -> Vector3:
    """Turn a point about the z axis, `Math::RotatePointOnOrigin2D`.

    Args:
        p: The point. Its z part is dropped.
        angle: The turn. Plus turns plus x toward plus y.

    Returns:
        The turned point, with z zero.
    """
    var radians = angle.to(RADIAN)
    var s = sin(radians)
    var c = cos(radians)
    return Vector3(p.x * c - p.y * s, p.x * s + p.y * c, 0)


def distance_arc_to_point(
    p: Vector3,
    start_pos: Vector3,
    length: Length,
    heading: Angle,
    curvature: InverseLength,
) -> Tuple[Length, Length]:
    """Project a point on an arc in the x-y plane,
    `Math::DistanceArcToPoint`.

    The arc is in CARLA's frame, so y and the heading are negated first,
    as CARLA does. A curvature of zero is not an arc: CARLA divides by it.

    Args:
        p: The point.
        start_pos: Where the arc starts.
        length: The length of the arc.
        heading: The heading at the start.
        curvature: The curvature. Its sign says which way the arc turns.

    Returns:
        The distance along the arc to the projection of `p`, and the
        distance from `p` to it. When the projection falls off the arc, the
        nearer end: zero or `length`, and the distance to that end.
    """
    var point = Vector3(p.x, -p.y, p.z)
    var start = Vector3(start_pos.x, -start_pos.y, start_pos.z)
    var head = -heading.to(RADIAN)
    var k = -curvature.value
    if k < 0.0:
        point.y = -point.y
        start.y = -start.y
        head = -head
        k = -k
    var rotated_p = rotate_point_on_origin_2d(
        point - start, Angle(-head, RADIAN)
    )
    var radius = 1.0 / k
    var circ_center = Vector3(0, radius, 0)
    if rotated_p == circ_center:
        return (Length(0, METER), Length(radius, METER))
    var intersection = (
        make_unit_vector(rotated_p - circ_center) * radius + circ_center
    )
    var last_point_angle = length.value / radius
    comptime pi_half = Float32(pi) / 2.0
    var angle = atan2(intersection.y - radius, intersection.x) + pi_half
    if angle < 0.0:
        angle += Float32(pi) * 2.0
    if angle <= last_point_angle:
        return (
            Length(angle * radius, METER),
            distance_2d(intersection, rotated_p),
        )
    var start_dist = distance_2d(Vector3(0, 0, 0), rotated_p)
    var end_pos = Vector3(
        radius * cos(last_point_angle - pi_half),
        radius * sin(last_point_angle - pi_half) + circ_center.y,
        0,
    )
    var end_dist = distance_2d(end_pos, rotated_p)
    if start_dist < end_dist:
        return (Length(0, METER), start_dist)
    return (length, end_dist)


def generate_range(a: Int, b: Int) -> List[Int]:
    """Return the whole numbers from `a` to `b`, `Math::GenerateRange`.

    Args:
        a: The first number.
        b: The last number. It can be below `a`.

    Returns:
        The list a, a + 1, ..., b when a < b, else a, a - 1, ..., b.
        Both ends are included.
    """
    var result = List[Int]()
    if a < b:
        for i in range(a, b + 1):  # pragma: no branch
            result.append(i)
    else:
        for i in range(a, b - 1, -1):  # pragma: no branch
            result.append(i)
    return result^


# --- Vector3D and Vector2D -------------------------------------------------


def make_unit_vector(
    v: Vector3, epsilon: Float32 = UNIT_VECTOR_EPSILON
) -> Vector3:
    """Scale a vector to length one, `Vector3D::MakeUnitVector`.

    Unlike `Vector3.normalize`, a vector no longer than `epsilon` comes
    back as it is.

    Args:
        v: The vector.
        epsilon: The length at or below which the vector is kept.

    Returns:
        The unit vector, or `v` itself.
    """
    var length = v.length()
    if length <= max(epsilon, 0.0):
        return v
    var k = 1.0 / length
    return Vector3(v.x * k, v.y * k, v.z * k)


def make_unit_vector_2d(
    v: Vector2, epsilon: Float32 = UNIT_VECTOR_EPSILON
) -> Vector2:
    """Scale a vector to length one, `Vector2D::MakeUnitVector`.

    Args:
        v: The vector.
        epsilon: The length at or below which the vector is kept.

    Returns:
        The unit vector, or `v` itself.
    """
    var length = v.length()
    if length <= max(epsilon, 0.0):
        return v
    var k = 1.0 / length
    return Vector2(v.x * k, v.y * k)


def squared_length_2d(v: Vector3) -> Float32:
    """Return x squared plus y squared, `Vector3D::SquaredLength2D`.

    Args:
        v: The vector.

    Returns:
        The squared length of its x-y part.
    """
    return v.x * v.x + v.y * v.y


def length_2d(v: Vector3) -> Float32:
    """Return the length of the x-y part, `Vector3D::Length2D`.

    Args:
        v: The vector.

    Returns:
        The square root of x squared plus y squared.
    """
    return sqrt(squared_length_2d(v))


def vector_abs(v: Vector3) -> Vector3:
    """Return each part's magnitude, `Vector3D::Abs`.

    Args:
        v: The vector.

    Returns:
        (|x|, |y|, |z|).
    """
    return Vector3(abs(v.x), abs(v.y), abs(v.z))


# --- Vector3DInt -----------------------------------------------------------


def _truncated_quotient(a: Int32, b: Int32) -> Int32:
    """Divide as C++ does: the quotient rounds toward zero."""
    var q = a // b
    if q < 0 and q * b != a:
        q += 1
    return q


@fieldwise_init
struct Vector3DInt(Equatable, ImplicitlyCopyable, Writable):
    """Three 32-bit whole numbers, CARLA's `geom::Vector3DInt`."""

    var x: Int32
    var y: Int32
    var z: Int32

    def squared_length(self) -> Int64:
        """Return x squared plus y squared plus z squared.

        CARLA squares in 32 bits, which can overflow. This squares in 64.

        Returns:
            The squared length.
        """
        var x = Int64(self.x)
        var y = Int64(self.y)
        var z = Int64(self.z)
        return x * x + y * y + z * z

    def length(self) -> Float64:
        """Return the length.

        Returns:
            The square root of `squared_length`.
        """
        return sqrt(Float64(self.squared_length()))

    def __add__(self, other: Self) -> Self:
        """Add part by part.

        Args:
            other: The other vector.

        Returns:
            The sum.
        """
        return Self(self.x + other.x, self.y + other.y, self.z + other.z)

    def __sub__(self, other: Self) -> Self:
        """Subtract part by part.

        Args:
            other: The other vector.

        Returns:
            The difference.
        """
        return Self(self.x - other.x, self.y - other.y, self.z - other.z)

    def __mul__(self, factor: Int32) -> Self:
        """Scale by a whole number.

        Args:
            factor: The factor.

        Returns:
            The scaled vector.
        """
        return Self(self.x * factor, self.y * factor, self.z * factor)

    def __truediv__(self, divisor: Int32) raises -> Self:
        """Divide by a whole number, rounding toward zero as C++ does.

        Args:
            divisor: The divisor.

        Returns:
            The divided vector.

        Raises:
            Error: If the divisor is zero.
        """
        if divisor == 0:
            raise Error("A Vector3DInt cannot be divided by zero")
        return Self(
            _truncated_quotient(self.x, divisor),
            _truncated_quotient(self.y, divisor),
            _truncated_quotient(self.z, divisor),
        )

    def __eq__(self, other: Self) -> Bool:
        """Return True if every part is equal.

        Args:
            other: The other vector.

        Returns:
            Whether the vectors are equal.
        """
        return self.x == other.x and self.y == other.y and self.z == other.z

    def to_location(self) -> Vector3:
        """Return this vector as a location, CARLA's `Location(Vector3DInt)`.

        Returns:
            The same numbers as floats, in meters.
        """
        return Vector3(Float32(self.x), Float32(self.y), Float32(self.z))

    def write_to(self, mut writer: Some[Writer]):
        """Write the vector.

        Args:
            writer: The destination.
        """
        writer.write(
            "Vector3DInt(x=", self.x, ", y=", self.y, ", z=", self.z, ")"
        )


# --- RightHandedVector3D ----------------------------------------------------


def to_right_handed(v: Vector3) -> Vector3:
    """Return a CARLA vector in the right-handed frame,
    `RightHandedVector3D(Vector3D)`.

    Args:
        v: A vector in CARLA's left-handed frame.

    Returns:
        The same vector with y negated.
    """
    return Vector3(v.x, -v.y, v.z)


def from_right_handed(v: Vector3) -> Vector3:
    """Return a right-handed vector in CARLA's frame,
    `RightHandedVector3D::operator Vector3D`.

    Args:
        v: A vector in the right-handed frame.

    Returns:
        The same vector with y negated.
    """
    return Vector3(v.x, -v.y, v.z)


# --- Velocity, Acceleration and AngularVelocity ------------------------------


@fieldwise_init
struct VelocityVector(ImplicitlyCopyable):
    """A linear velocity, CARLA's `geom::Velocity`, in meters per second."""

    var x: Velocity
    var y: Velocity
    var z: Velocity

    @staticmethod
    def from_centimeters_per_second(v: Vector3) -> VelocityVector:
        """Convert from centimeters per second, the unit CARLA's simulator
        plugin works in.

        Args:
            v: The velocity, in centimeters per second.

        Returns:
            The velocity, each part scaled by 1e-2.
        """
        return VelocityVector(
            Velocity(v.x * 1e-2, METER_PER_SECOND),
            Velocity(v.y * 1e-2, METER_PER_SECOND),
            Velocity(v.z * 1e-2, METER_PER_SECOND),
        )

    def to_centimeters_per_second(self) -> Vector3:
        """Convert to centimeters per second, the unit CARLA's simulator
        plugin works in.

        Returns:
            Each part scaled by 1e2.
        """
        return Vector3(
            self.x.value * 1e2, self.y.value * 1e2, self.z.value * 1e2
        )

    def vector(self) -> Vector3:
        """Return the three parts in meters per second.

        Returns:
            The bare vector.
        """
        return Vector3(self.x.value, self.y.value, self.z.value)

    def length(self) -> Velocity:
        """Return the speed.

        Returns:
            The length of the vector.
        """
        return Velocity(self.vector().length(), METER_PER_SECOND)


@fieldwise_init
struct AccelerationVector(ImplicitlyCopyable):
    """A linear acceleration, CARLA's `geom::Acceleration`."""

    var x: Acceleration
    var y: Acceleration
    var z: Acceleration

    @staticmethod
    def from_centimeters_per_second_squared(a: Vector3) -> AccelerationVector:
        """Convert from centimeters per second squared, the unit CARLA's
        simulator plugin works in.

        Args:
            a: The acceleration, in centimeters per second squared.

        Returns:
            The acceleration, each part scaled by 1e-2.
        """
        return AccelerationVector(
            Acceleration(a.x * 1e-2, METER_PER_SECOND_SQUARED),
            Acceleration(a.y * 1e-2, METER_PER_SECOND_SQUARED),
            Acceleration(a.z * 1e-2, METER_PER_SECOND_SQUARED),
        )

    def to_centimeters_per_second_squared(self) -> Vector3:
        """Convert to centimeters per second squared, the unit CARLA's
        simulator plugin works in.

        Returns:
            Each part scaled by 1e2.
        """
        return Vector3(
            self.x.value * 1e2, self.y.value * 1e2, self.z.value * 1e2
        )

    def vector(self) -> Vector3:
        """Return the three parts in meters per second squared.

        Returns:
            The bare vector.
        """
        return Vector3(self.x.value, self.y.value, self.z.value)


@fieldwise_init
struct AngularVelocityVector(ImplicitlyCopyable):
    """An angular velocity, CARLA's `geom::AngularVelocity`.

    CARLA carries degrees per second. The parts here are `AngularVelocity`
    quantities, so they read back in any unit.
    """

    var x: AngularVelocity
    var y: AngularVelocity
    var z: AngularVelocity

    @staticmethod
    def from_degrees_per_second(v: Vector3) -> AngularVelocityVector:
        """Convert from degrees per second, the unit CARLA's simulator
        plugin works in.

        Args:
            v: The angular velocity, in degrees per second.

        Returns:
            The angular velocity.
        """
        return AngularVelocityVector(
            AngularVelocity(v.x, DEGREE_PER_SECOND),
            AngularVelocity(v.y, DEGREE_PER_SECOND),
            AngularVelocity(v.z, DEGREE_PER_SECOND),
        )

    def to_degrees_per_second(self) -> Vector3:
        """Convert to degrees per second, the unit CARLA's simulator plugin
        works in.

        Returns:
            The three parts in degrees per second.
        """
        return Vector3(
            self.x.to(DEGREE_PER_SECOND),
            self.y.to(DEGREE_PER_SECOND),
            self.z.to(DEGREE_PER_SECOND),
        )


# --- Quaternion --------------------------------------------------------------


def quaternion_from_rotation(rotation: CarlaRotation) -> Quaternion:
    """Convert a CARLA rotation, `Quaternion(Rotation)`.

    Yaw and roll are negated, so the quaternion works in a right-handed
    frame. Pitch is kept.

    Args:
        rotation: The rotation.

    Returns:
        The unit quaternion.
    """
    comptime to_radians = 0.017453292519943295
    var half_yaw = Float32(Float64(-rotation.yaw) * to_radians) * 0.5
    var half_pitch = Float32(Float64(rotation.pitch) * to_radians) * 0.5
    var half_roll = Float32(Float64(-rotation.roll) * to_radians) * 0.5
    var cy = cos(half_yaw)
    var sy = sin(half_yaw)
    var cp = cos(half_pitch)
    var sp = sin(half_pitch)
    var cr = cos(half_roll)
    var sr = sin(half_roll)
    return Quaternion(
        cy * cp * sr - sy * sp * cr,
        cy * sp * cr + sy * cp * sr,
        sy * cp * cr - cy * sp * sr,
        cy * cp * cr + sy * sp * sr,
    )


def rotation_from_quaternion(q: Quaternion) -> CarlaRotation:
    """Convert a quaternion to a CARLA rotation, `Quaternion::Rotator`.

    Args:
        q: The quaternion.

    Returns:
        The rotation, with yaw and roll negated back. The sine of the
        pitch is clamped to -1 through 1.
    """
    var sin_pitch = 2.0 * (q.w * q.y - q.z * q.x)
    var clamped = sin_pitch
    if sin_pitch > 1.0:
        clamped = 1.0
    elif sin_pitch < -1.0:
        clamped = -1.0
    var pitch = asin(clamped)
    var roll = atan2(
        2.0 * (q.w * q.x + q.y * q.z), 1.0 - 2.0 * (q.x * q.x + q.y * q.y)
    )
    var yaw = atan2(
        2.0 * (q.w * q.z + q.x * q.y), 1.0 - 2.0 * (q.y * q.y + q.z * q.z)
    )
    comptime to_degrees = 57.29577951308232
    # The fields are set in degrees directly: a trip through `Angle`,
    # which holds radians, would move the last bit.
    var out = CarlaRotation(
        Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE)
    )
    out.pitch = Float32(Float64(pitch) * to_degrees)
    out.yaw = Float32(Float64(-yaw) * to_degrees)
    out.roll = Float32(Float64(-roll) * to_degrees)
    return out


def quaternion_inverse(q: Quaternion) -> Quaternion:
    """Return the inverse, CARLA's `Quaternion::Inverse`.

    Unlike `Quaternion.invert`, which only conjugates, this divides by the
    squared length.

    Args:
        q: The quaternion.

    Returns:
        The conjugate over the squared length, or the identity when the
        squared length is zero or less.
    """
    var n2 = q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w
    if n2 <= 0.0:
        return Quaternion.identity()
    var k = 1.0 / n2
    return Quaternion(-q.x * k, -q.y * k, -q.z * k, q.w * k)


def quaternion_inverse_rotate(q: Quaternion, v: Vector3) -> Vector3:
    """Turn a right-handed vector back, `InverseRotatedVector`.

    Args:
        q: The quaternion.
        v: A vector in the right-handed frame.

    Returns:
        The vector turned by `quaternion_inverse(q)`.
    """
    return quaternion_inverse(q).rotate(v)


def quaternion_forward_vector(q: Quaternion) -> Vector3:
    """Return where plus x points, `Quaternion::GetForwardVector`.

    Args:
        q: The quaternion.

    Returns:
        A unit vector in CARLA's left-handed frame.
    """
    return from_right_handed(q.rotate(to_right_handed(Vector3(1, 0, 0))))


def quaternion_right_vector(q: Quaternion) -> Vector3:
    """Return where plus y points, `Quaternion::GetRightVector`.

    Args:
        q: The quaternion.

    Returns:
        A unit vector in CARLA's left-handed frame.
    """
    return from_right_handed(q.rotate(to_right_handed(Vector3(0, 1, 0))))


def quaternion_up_vector(q: Quaternion) -> Vector3:
    """Return where plus z points, `Quaternion::GetUpVector`.

    Args:
        q: The quaternion.

    Returns:
        A unit vector in CARLA's left-handed frame.
    """
    return from_right_handed(q.rotate(to_right_handed(Vector3(0, 0, 1))))


# --- Rotation and Transform --------------------------------------------------


def rotation_sum(a: CarlaRotation, b: CarlaRotation) -> CarlaRotation:
    """Add two rotations angle by angle, `Rotation::operator+`.

    Args:
        a: The first rotation.
        b: The second rotation.

    Returns:
        The sums of the pitches, the yaws and the rolls.
    """
    var out = a
    out.pitch = a.pitch + b.pitch
    out.yaw = a.yaw + b.yaw
    out.roll = a.roll + b.roll
    return out


def rotation_difference(a: CarlaRotation, b: CarlaRotation) -> CarlaRotation:
    """Subtract two rotations angle by angle, `Rotation::operator-`.

    Args:
        a: The first rotation.
        b: The rotation to subtract.

    Returns:
        The differences of the pitches, the yaws and the rolls.
    """
    var out = a
    out.pitch = a.pitch - b.pitch
    out.yaw = a.yaw - b.yaw
    out.roll = a.roll - b.roll
    return out


def rotations_equal(a: CarlaRotation, b: CarlaRotation) -> Bool:
    """Compare two rotations angle by angle, each wrapped to one turn.

    `CarlaRotation.__eq__` compares the three angles as they are. This
    port also calls two rotations equal when each pair of angles differs
    by whole turns, so a yaw of 370 degrees equals a yaw of 10 degrees,
    and 180 equals -180. That is the usual angle-wrapping comparison:
    each angle is wrapped into [-180, 180) degrees, and the wrapped
    angles must be equal.

    Args:
        a: The first rotation.
        b: The second rotation.

    Returns:
        Whether the wrapped angles are equal.
    """
    return (
        _wrapped_degrees(a.pitch) == _wrapped_degrees(b.pitch)
        and _wrapped_degrees(a.yaw) == _wrapped_degrees(b.yaw)
        and _wrapped_degrees(a.roll) == _wrapped_degrees(b.roll)
    )


def _wrapped_degrees(angle: Float32) -> Float32:
    """Wrap an angle in degrees into [-180, 180)."""
    return angle - 360 * floor((angle + 180) / 360)


def transforms_equal(a: CarlaTransform, b: CarlaTransform) -> Bool:
    """Compare two transforms, CARLA's `Transform::operator==`.

    Args:
        a: The first transform.
        b: The second transform.

    Returns:
        Whether the locations are equal and `rotations_equal` holds.
    """
    return a.location == b.location and rotations_equal(a.rotation, b.rotation)


def transform_vector(transform: CarlaTransform, v: Vector3) -> Vector3:
    """Turn a vector without moving it, `Transform::TransformVector`.

    Args:
        transform: The transform.
        v: A direction in the transform's local frame.

    Returns:
        The direction in the parent frame.
    """
    return transform.rotation.rotate_vector(v)


def inverse_matrix(transform: CarlaTransform) -> Matrix4:
    """Return the 4x4 form of the inverse, `Transform::GetInverseMatrix`.

    Args:
        transform: The transform.

    Returns:
        The transposed rotation, and the translation
        `inverse_transform_point` gives the origin. It takes parent CARLA
        points to local CARLA points.
    """
    var r = transform.rotation
    var f = r.rotate_vector(Vector3(1, 0, 0))
    var s = r.rotate_vector(Vector3(0, 1, 0))
    var u = r.rotate_vector(Vector3(0, 0, 1))
    var a = transform.inverse_transform_point(Vector3(0, 0, 0))
    var m = Matrix4()
    m.set(
        f.x, f.y, f.z, a.x, s.x, s.y, s.z, a.y, u.x, u.y, u.z, a.z, 0, 0, 0, 1
    )
    return m
