# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Vectors, frames and rigid transforms for distance field sculpts.

`V3` is the generators' `Vec3d`, a `Float64` vector with three.js's
methods. The free functions here read like the sculpts they serve.
Coordinates are meters.
"""

from generators.utils import Vec3d
from std.math import cos, sin, sqrt

# A point or a direction, in meters.
comptime V3 = Vec3d


def v3(x: Float64, y: Float64, z: Float64) -> V3:
    """Return a vector.

    Args:
        x: Left, in meters.
        y: Up, in meters.
        z: Forward, in meters.

    Returns:
        The vector.
    """
    return V3(x, y, z)


def dot(a: V3, b: V3) -> Float64:
    """Return the dot product.

    Args:
        a: One vector.
        b: The other vector.

    Returns:
        The dot product.
    """
    return a.dot(b)


def cross(a: V3, b: V3) -> V3:
    """Return the cross product.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        `a` cross `b`.
    """
    return V3(
        a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x
    )


def length(a: V3) -> Float64:
    """Return the length.

    Args:
        a: The vector.

    Returns:
        The Euclidean length.
    """
    return a.length()


def distance(a: V3, b: V3) -> Float64:
    """Return the distance between two points.

    Args:
        a: One point.
        b: The other point.

    Returns:
        The distance.
    """
    return a.distance_to(b)


def normalize(a: V3) -> V3:
    """Return the vector made unit length. A zero vector stays zero.

    Args:
        a: The vector.

    Returns:
        The unit vector, or zero.
    """
    return a.normalized()


def lerp(a: V3, b: V3, t: Float64) -> V3:
    """Return the point a fraction of the way from `a` to `b`.

    Args:
        a: The start.
        b: The end.
        t: The fraction.

    Returns:
        The point.
    """
    return a.lerp(b, t)


def mirror(a: V3) -> V3:
    """Return the point mirrored to the animal's other side.

    Args:
        a: The point.

    Returns:
        The point with `x` negated.
    """
    return V3(-a.x, a.y, a.z)


def clamp(x: Float64, low: Float64, high: Float64) -> Float64:
    """Return `x` held between two bounds.

    Args:
        x: The value.
        low: The lower bound.
        high: The upper bound.

    Returns:
        The clamped value.
    """
    return low if x < low else (high if x > high else x)


def smoothstep(e0: Float64, e1: Float64, x: Float64) -> Float64:
    """Return the cubic Hermite step from `e0` to `e1`.

    Args:
        e0: Where the step starts.
        e1: Where the step ends.
        x: The value.

    Returns:
        Zero at or below `e0`, one at or above `e1`, smooth between.
    """
    var t = clamp((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def mix(a: Float64, b: Float64, t: Float64) -> Float64:
    """Return the linear blend of two numbers.

    Args:
        a: The value at zero.
        b: The value at one.
        t: The fraction.

    Returns:
        `a + (b - a) t`.
    """
    return a + (b - a) * t


@fieldwise_init
struct Frame(ImplicitlyCopyable):
    """An orthonormal frame: three unit axes."""

    var x: V3
    var y: V3
    var z: V3


def frame_zy(z_dir: V3, up_hint: V3) -> Frame:
    """Return a frame whose `z` follows `z_dir` and whose `y` is near `up_hint`.

    When the hint is parallel to `z_dir`, world +x seeds the frame.

    Args:
        z_dir: The direction of the frame's z axis.
        up_hint: A direction near the frame's y axis.

    Returns:
        The right-handed frame.
    """
    var z = normalize(z_dir)
    var x = cross(up_hint, z)
    if length(x) < 1e-6:
        x = cross(V3(1.0, 0.0, 0.0), z)
    x = normalize(x)
    return Frame(x, cross(z, x), z)


def rotate_about(v: V3, axis: V3, angle: Float64) -> V3:
    """Return a vector turned about a unit axis by Rodrigues' formula.

    Args:
        v: The vector.
        axis: The unit axis.
        angle: How far, in radians, counterclockwise looking down the axis.

    Returns:
        The turned vector.
    """
    var c = cos(angle)
    return (
        v * c + cross(axis, v) * sin(angle) + axis * (dot(axis, v) * (1.0 - c))
    )


@fieldwise_init
struct Rigid(ImplicitlyCopyable):
    """A rotation then a translation: `p -> x p.x + y p.y + z p.z + t`.

    The columns `x`, `y` and `z` are the images of the world axes.
    """

    var x: V3
    var y: V3
    var z: V3
    var t: V3

    def apply(self, p: V3) -> V3:
        """Return a point moved by the transform.

        Args:
            p: The point.

        Returns:
            The moved point.
        """
        return self.x * p.x + self.y * p.y + self.z * p.z + self.t

    def turn(self, d: V3) -> V3:
        """Return a direction turned by the transform's rotation.

        Args:
            d: The direction.

        Returns:
            The turned direction. Translation does not apply.
        """
        return self.x * d.x + self.y * d.y + self.z * d.z

    def inverse(self) -> Self:
        """Return the inverse transform. The rotation must be orthonormal.

        Returns:
            The transform that undoes this one.
        """
        var rx = V3(self.x.x, self.y.x, self.z.x)
        var ry = V3(self.x.y, self.y.y, self.z.y)
        var rz = V3(self.x.z, self.y.z, self.z.z)
        var inv = Rigid(rx, ry, rz, V3(0.0, 0.0, 0.0))
        return Rigid(rx, ry, rz, -inv.turn(self.t))

    def then(self, after: Self) -> Self:
        """Return the transform that applies this one, then `after`.

        Args:
            after: The transform applied second.

        Returns:
            The composition.
        """
        return Rigid(
            after.turn(self.x),
            after.turn(self.y),
            after.turn(self.z),
            after.apply(self.t),
        )


def identity() -> Rigid:
    """Return the transform that moves nothing.

    Returns:
        The identity.
    """
    return Rigid(
        V3(1.0, 0.0, 0.0),
        V3(0.0, 1.0, 0.0),
        V3(0.0, 0.0, 1.0),
        V3(0.0, 0.0, 0.0),
    )


def rotation_about(pivot: V3, axis: V3, angle: Float64) -> Rigid:
    """Return the turn about a line through `pivot`.

    Args:
        pivot: A point on the line. It stays where it is.
        axis: The unit direction of the line.
        angle: How far, in radians.

    Returns:
        The transform.
    """
    var x = rotate_about(V3(1.0, 0.0, 0.0), axis, angle)
    var y = rotate_about(V3(0.0, 1.0, 0.0), axis, angle)
    var z = rotate_about(V3(0.0, 0.0, 1.0), axis, angle)
    var turned = x * pivot.x + y * pivot.y + z * pivot.z
    return Rigid(x, y, z, pivot - turned)
