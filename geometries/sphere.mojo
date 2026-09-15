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
from std.math import cos, pi, sin
from units.si import Length


def sphere(
    radius: Length, width_segments: Int = 24, height_segments: Int = 16
) raises -> BufferGeometry:
    """Return a sphere centered on the origin.

    Args:
        radius: How far the surface lies from the center.
        width_segments: Divisions around the equator; at least three.
        height_segments: Divisions from pole to pole; at least two.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and an
        index buffer.

    Raises:
        Error: If the radius is not positive or either segment count is too
            small to close a surface.
    """
    if radius.value <= 0:
        raise Error("A sphere needs a positive radius")
    if width_segments < 3:
        raise Error("A sphere needs at least three segments around")
    if height_segments < 2:
        raise Error("A sphere needs at least two segments from pole to pole")

    var r = radius.value
    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()

    # One extra column, so the seam has a vertex on each side of the wrap.
    # Segment counts were validated above, so none of these run zero times.
    for ring in range(height_segments + 1):  # pragma: no branch
        var ring_fraction = Float32(ring) / Float32(height_segments)
        var theta = Float32(pi) * ring_fraction
        var sin_theta = sin(theta)
        var cos_theta = cos(theta)
        for column in range(width_segments + 1):  # pragma: no branch
            var column_fraction = Float32(column) / Float32(width_segments)
            var phi = 2 * Float32(pi) * column_fraction
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
            uvs.append(column_fraction)
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
            # triangles has any area.
            if ring != 0:
                index.append(top_left)
                index.append(bottom_left)
                index.append(top_right)
            if ring != height_segments - 1:
                index.append(top_right)
                index.append(bottom_left)
                index.append(bottom_right)

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(index^)
    return geometry^
