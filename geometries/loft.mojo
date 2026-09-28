# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A surface skinned through a row of cross sections, ported from three.js
`examples/jsm/geometries/LoftGeometry.js`.

Each section is a list of points in space, and every section holds the
same number of points. Point `j` of one section joins point `j` of the
next, two triangles a cell, as `parametric` joins its grid. A lathe
turns one profile around an axis and a tube sweeps one circle along a
path. A loft is the general case: each section can have its own shape,
size, place and turn.

## Closed and open sections

A closed section is a ring, such as the body of an airplane. Its first
point is written again at its end, so the texture coordinates run from
zero to one around the ring without a jump. The two copies at the seam
get the mean of their two normals, as three.js does, so the seam shades
smoothly. An open section is a strip, such as a ribbon.

## Texture coordinates

`u` runs along the loft and `v` around each section. Both follow the
distance between points, so sections of uneven size and points of uneven
spacing map evenly. `u` at a section is the mean distance of its points
from the points of the section before, summed from the first section.

## Caps

A cap closes the first or the last section with a flat face. Its plane
comes from Newell's method, and it faces away from the next section in.
The section is laid flat on that plane and cut into triangles by
`triangulate_shape`. A cap has its own vertices, so it shades flat with a
hard edge against the wall.

The points are bare meters, as a `Vector3` position is.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from geometries.earcut import triangulate_shape
from math.shape_path import is_clockwise
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import isfinite

# JavaScript's `Number.EPSILON`, which keeps a cap's texture from dividing
# by a width of zero.
comptime JS_EPSILON = Float32(2.220446049250313e-16)


def _check_sections(sections: List[List[Vector3]]) raises -> Int:
    """Refuse sections a loft cannot join, and return the point count.

    Raises:
        Error: If there are fewer than two sections, a section has fewer
            than two points, the sections differ in point count, or a
            point is not finite.
    """
    if len(sections) < 2:
        raise Error("A loft needs two sections at least")
    var columns = len(sections[0])
    if columns < 2:
        raise Error("A loft section needs two points at least")
    for row in range(len(sections)):  # pragma: no branch
        if len(sections[row]) != columns:
            raise Error(
                "Every loft section must hold the same number of points"
            )
        for point in sections[row]:  # pragma: no branch
            if not (
                isfinite(point.x) and isfinite(point.y) and isfinite(point.z)
            ):
                raise Error("A loft point must be finite")
    return columns


def _row_u(sections: List[List[Vector3]], columns: Int) -> List[Float32]:
    """Return the distance along the loft at each section: the mean
    distance of each section's points from the section before, summed."""
    var row_u: List[Float32] = [0]
    for row in range(1, len(sections)):  # pragma: no branch
        var distance = Float32(0)
        for column in range(columns):  # pragma: no branch
            distance += sections[row][column].distance_to(
                sections[row - 1][column]
            )
        row_u.append(row_u[row - 1] + distance / Float32(columns))
    return row_u^


def _column_v(section: List[Vector3], per_row: Int) -> List[Float32]:
    """Return the distance around one section at each of its written
    points, the first point again at the end of a closed one."""
    var columns = len(section)
    var column_v: List[Float32] = [0]
    for column in range(1, per_row):  # pragma: no branch
        column_v.append(
            column_v[column - 1]
            + section[column % columns].distance_to(
                section[(column - 1) % columns]
            )
        )
    return column_v^


def _fraction(
    distance: Float32, total: Float32, index: Int, count: Int
) -> Float32:
    """Return how far along a run a point is: by distance, or by count when
    the run has no length, three.js's `i / ( rows - 1 )`."""
    if total > 0:
        return distance / total
    return Float32(index) / Float32(count - 1)


