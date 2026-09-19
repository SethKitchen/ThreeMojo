# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Signed-distance primitives shared by the humanoid bones.

Each bone builds an implicit solid from capsules, ellipsoids and smooth
unions. The mesh builder takes the zero set. The mass sampler classifies
the interior. This file holds the arithmetic those solids share.
"""

from extensions.humanoid.sex import Sex
from extensions.humanoid.side import BodySide
from extensions.humanoid.spec import MAX_STATURE, MIN_STATURE
from math.vector3 import Vector3
from std.math import isfinite, max, min, pi, sqrt
from units.si import Angle, Length


trait DistanceField(Copyable, Movable):
    """An implicit solid whose zero set is the bone surface."""

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the solid, in meters.

        Negative is inside. Zero is the surface.
        """
        ...


@fieldwise_init
struct Bounds(ImplicitlyCopyable):
    """An axis-aligned box that grows to hold bone primitives."""

    var low: Vector3
    var high: Vector3

    def include_sphere(mut self, center: Vector3, radius: Float32):
        """Grow the box to hold a sphere.

        Args:
            center: Sphere center, in meters.
            radius: Sphere radius, in meters.
        """
        self.include_ellipsoid(center, Vector3(radius, radius, radius))

    def include_ellipsoid(mut self, center: Vector3, radii: Vector3):
        """Grow the box to hold an ellipsoid.

        Args:
            center: Ellipsoid center, in meters.
            radii: Semi-axes, in meters.
        """
        self.low = Vector3(
            min(self.low.x, center.x - radii.x),
            min(self.low.y, center.y - radii.y),
            min(self.low.z, center.z - radii.z),
        )
        self.high = Vector3(
            max(self.high.x, center.x + radii.x),
            max(self.high.y, center.y + radii.y),
            max(self.high.z, center.z + radii.z),
        )

    def padded(self, pad: Float32) -> Bounds:
        """Return this box grown by `pad` on every side.

        Args:
            pad: Extra margin, in meters.

        Returns:
            A larger box.
        """
        return Bounds(
            Vector3(self.low.x - pad, self.low.y - pad, self.low.z - pad),
            Vector3(self.high.x + pad, self.high.y + pad, self.high.z + pad),
        )


def empty_bounds() -> Bounds:
    """Return a box that grows from the first included primitive.

    Returns:
        A box whose first `include_*` call sets the extent.
    """
    var huge = Float32(1.0e9)
    return Bounds(
        Vector3(huge, huge, huge),
        Vector3(-huge, -huge, -huge),
    )


def check_spec(
    stature: Length, sex: Sex, side: BodySide, bone: String
) raises:
    """Refuse a spec a bone template cannot use.

    Args:
        stature: Standing height.
        sex: Osteological template.
        side: Left or right.
        bone: Name used in the error text.

    Raises:
        Error: If `sex` or `side` is not valid, or stature is not finite
            or is outside the software range.
    """
    if not sex.is_valid():
        raise Error("A " + bone + " needs a male or female template")
    if not side.is_valid():
        raise Error("A " + bone + " needs a left or right side")
    if not isfinite(stature.value):
        raise Error("A " + bone + "'s stature must be finite")
    if stature < MIN_STATURE:
        raise Error("A " + bone + "'s stature must be at least 1.2 meters")
    if stature > MAX_STATURE:
        raise Error("A " + bone + "'s stature cannot exceed 2.5 meters")


def positive_length(value: Length, name: String, bone: String) raises:
    """Refuse a length that is not finite or not positive.

    Args:
        value: The length to check.
        name: What the length measures.
        bone: Name used in the error text.

    Raises:
        Error: If `value` is not finite or is not positive.
    """
    if not isfinite(value.value):
        raise Error("A " + bone + " " + name + " must be finite")
    if value.value <= 0:
        raise Error("A " + bone + " " + name + " must be positive")


def non_negative_length(value: Length, name: String, bone: String) raises:
    """Refuse a length that is not finite or is negative.

    Args:
        value: The length to check.
        name: What the length measures.
        bone: Name used in the error text.

    Raises:
        Error: If `value` is not finite or is negative.
    """
    if not isfinite(value.value):
        raise Error("A " + bone + " " + name + " must be finite")
    if value.value < 0:
        raise Error("A " + bone + " " + name + " cannot be negative")


