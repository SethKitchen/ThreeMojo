# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Cutting triangles against the near plane before they are projected.

Perspective projection divides by depth, so a vertex level with the camera
divides by zero and one behind it divides by a negative and comes out mirrored
through the origin. A triangle with one corner behind the camera does not
project to a slightly wrong triangle; it projects to a wildly wrong one,
usually a huge wedge across the whole image.

The fix is to cut the triangle where it crosses the near plane and project
only the part in front. The cut has to happen in camera space, before the
divide, because the near plane is only a plane there — projection is what
bends it.

Clipping a triangle against one plane leaves a polygon of three or four
corners, which is one or two triangles. The interpolation at each cut carries
the vertex colour with it, so a clipped triangle shades as though it were
never cut.
"""

from math.vector3 import Vector3
from render.framebuffer import Color


@fieldwise_init
struct ClipVertex(ImplicitlyCopyable):
    """A camera-space position with the colour already worked out for it."""

    var position: Vector3
    var color: Color


def _mix(a: UInt8, b: UInt8, t: Float32) -> UInt8:
    """Return one colour channel a fraction `t` of the way from `a` to `b`."""
    # `t` lies in [0, 1], so the result sits between the two inputs and can
    # never go negative; only the rounding on a 255 needs clamping.
    var value = Float32(a) + (Float32(b) - Float32(a)) * t + 0.5
    if value > 255:
        return 255
    return UInt8(value)


def _cross_at(a: ClipVertex, b: ClipVertex, near: Float32) -> ClipVertex:
    """Return the vertex where the edge from `a` to `b` meets the near plane.

    The camera looks down -z, so the plane is at z = -near and the crossing
    fraction comes from how far `a` is from it relative to the whole edge.
    """
    # Only called for an edge with one end in front of the plane and one
    # behind, so the ends differ in z and the span cannot be zero. The guard
    # is kept because dividing by zero here would silently produce NaN
    # coordinates rather than a visible error.
    var span = a.position.z - b.position.z
    var t = Float32(0)
    if span != 0:  # pragma: no branch
        t = (a.position.z + near) / span
    return ClipVertex(
        Vector3(
            a.position.x + (b.position.x - a.position.x) * t,
            a.position.y + (b.position.y - a.position.y) * t,
            -near,
        ),
        Color(
            _mix(a.color.r, b.color.r, t),
            _mix(a.color.g, b.color.g, t),
            _mix(a.color.b, b.color.b, t),
            _mix(a.color.a, b.color.a, t),
        ),
    )


def clip_near(
    a: ClipVertex, b: ClipVertex, c: ClipVertex, near: Float32
) raises -> List[ClipVertex]:
    """Return the part of a triangle in front of the near plane.

    Args:
        a: First corner, in camera space.
        b: Second corner.
        c: Third corner.
        near: Distance to the near plane; the plane sits at z = -near.

    Returns:
        Corners three at a time: empty if the triangle is entirely behind the
        plane, three if it survives whole or is cut to a triangle, six if the
        cut leaves a quadrilateral.

    Raises:
        Error: If `near` is not positive, which would put the plane behind the
            camera.
    """
    if near <= 0:
        raise Error("The near plane must be in front of the camera")

    var corners = List[ClipVertex]()
    corners.append(a)
    corners.append(b)
    corners.append(c)

    # Sutherland-Hodgman against the single plane: walk the edges, keeping
    # every corner in front and adding a crossing wherever an edge leaves or
    # enters.
    var kept = List[ClipVertex]()
    for position in range(3):  # pragma: no branch
        var current = corners[position]
        var following = corners[(position + 1) % 3]
        var current_in = current.position.z <= -near
        var following_in = following.position.z <= -near
        if current_in:
            kept.append(current)
        if current_in != following_in:
            kept.append(_cross_at(current, following, near))

    # Three or four corners, fanned from the first into one or two triangles.
    var triangles = List[ClipVertex]()
    for corner in range(1, len(kept) - 1):
        triangles.append(kept[0])
        triangles.append(kept[corner])
        triangles.append(kept[corner + 1])
    return triangles^
