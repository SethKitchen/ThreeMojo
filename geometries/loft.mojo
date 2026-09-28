# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A surface skinned through a row of cross sections, from three.js
`examples/jsm/geometries/LoftGeometry.js`.

A loft is the general case of a lathe or a tube: each section is a list of
points in space, all sections have the same number of points, and the
surface joins point `j` of one section to point `j` of the next. The
sections can change shape, size, position and turn from one to the next.

A closed section is a ring. Its first point is written again at its end,
so the texture wraps round without a jump, and the two copies of the
seam's normal are averaged so the surface shades smoothly across it. An
open section is a strip, a ribbon.

The texture coordinates follow arc length: `u` along the loft by the mean
distance between neighboring sections, `v` round each section by the
distance along it.

A cap closes the first or the last section with a flat, earcut polygon of
its own vertices, so its edge is hard. The cap faces away from the rest of
the surface.

A section wound counter-clockwise, seen from the end of the loft looking
back to its start, gives normals that point out.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from geometries.earcut import triangulate_shape
from math.vector3 import Vector3
from std.math import sqrt

# The smallest width a cap's texture box is given, JavaScript's
# `Number.EPSILON`.
comptime _EPSILON = 2.220446049250313e-16


@fieldwise_init
struct _P(ImplicitlyCopyable):
    """A point in `Float64`."""

    var x: Float64
    var y: Float64
    var z: Float64


def _p(v: Vector3) -> _P:
    """Return a point in `Float64`."""
    return _P(Float64(v.x), Float64(v.y), Float64(v.z))


def _distance(a: Vector3, b: Vector3) -> Float64:
    """Return the distance between two points, in `Float64`."""
    var dx = Float64(a.x) - Float64(b.x)
    var dy = Float64(a.y) - Float64(b.y)
    var dz = Float64(a.z) - Float64(b.z)
    return sqrt(dx * dx + dy * dy + dz * dz)


def _unit(v: _P) -> _P:
    """Return a vector made unit length, or zero, as three.js's
    `normalize`."""
    var length = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    var inverse = 1.0 / (length if length != 0 else 1.0)
    return _P(v.x * inverse, v.y * inverse, v.z * inverse)


def _cross(a: _P, b: _P) -> _P:
    """Return a cross product."""
    return _P(
        a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x
    )


def _dot(a: _P, b: _P) -> Float64:
    """Return a dot product."""
    return a.x * b.x + a.y * b.y + a.z * b.z


def _mean(section: List[Vector3]) -> _P:
    """Return the mean of a section's points."""
    var x = 0.0
    var y = 0.0
    var z = 0.0
    for i in range(len(section)):  # pragma: no branch
        x += Float64(section[i].x)
        y += Float64(section[i].y)
        z += Float64(section[i].z)
    var n = Float64(len(section))
    return _P(x / n, y / n, z / n)


struct _Buffers:
    """The loft's vertices, texture coordinates and index, as they grow."""

    var vertices: List[Float32]
    var uvs: List[Float32]
    var index: List[Int]

    def __init__(out self):
        self.vertices = List[Float32]()
        self.uvs = List[Float32]()
        self.index = List[Int]()


def _cap(
    mut out: _Buffers,
    sections: List[List[Vector3]],
    at: Int,
) raises:
    """Close one end with a flat polygon, three.js's `generateCap`."""
    ref section = sections[at]
    var columns = len(section)
    var rows = len(sections)
    var centroid = _mean(section)
    var nx = 0.0
    var ny = 0.0
    var nz = 0.0
    for i in range(columns):  # pragma: no branch
        var p = _p(section[i])
        var q = _p(section[(i + 1) % columns])
        nx += (p.y - q.y) * (p.z + q.z)
        ny += (p.z - q.z) * (p.x + q.x)
        nz += (p.x - q.x) * (p.y + q.y)
    var normal = _unit(_P(nx, ny, nz))
    var neighbor = _mean(sections[1 if at == 0 else rows - 2])
    var toward = _P(
        neighbor.x - centroid.x,
        neighbor.y - centroid.y,
        neighbor.z - centroid.z,
    )
    var sign = -1.0 if _dot(normal, toward) > 0 else 1.0
    normal = _P(normal.x * sign, normal.y * sign, normal.z * sign)
    var tangent = _P(0, 1, 0) if abs(normal.x) > 0.9 else _P(1, 0, 0)
    var bitangent = _unit(_cross(normal, tangent))
    tangent = _cross(bitangent, normal)
    var contour = List[Float64]()
    var area = 0.0
    for i in range(columns):  # pragma: no branch
        var p = _p(section[i])
        var d = _P(p.x - centroid.x, p.y - centroid.y, p.z - centroid.z)
        contour.append(_dot(d, tangent))
        contour.append(_dot(d, bitangent))
    for q in range(columns):  # pragma: no branch
        var p = (q + columns - 1) % columns
        area += (
            contour[p * 2] * contour[q * 2 + 1]
            - contour[q * 2] * contour[p * 2 + 1]
        )
    # three.js reverses a clockwise contour, and the points with it, for
    # earcut. Reading both backward is the same.
    var clockwise = area * 0.5 < 0
    var order = List[Int]()
    for i in range(columns):  # pragma: no branch
        order.append(columns - 1 - i if clockwise else i)
    var flat = List[Float64]()
    var low_x = contour[0]
    var low_y = contour[1]
    var high_x = contour[0]
    var high_y = contour[1]
    for k in range(columns):  # pragma: no branch
        var i = order[k]
        flat.append(contour[i * 2])
        flat.append(contour[i * 2 + 1])
        low_x = min(low_x, contour[i * 2])
        low_y = min(low_y, contour[i * 2 + 1])
        high_x = max(high_x, contour[i * 2])
        high_y = max(high_y, contour[i * 2 + 1])
    var faces = triangulate_shape(flat)
    var width = max(high_x - low_x, _EPSILON)
    var height = max(high_y - low_y, _EPSILON)
    var offset = len(out.vertices) // 3
    for k in range(columns):  # pragma: no branch
        var i = order[k]
        out.vertices.append(section[i].x)
        out.vertices.append(section[i].y)
        out.vertices.append(section[i].z)
        out.uvs.append(Float32((contour[i * 2] - low_x) / width))
        out.uvs.append(Float32((contour[i * 2 + 1] - low_y) / height))
    for f in range(len(faces)):
        out.index.append(offset + faces[f])