def finite_angle(value: Angle, name: String, bone: String) raises:
    """Refuse an angle that is not finite.

    Args:
        value: The angle to check.
        name: What the angle measures.
        bone: Name used in the error text.

    Raises:
        Error: If `value` is not finite.
    """
    if not isfinite(value.value):
        raise Error("A " + bone + " " + name + " must be finite")


def open_angle(value: Angle, name: String, bone: String) raises:
    """Refuse an angle that is not strictly between 0 and pi.

    Args:
        value: The angle to check.
        name: What the angle measures.
        bone: Name used in the error text.

    Raises:
        Error: If `value` is not finite or is not between 0 and 180 degrees.
    """
    finite_angle(value, name, bone)
    if value.value <= 0:
        raise Error("A " + bone + " " + name + " must be positive")
    if value.value >= pi:
        raise Error("A " + bone + " " + name + " must be less than 180 degrees")


def acute_angle(value: Angle, name: String, bone: String) raises:
    """Refuse an angle that is negative or 90 degrees or more.

    Args:
        value: The angle to check.
        name: What the angle measures.
        bone: Name used in the error text.

    Raises:
        Error: If `value` is not finite, is negative, or is 90 degrees or more.
    """
    finite_angle(value, name, bone)
    if value.value < 0:
        raise Error("A " + bone + " " + name + " cannot be negative")
    if value.value >= pi * Float32(0.5):
        raise Error("A " + bone + " " + name + " must be less than 90 degrees")


def finite_point(point: Vector3, name: String, bone: String) raises:
    """Refuse a landmark with a non-finite coordinate.

    Args:
        point: The landmark to check.
        name: What the landmark is.
        bone: Name used in the error text.

    Raises:
        Error: If any coordinate is not finite.
    """
    if not isfinite(point.x):
        raise Error("A " + bone + " " + name + " must be finite")
    if not isfinite(point.y):
        raise Error("A " + bone + " " + name + " must be finite")
    if not isfinite(point.z):
        raise Error("A " + bone + " " + name + " must be finite")


def clamp_unit(value: Float32) -> Float32:
    """Return `value` held to minus one through one, for `acos`."""
    if value < -1:
        return -1
    if value > 1:
        return 1
    return value


def flip_x(point: Vector3) -> Vector3:
    """Return `point` mirrored across the midline of the bone."""
    return Vector3(-point.x, point.y, point.z)


def bowed_station(
    t: Float32, a: Vector3, b: Vector3, bow: Vector3
) -> Vector3:
    """Return a centerline point at fraction `t` from `a` toward `b`.

    The bow offset peaks at mid-shaft, where `4 t (1 - t)` is one.
    """
    var s = 4 * t * (1 - t)
    return Vector3(
        a.x + t * (b.x - a.x) + s * bow.x,
        a.y + t * (b.y - a.y) + s * bow.y,
        a.z + t * (b.z - a.z) + s * bow.z,
    )


def abs_f(value: Float32) -> Float32:
    """Return `value` without its sign."""
    if value < 0:
        return -value
    return value


def smin(a: Float32, b: Float32, k: Float32) -> Float32:
    """Return a smooth minimum of `a` and `b` with blend radius `k`."""
    var h = k - abs_f(a - b)
    if h < 0:
        h = 0
    return min(a, b) - h * h * Float32(0.25) / k


def smax(a: Float32, b: Float32, k: Float32) -> Float32:
    """Return a smooth maximum of `a` and `b` with blend radius `k`."""
    return -smin(-a, -b, k)


def sd_sphere(point: Vector3, center: Vector3, radius: Float32) -> Float32:
    """Return the signed distance to a sphere."""
    return (point - center).length() - radius


def sd_segment(
    point: Vector3, a: Vector3, b: Vector3, radius_a: Float32, radius_b: Float32
) -> Float32:
    """Return the signed distance to a tapered capsule from `a` to `b`."""
    var along = b - a
    var from_a = point - a
    var span = along.dot(along)
    var t = Float32(0)
    if span > 0:
        t = from_a.dot(along) / span
        if t < 0:
            t = 0
        if t > 1:
            t = 1
    var radius = radius_a + (radius_b - radius_a) * t
    return (from_a - along * t).length() - radius