def _cap(
    sections: List[List[Vector3]],
    which: Int,
    mut vertices: List[Float32],
    mut uvs: List[Float32],
    mut indices: List[Int],
) raises:
    """Close one end section with a flat face, three.js's `generateCap`.

    Args:
        sections: Every section.
        which: The first section's index or the last's.
        vertices: The positions so far, added to.
        uvs: The texture coordinates so far, added to.
        indices: The triangles so far, added to.

    Raises:
        Error: If `triangulate_shape` refuses the laid-flat section.
    """
    var rows = len(sections)
    var columns = len(sections[which])
    var points = sections[which].copy()
    # The center, and the normal of the section's plane by Newell's
    # method.
    var centroid = Vector3(0, 0, 0)
    var normal = Vector3(0, 0, 0)
    for column in range(columns):  # pragma: no branch
        var p = points[column]
        var q = points[(column + 1) % columns]
        centroid.add(p)
        normal.x += (p.y - q.y) * (p.z + q.z)
        normal.y += (p.z - q.z) * (p.x + q.x)
        normal.z += (p.x - q.x) * (p.y + q.y)
    centroid = centroid / Float32(columns)
    normal.normalize()
    # Face away from the rest of the surface.
    var neighbor = 1 if which == 0 else rows - 2
    var inward = Vector3(0, 0, 0)
    for column in range(columns):  # pragma: no branch
        inward.add(sections[neighbor][column])
    inward = inward / Float32(columns) - centroid
    if normal.dot(inward) > 0:
        normal.negate()
    # Lay the section flat on the cap's plane.
    var tangent = Vector3(1, 0, 0)
    if abs(normal.x) > 0.9:
        tangent = Vector3(0, 1, 0)
    var bitangent = normal
    bitangent.cross(tangent)
    bitangent.normalize()
    tangent = bitangent
    tangent.cross(normal)
    var contour = List[Vector2]()
    for column in range(columns):  # pragma: no branch
        var offset = points[column] - centroid
        contour.append(Vector2(offset.dot(tangent), offset.dot(bitangent)))
    # `triangulate_shape` wants the outline counterclockwise.
    if is_clockwise(contour):
        contour.reverse()
        points.reverse()
    var flat = List[Float64]()
    var low = Vector2(Float32.MAX, Float32.MAX)
    var high = Vector2(-Float32.MAX, -Float32.MAX)
    for column in range(columns):  # pragma: no branch
        flat.append(Float64(contour[column].x))
        flat.append(Float64(contour[column].y))
        low = Vector2(
            min(low.x, contour[column].x), min(low.y, contour[column].y)
        )
        high = Vector2(
            max(high.x, contour[column].x), max(high.y, contour[column].y)
        )
    var faces = triangulate_shape(flat)
    var width = max(high.x - low.x, JS_EPSILON)
    var height = max(high.y - low.y, JS_EPSILON)
    # The cap's own vertices, so it shades flat with a hard edge.
    var first = len(vertices) // 3
    for column in range(columns):  # pragma: no branch
        vertices.append(points[column].x)
        vertices.append(points[column].y)
        vertices.append(points[column].z)
        uvs.append((contour[column].x - low.x) / width)
        uvs.append((contour[column].y - low.y) / height)
    for corner in range(len(faces)):
        indices.append(first + faces[corner])


def loft(
    sections: List[List[Vector3]],
    closed: Bool = True,
    cap_start: Bool = False,
    cap_end: Bool = False,
) raises -> BufferGeometry:
    """Return a surface skinned through cross sections, three.js's
    `LoftGeometry`.

    Args:
        sections: The cross sections, in order along the loft, each a list
            of points in meters. Every section holds the same number of
            points. The faces point outward when each section runs
            counterclockwise seen from the last section toward the first.
        closed: True, the default, to treat each section as a ring. False
            to treat it as an open strip.
        cap_start: Whether to close the first section with a flat face.
        cap_end: Whether to close the last section with a flat face.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and an
        index. The wall's vertices come first, one row per section, and
        each cap's after them.

    Raises:
        Error: If there are fewer than two sections, a section has fewer
            than two points, the sections differ in point count, or a
            point is not finite.
    """
    var columns = _check_sections(sections)
    var rows = len(sections)
    var per_row = columns + 1 if closed else columns
    var row_u = _row_u(sections, columns)
    var total_u = row_u[rows - 1]
    var vertices = List[Float32]()
    var uvs = List[Float32]()
    for row in range(rows):  # pragma: no branch
        var column_v = _column_v(sections[row], per_row)
        var total_v = column_v[per_row - 1]
        for column in range(per_row):  # pragma: no branch
            var point = sections[row][column % columns]
            vertices.append(point.x)
            vertices.append(point.y)
            vertices.append(point.z)
            uvs.append(_fraction(row_u[row], total_u, row, rows))
            uvs.append(_fraction(column_v[column], total_v, column, per_row))
    var indices = List[Int]()
    for row in range(rows - 1):  # pragma: no branch
        for column in range(per_row - 1):  # pragma: no branch
            var a = row * per_row + column
            var b = row * per_row + column + 1
            var c = (row + 1) * per_row + column + 1
            var d = (row + 1) * per_row + column
            indices.append(a)
            indices.append(b)
            indices.append(d)
            indices.append(b)
            indices.append(c)
            indices.append(d)
    if cap_start:
        _cap(sections, 0, vertices, uvs, indices)
    if cap_end:
        _cap(sections, rows - 1, vertices, uvs, indices)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(vertices^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(indices^)
    geometry.compute_vertex_normals()
    if closed:
        _smooth_seam(geometry, rows, per_row)
    return geometry^


def _smooth_seam(mut geometry: BufferGeometry, rows: Int, per_row: Int) raises:
    """Give both copies of each closed section's first point the mean of
    their two normals, so the seam shades smoothly.

    Raises:
        Error: If the geometry has no normals.
    """
    var normals = geometry.clone_attribute(NORMAL)
    for row in range(rows):  # pragma: no branch
        var a = row * per_row
        var b = row * per_row + per_row - 1
        var mean = Vector3(
            normals.data[a * 3] + normals.data[b * 3],
            normals.data[a * 3 + 1] + normals.data[b * 3 + 1],
            normals.data[a * 3 + 2] + normals.data[b * 3 + 2],
        )
        mean.normalize()
        for vertex in [a, b]:  # pragma: no branch
            normals.data[vertex * 3] = mean.x
            normals.data[vertex * 3 + 1] = mean.y
            normals.data[vertex * 3 + 2] = mean.z
    geometry.set_attribute(String(NORMAL), normals^)
