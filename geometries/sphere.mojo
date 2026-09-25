# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sphere, from three.js `src/geometries/SphereGeometry.js`.

Built the usual way, as a grid of latitude and longitude lines. Vertices run
from the north pole to the south, and each ring repeats its first vertex at
the end: the seam where longitude wraps needs two vertices at the same place,
because they carry different texture coordinates: u is 0 on one and 1 on the
other, and a single shared vertex would have to run the whole image backwards
across the last column to reconcile them.

The poles are where this gets fiddly. A quad against a pole has two of its
corners in the same spot, so one of its two triangles is degenerate and is
skipped rather than emitted with zero area.

Each vertex's normal is simply the direction it lies from the center, so
neighboring triangles agree along their shared edges and the renderer's
interpolation hides the facets. That is the whole difference between this and
a box, where the four corners of a face deliberately agree with each other and
disagree with the next face.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from std.math import cos, isfinite, pi, sin
from units.si import Angle, Length, RADIAN


def sphere(
    radius: Length,
    width_segments: Int = 32,
    height_segments: Int = 16,
    phi_start: Angle = Angle(0.0, RADIAN),
    phi_length: Angle = Angle(2 * pi, RADIAN),
    theta_start: Angle = Angle(0.0, RADIAN),
    theta_length: Angle = Angle(pi, RADIAN),
) raises -> BufferGeometry:
    """Return a sphere centered on the origin, or a part of one: three.js's
    `SphereGeometry`.

    Args:
        radius: How far the surface lies from the center.
        width_segments: Divisions around the equator; at least three.
            Thirty-two by default, three.js's `SphereGeometry` default.
        height_segments: Divisions from pole to pole; at least two.
            Sixteen by default, as there.
        phi_start: Where the surface starts around the y axis, from -x
            toward +z. Zero by default.
        phi_length: How far it runs around. A whole turn by default.
        theta_start: Where it starts down from the north pole. Zero by
            default.
        theta_length: How far it runs down. Half a turn, pole to pole,
            by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and an
        index buffer.

    Raises:
        Error: If the radius is not positive, either segment count is too
            small to close a surface, or an angle is not finite.
    """
    if radius.value <= 0:
        raise Error("A sphere needs a positive radius")
    if width_segments < 3:
        raise Error("A sphere needs at least three segments around")
    if height_segments < 2:
        raise Error("A sphere needs at least two segments from pole to pole")
    var phi0 = phi_start.to(RADIAN)
    var phi_run = phi_length.to(RADIAN)
    var theta0 = theta_start.to(RADIAN)
    var theta_run = theta_length.to(RADIAN)
    if not (
        isfinite(phi0)
        and isfinite(phi_run)
        and isfinite(theta0)
        and isfinite(theta_run)
    ):
        raise Error("A sphere's angles must be finite")
    # three.js's `thetaEnd`: a part reaches the south pole only when its
    # end is past it.
    var theta_end = min(theta0 + theta_run, Float32(pi))

    var r = radius.value
    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()

    # One extra column, so the seam has a vertex on each side of the wrap.
    # Segment counts were validated above, so none of these run zero times.
    for ring in range(height_segments + 1):  # pragma: no branch
        var ring_fraction = Float32(ring) / Float32(height_segments)
        var theta = theta0 + ring_fraction * theta_run
        var sin_theta = sin(theta)
        var cos_theta = cos(theta)
        # At a pole every column's vertex is the same point, and the one
        # triangle each quad keeps there has its tip at it. three.js moves
        # the tip's u half a column toward the middle of that triangle --
        # forward at the north pole, back at the south -- so the texture
        # meets the pole squarely rather than sheared into a pinwheel.
        # Only at a real pole: a part that starts below the north pole or
        # ends above the south has no tip there.
        var u_offset = Float32(0)
        if ring == 0 and theta0 == 0:
            u_offset = 0.5 / Float32(width_segments)
        elif ring == height_segments and theta_end == Float32(pi):
            u_offset = -0.5 / Float32(width_segments)
        for column in range(width_segments + 1):  # pragma: no branch
            var column_fraction = Float32(column) / Float32(width_segments)
            var phi = phi0 + column_fraction * phi_run
            var nx = -cos(phi) * sin_theta
            var ny = cos_theta
            var nz = sin(phi) * sin_theta
            data.append(nx * r)
            data.append(ny * r)
            data.append(nz * r)
            # Already unit length: the normal of a sphere at the origin is
            # just the direction the point lies in.
            normals.append(nx)
            normals.append(ny)
            normals.append(nz)
            # u wraps once around the equator; v runs 1 at the north pole to
            # 0 at the south, because texture space has its origin at the
            # bottom while `ring` counts downwards from the top.
            uvs.append(column_fraction + u_offset)
            uvs.append(1 - ring_fraction)

    var stride = width_segments + 1
    var index = List[Int]()
    for ring in range(height_segments):  # pragma: no branch
        for column in range(width_segments):  # pragma: no branch
            var top_left = ring * stride + column
            var top_right = top_left + 1
            var bottom_left = top_left + stride
            var bottom_right = bottom_left + 1
            # At a pole two of the quad's corners coincide, so only one of its
            # triangles has any area. The quad is cut from top left to bottom
            # right, three.js's `(a, b, d)` and `(b, c, d)`, so the triangle
            # kept at a pole has its tip in the column at its base's left:
            # the one the half-column u offset above was made for.
            # A ring at a real pole keeps only the triangle with area.
            if ring != 0 or theta0 > 0:
                index.append(top_right)
                index.append(top_left)
                index.append(bottom_right)
            if ring != height_segments - 1 or theta_end < Float32(pi):
                index.append(top_left)
                index.append(bottom_left)
                index.append(bottom_right)

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(index^)
    return geometry^