def reject(vector: Vector3, unit: Vector3) -> Vector3:
    """Return the part of `vector` perpendicular to unit `unit`."""
    var d = vector.dot(unit)
    return Vector3(
        vector.x - unit.x * d, vector.y - unit.y * d, vector.z - unit.z * d
    )


def cross(a: Vector3, b: Vector3) -> Vector3:
    """Return the cross product of `a` and `b` without mutating them."""
    var out = a
    out.cross(b)
    return out


def sd_ellipse_segment(
    point: Vector3,
    a: Vector3,
    b: Vector3,
    ml_a: Float32,
    ap_a: Float32,
    ml_b: Float32,
    ap_b: Float32,
    ml_hint: Vector3,
) -> Float32:
    """Return an approximate signed distance to a tapered elliptical capsule.

    Mediolateral radius is along `ml_hint` after projecting out the tangent.
    Anteroposterior radius is along the remaining anterior axis. The two
    diameters are independent.
    """
    var along = b - a
    var from_a = point - a
    var span = along.dot(along)
    var t = Float32(0)
    if span > 0:
        t = from_a.dot(along) / span
        if t < 0:
            t = 0
        if t > 1:
            t = 1
    var ml_r = ml_a + (ml_b - ml_a) * t
    var ap_r = ap_a + (ap_b - ap_a) * t
    var center = Vector3(
        a.x + along.x * t, a.y + along.y * t, a.z + along.z * t
    )
    var offset = point - center
    var tangent = Vector3(0, 1, 0)
    if span > 0:
        var inv = Float32(1) / sqrt(span)
        tangent = Vector3(along.x * inv, along.y * inv, along.z * inv)
    var ml_axis = reject(ml_hint, tangent)
    if ml_axis.length() < Float32(0.000001):
        ml_axis = reject(Vector3(0, 0, 1), tangent)
    ml_axis.normalize()
    var ap_axis = cross(tangent, ml_axis)
    ap_axis.normalize()
    var u = offset.dot(ml_axis)
    var v = offset.dot(ap_axis)
    var w = offset.dot(tangent)
    var px = u / ml_r
    var pz = v / ap_r
    var pr = sqrt(ml_r * ap_r)
    var py = w / pr
    var k0 = sqrt(px * px + py * py + pz * pz)
    var qx = px / ml_r
    var qy = py / pr
    var qz = pz / ap_r
    var k1 = sqrt(qx * qx + qy * qy + qz * qz)
    if k1 == 0:
        return -min(ml_r, ap_r)
    return k0 * (k0 - 1) / k1


def sd_ellipsoid(point: Vector3, center: Vector3, radii: Vector3) -> Float32:
    """Return an approximate signed distance to an ellipsoid."""
    var px = (point.x - center.x) / radii.x
    var py = (point.y - center.y) / radii.y
    var pz = (point.z - center.z) / radii.z
    var k0 = sqrt(px * px + py * py + pz * pz)
    var qx = px / radii.x
    var qy = py / radii.y
    var qz = pz / radii.z
    var k1 = sqrt(qx * qx + qy * qy + qz * qz)
    if k1 == 0:
        return -min(radii.x, min(radii.y, radii.z))
    return k0 * (k0 - 1) / k1


def field_gradient[
    F: DistanceField
](field: F, point: Vector3, epsilon: Float32) -> Vector3:
    """Return the unit outward normal of `field.distance` at `point`.

    Args:
        field: An implicit solid.
        point: The sample point, in meters.
        epsilon: Finite-difference step, in meters.

    Returns:
        A unit vector. A zero field gradient stays the zero vector.
    """
    var dx = field.distance(
        Vector3(point.x + epsilon, point.y, point.z)
    ) - field.distance(Vector3(point.x - epsilon, point.y, point.z))
    var dy = field.distance(
        Vector3(point.x, point.y + epsilon, point.z)
    ) - field.distance(Vector3(point.x, point.y - epsilon, point.z))
    var dz = field.distance(
        Vector3(point.x, point.y, point.z + epsilon)
    ) - field.distance(Vector3(point.x, point.y, point.z - epsilon))
    var normal = Vector3(dx, dy, dz)
    normal.normalize()
    return normal
