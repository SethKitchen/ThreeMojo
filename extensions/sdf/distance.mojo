# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Closed-form distances to simple shapes, for sculpts and painters.

The field's primitives use some of them. Painters use them to find
how far a point is from a feature without a whole sculpt. Distances
are meters and negative inside.
"""

from extensions.sdf.vector import (
    V3,
    clamp,
    dot,
    frame_zy,
    length,
)
from std.math import sqrt


def almond_distance(
    u: Float64, v: Float64, big_r: Float64, d: Float64
) -> Float64:
    """Return the signed distance to an almond in its plane.

    The almond is where two circles of radius `big_r` overlap. Their
    centers are `d` above and `d` below the origin, along `v`. This is
    the shape of an eye's aperture and of a lens primitive.

    Args:
        u: The point's coordinate across the almond.
        v: The point's coordinate along the almond's short axis.
        big_r: The circles' radius.
        d: The circles' offset from the origin.

    Returns:
        The distance. It is negative inside the almond.
    """
    var upper = sqrt(u * u + (v + d) * (v + d)) - big_r
    var lower = sqrt(u * u + (v - d) * (v - d)) - big_r
    return max(upper, lower)


def rect_distance(qx: Float64, qy: Float64) -> Float64:
    """Return the signed distance to a rectangle from its corner offsets.

    `qx` and `qy` are the point's folded coordinates less the half
    sizes: `abs(x) - hx` and `abs(y) - hy`. Subtract a radius from both
    offsets and from the result to round the corners.

    Args:
        qx: The offset across.
        qy: The offset up.

    Returns:
        The distance. It is negative inside the rectangle.
    """
    var ox = max(qx, 0.0)
    var oy = max(qy, 0.0)
    return sqrt(ox * ox + oy * oy) + min(max(qx, qy), 0.0)


def segment_param(p: V3, a: V3, b: V3) -> Float64:
    """Return where the nearest point of a segment is, as a fraction.

    Args:
        p: The point.
        a: The segment's start.
        b: The segment's end. It must differ from `a`.

    Returns:
        Zero at `a`, one at `b`.
    """
    var ab = b - a
    return clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0)


def segment_distance(p: V3, a: V3, b: V3) -> Float64:
    """Return the distance from a point to a segment.

    Args:
        p: The point.
        a: The segment's start.
        b: The segment's end. It must differ from `a`.

    Returns:
        The distance. It is never negative.
    """
    var u = segment_param(p, a, b)
    return length(p - (a + (b - a) * u))


def round_cone_estimate(
    p: V3, a: V3, b: V3, ra: Float64, rb: Float64
) -> Float64:
    """Return about the distance from a point to a round cone.

    The radius is interpolated at the segment's nearest point. This is
    exact for a cylinder and close for a gentle taper.

    Args:
        p: The point.
        a: The cone's start.
        b: The cone's end. It must differ from `a`.
        ra: The radius at `a`.
        rb: The radius at `b`.

    Returns:
        The estimated distance. It is negative inside.
    """
    var u = segment_param(p, a, b)
    return length(p - (a + (b - a) * u)) - (ra + (rb - ra) * u)


def ellipsoid_estimate(p: V3, c: V3, r: V3) -> Float64:
    """Return about the distance from a point to an axis-aligned ellipsoid.

    The point's radius in the ellipsoid's scaled space, less one, is
    multiplied by the smallest radius.

    Args:
        p: The point.
        c: The ellipsoid's center.
        r: The radii along `x`, `y` and `z`.

    Returns:
        The estimated distance. It is negative inside.
    """
    var q = V3((p.x - c.x) / r.x, (p.y - c.y) / r.y, (p.z - c.z) / r.z)
    return (length(q) - 1.0) * min(r.x, min(r.y, r.z))


def oriented_ellipsoid_estimate(
    p: V3, c: V3, z_dir: V3, up: V3, r: V3
) -> Float64:
    """Return about the distance from a point to a turned ellipsoid.

    The ellipsoid's frame is `frame_zy(z_dir, up)`. The estimate is as
    `ellipsoid_estimate` computes it in that frame.

    Args:
        p: The point.
        c: The ellipsoid's center.
        z_dir: The direction of the third radius.
        up: A direction near the second radius.
        r: The radii along the frame's axes.

    Returns:
        The estimated distance. It is negative inside.
    """
    var f = frame_zy(z_dir, up)
    var d = p - c
    var u = V3(dot(d, f.x) / r.x, dot(d, f.y) / r.y, dot(d, f.z) / r.z)
    return (length(u) - 1.0) * min(r.x, min(r.y, r.z))