def loft(
    sections: List[List[Vector3]],
    closed: Bool = True,
    cap_start: Bool = False,
    cap_end: Bool = False,
) raises -> BufferGeometry:
    """Return a surface skinned through cross sections, three.js's
    `LoftGeometry`.

    Args:
        sections: The cross sections, in meters, two at least, all with
            the same number of points.
        closed: Whether each section is a closed ring or an open strip.
        cap_start: Whether the first section is closed with a flat cap.
        cap_end: Whether the last section is closed with a flat cap.

    Returns:
        An indexed geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If there are fewer than two sections, the sections differ
            in their number of points, or a section has fewer than two
            points, or fewer than three with a cap. three.js logs the
            first two and builds nothing.
    """
    var rows = len(sections)
    if rows < 2:
        raise Error("A loft needs two sections at least")
    var columns = len(sections[0])
    for i in range(1, rows):  # pragma: no branch
        if len(sections[i]) != columns:
            raise Error("A loft's sections must all have the same points")
    if columns < 2:
        raise Error("A loft's section needs two points at least")
    if (cap_start or cap_end) and columns < 3:
        raise Error("A capped loft's section needs three points at least")
    var per_row = columns + 1 if closed else columns
    var row_u: List[Float64] = [0.0]
    for i in range(1, rows):  # pragma: no branch
        var distance = 0.0
        for j in range(columns):  # pragma: no branch
            distance += _distance(sections[i][j], sections[i - 1][j])
        row_u.append(row_u[i - 1] + distance / Float64(columns))
    var total_u = row_u[rows - 1]
    var out = _Buffers()
    for i in range(rows):  # pragma: no branch
        ref section = sections[i]
        var col_v: List[Float64] = [0.0]
        for j in range(1, per_row):  # pragma: no branch
            col_v.append(
                col_v[j - 1]
                + _distance(section[j % columns], section[(j - 1) % columns])
            )
        var total_v = col_v[per_row - 1]
        for j in range(per_row):  # pragma: no branch
            var point = section[j % columns]
            out.vertices.append(point.x)
            out.vertices.append(point.y)
            out.vertices.append(point.z)
            out.uvs.append(
                Float32(
                    row_u[i] / total_u if total_u
                    > 0 else Float64(i) / Float64(rows - 1)
                )
            )
            out.uvs.append(
                Float32(
                    col_v[j] / total_v if total_v
                    > 0 else Float64(j) / Float64(per_row - 1)
                )
            )
    for i in range(rows - 1):  # pragma: no branch
        for j in range(per_row - 1):  # pragma: no branch
            var a = i * per_row + j
            var b = a + 1
            var c = (i + 1) * per_row + j + 1
            var d = (i + 1) * per_row + j
            out.index.append(a)
            out.index.append(b)
            out.index.append(d)
            out.index.append(b)
            out.index.append(c)
            out.index.append(d)
    if cap_start:
        _cap(out, sections, 0)
    if cap_end:
        _cap(out, sections, rows - 1)
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION), BufferAttribute(out.vertices.copy(), 3)
    )
    geometry.set_attribute(String(UV), BufferAttribute(out.uvs.copy(), 2))
    geometry.set_index(out.index.copy())
    geometry.compute_vertex_normals()
    if closed:
        _smooth_seams(geometry, rows, per_row)
    return geometry^


def _smooth_seams(mut geometry: BufferGeometry, rows: Int, per_row: Int) raises:
    """Average the normals of each ring's two seam copies, so a closed loft
    shades smoothly across its seam."""
    var normals = geometry.clone_attribute(String(NORMAL))
    for i in range(rows):  # pragma: no branch
        var a = i * per_row
        var b = a + per_row - 1
        var na = normals.vector3(a)
        var nb = normals.vector3(b)
        var sum = _unit(
            _P(
                Float64(na.x) + Float64(nb.x),
                Float64(na.y) + Float64(nb.y),
                Float64(na.z) + Float64(nb.z),
            )
        )
        for vertex in [a, b]:  # pragma: no branch
            normals.set_component(vertex, 0, Float32(sum.x))
            normals.set_component(vertex, 1, Float32(sum.y))
            normals.set_component(vertex, 2, Float32(sum.z))
    geometry.set_attribute(String(NORMAL), normals^)
