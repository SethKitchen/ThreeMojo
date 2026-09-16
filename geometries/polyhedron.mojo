# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Polyhedra, from three.js `src/geometries/PolyhedronGeometry.js` and the
four solids that specialize it.

A polyhedron here is a list of vertices and a list of triangles over them,
each triangle cut into `(detail + 1)` squared smaller ones and every vertex
pushed out onto a sphere. At a detail of zero it is the solid itself, flat
faced, with a normal per face; at one or more it is a sphere approximated
ever more finely, with a normal per vertex pointing away from the center.
The four regular solids three.js ships are here with the same vertices and
the same faces in the same order, so a texture lands as it does there.

Every face's vertices are its own -- the geometry is not indexed -- because
a flat face needs its corners' normals to be its normal and not its
neighbors', and a subdivided face's corners are shared only along its
edges, where the sphere's normals agree anyway.

Texture coordinates are longitude and latitude, as on a globe, with the
seam repaired per face as three.js repairs it: a corner on the seam takes
the side its face's middle is on, a corner at a pole takes its face's
longitude, and a face that straddles the seam has its low corners moved a
turn on. That last repair is why a coordinate can exceed one; the wrap mode
reads it as the same place.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from math.vector3 import Vector3
from std.math import atan2, pi, sqrt
from units.si import Length

# The golden ratio, (1 + root 5) / 2, which the icosahedron and the
# dodecahedron are built on.
comptime GOLDEN = Float32(1.618034)


def _lerp(a: Vector3, b: Vector3, t: Float32) -> Vector3:
    """Return the point a fraction `t` of the way from `a` to `b`."""
    return a + (b - a) * t


def _push(mut data: List[Float32], point: Vector3):
    """Append a point's three components."""
    data.append(point.x)
    data.append(point.y)
    data.append(point.z)


def _subdivide_face(
    a: Vector3, b: Vector3, c: Vector3, detail: Int, mut data: List[Float32]
):
    """Cut one triangle into `(detail + 1)` squared and append them.

    three.js's construction: `detail + 1` rows of points from the edge `ab`
    up to the corner `c`, each one point shorter than the last, and then
    the triangles between each pair of rows, pointing up and down by turns.
    The apex row has one point and no length to interpolate along, which is
    the one case taken outright.
    """
    var columns = detail + 1
    var rows = List[List[Vector3]]()
    for i in range(columns + 1):  # pragma: no branch
        var fraction = Float32(i) / Float32(columns)
        var along_a = _lerp(a, c, fraction)
        var along_b = _lerp(b, c, fraction)
        var length = columns - i
        var row = List[Vector3]()
        for j in range(length + 1):  # pragma: no branch
            if j == 0 and i == columns:
                row.append(along_a)
            else:
                row.append(
                    _lerp(along_a, along_b, Float32(j) / Float32(length))
                )
        rows.append(row^)
    for i in range(columns):  # pragma: no branch
        for j in range(2 * (columns - i) - 1):  # pragma: no branch
            var k = j // 2
            if j % 2 == 0:
                _push(data, rows[i][k + 1])
                _push(data, rows[i + 1][k])
                _push(data, rows[i][k])
            else:
                _push(data, rows[i][k + 1])
                _push(data, rows[i + 1][k + 1])
                _push(data, rows[i + 1][k])


def _azimuth(point: Vector3) -> Float32:
    """Return a point's longitude, three.js's way round: zero at -x."""
    return atan2(point.z, -point.x)


def _inclination(point: Vector3) -> Float32:
    """Return a point's latitude, negative toward +y, as three.js has it."""
    return atan2(-point.y, sqrt(point.x * point.x + point.z * point.z))


def _correct_uv(
    mut uvs: List[Float32], index: Int, point: Vector3, face_azimuth: Float32
):
    """Repair one corner's u, three.js's `correctUV`: a corner on the seam
    takes the side its face's middle is on, and a corner at a pole, which
    has no longitude of its own, takes its face's."""
    if face_azimuth < 0 and uvs[index * 2] == 1:
        uvs[index * 2] = uvs[index * 2] - 1
    if point.x == 0 and point.z == 0:
        uvs[index * 2] = face_azimuth / (2 * Float32(pi)) + 0.5


def _correct_seam(mut uvs: List[Float32], triangle: Int):
    """Move a face that straddles the seam a turn on, three.js's
    `correctSeam`: if its u runs from near one to near zero, the low
    corners are moved past one so the face does not wrap the whole image."""
    var first = triangle * 6
    var highest = max(uvs[first], max(uvs[first + 2], uvs[first + 4]))
    var lowest = min(uvs[first], min(uvs[first + 2], uvs[first + 4]))
    if highest > 0.9 and lowest < 0.1:
        for corner in range(3):  # pragma: no branch
            if uvs[first + corner * 2] < 0.2:
                uvs[first + corner * 2] += 1


def polyhedron(
    vertices: List[Float32],
    indices: List[Int],
    radius: Length,
    detail: Int = 0,
) raises -> BufferGeometry:
    """Return a polyhedron, subdivided and pushed out onto a sphere.

    three.js's `PolyhedronGeometry`. The four regular solids below are this
    with their vertices and faces filled in.

    Args:
        vertices: Three floats per vertex, at any scale: each is pushed out
            to `radius` from the origin.
        indices: Three vertex indices per triangle, wound counter-clockwise
            seen from outside.
        radius: How far every vertex ends up from the origin.
        detail: How many times to cut each edge: zero leaves the faces
            flat, and a detail of `d` cuts every face into `(d + 1)`
            squared triangles, on the way to a sphere.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and no
        index: three vertices per triangle, `(detail + 1)` squared
        triangles per face. Flat normals at a detail of zero, normals along
        the radius otherwise.

    Raises:
        Error: If the radius is not positive, the detail is negative, the
            vertices are not whole triples, the indices are not whole
            triangles, either list is empty, or an index names no vertex.
    """
    if radius.value <= 0:
        raise Error("A polyhedron needs a positive radius")
    if detail < 0:
        raise Error("A polyhedron's detail cannot be negative")
    if len(vertices) == 0 or len(vertices) % 3 != 0:
        raise Error("A polyhedron's vertices come three floats at a time")
    if len(indices) == 0 or len(indices) % 3 != 0:
        raise Error("A polyhedron's faces come three indices at a time")
    var given = len(vertices) // 3
    for slot in range(len(indices)):  # pragma: no branch
        if indices[slot] < 0 or indices[slot] >= given:
            raise Error("A polyhedron's face names a vertex that is not there")

    var data = List[Float32]()
    for face in range(len(indices) // 3):  # pragma: no branch
        _subdivide_face(
            _vertex(vertices, indices[face * 3]),
            _vertex(vertices, indices[face * 3 + 1]),
            _vertex(vertices, indices[face * 3 + 2]),
            detail,
            data,
        )

    # Every point out onto the sphere. Its direction is its normal, which
    # is right for a subdivided face and replaced below for a flat one.
    var count = len(data) // 3
    var normals = List[Float32]()
    var uvs = List[Float32]()
    var points = List[Vector3]()
    for vertex in range(count):  # pragma: no branch
        var direction = Vector3(
            data[vertex * 3], data[vertex * 3 + 1], data[vertex * 3 + 2]
        )
        direction.normalize()
        points.append(direction)
        _push(normals, direction)
        data[vertex * 3] = direction.x * radius.value
        data[vertex * 3 + 1] = direction.y * radius.value
        data[vertex * 3 + 2] = direction.z * radius.value
        uvs.append(_azimuth(direction) / (2 * Float32(pi)) + 0.5)
        # Latitude runs the other way from the inclination: one at the top,
        # as the sphere's v does and as three.js writes it.
        uvs.append(0.5 - _inclination(direction) / Float32(pi))

    # The seam repairs, per face, in three.js's order.
    for triangle in range(count // 3):  # pragma: no branch
        var middle = (
            points[triangle * 3]
            + points[triangle * 3 + 1]
            + points[triangle * 3 + 2]
        ) * (Float32(1) / 3)
        var face_azimuth = _azimuth(middle)
        for corner in range(3):  # pragma: no branch
            var index = triangle * 3 + corner
            _correct_uv(uvs, index, points[index], face_azimuth)
    for triangle in range(count // 3):  # pragma: no branch
        _correct_seam(uvs, triangle)

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    if detail == 0:
        geometry.compute_vertex_normals()
    return geometry^


def _vertex(vertices: List[Float32], index: Int) -> Vector3:
    """Return one vertex of a flat list of triples."""
    return Vector3(
        vertices[index * 3], vertices[index * 3 + 1], vertices[index * 3 + 2]
    )


def tetrahedron(radius: Length, detail: Int = 0) raises -> BufferGeometry:
    """Return a tetrahedron, three.js's `TetrahedronGeometry`.

    Args:
        radius: How far every vertex lies from the origin.
        detail: How finely to cut it toward a sphere; see `polyhedron`.

    Returns:
        The geometry, four faces at a detail of zero.

    Raises:
        Error: If the radius is not positive or the detail is negative.
    """
    var vertices: List[Float32] = [1, 1, 1, -1, -1, 1, -1, 1, -1, 1, -1, -1]
    var indices: List[Int] = [2, 1, 0, 0, 3, 2, 1, 3, 0, 2, 3, 1]
    return polyhedron(vertices, indices, radius, detail)


def octahedron(radius: Length, detail: Int = 0) raises -> BufferGeometry:
    """Return an octahedron, three.js's `OctahedronGeometry`.

    Args:
        radius: How far every vertex lies from the origin.
        detail: How finely to cut it toward a sphere; see `polyhedron`.

    Returns:
        The geometry, eight faces at a detail of zero.

    Raises:
        Error: If the radius is not positive or the detail is negative.
    """
    var vertices: List[Float32] = [
        1,
        0,
        0,
        -1,
        0,
        0,
        0,
        1,
        0,
        0,
        -1,
        0,
        0,
        0,
        1,
        0,
        0,
        -1,
    ]
    var indices: List[Int] = [
        0,
        2,
        4,
        0,
        4,
        3,
        0,
        3,
        5,
        0,
        5,
        2,
        1,
        2,
        5,
        1,
        5,
        3,
        1,
        3,
        4,
        1,
        4,
        2,
    ]
    return polyhedron(vertices, indices, radius, detail)


def icosahedron(radius: Length, detail: Int = 0) raises -> BufferGeometry:
    """Return an icosahedron, three.js's `IcosahedronGeometry`.

    Args:
        radius: How far every vertex lies from the origin.
        detail: How finely to cut it toward a sphere; see `polyhedron`.
            An icosahedron is the usual start for a sphere of even
            triangles.

    Returns:
        The geometry, twenty faces at a detail of zero.

    Raises:
        Error: If the radius is not positive or the detail is negative.
    """
    var t = GOLDEN
    var vertices: List[Float32] = [
        -1,
        t,
        0,
        1,
        t,
        0,
        -1,
        -t,
        0,
        1,
        -t,
        0,
        0,
        -1,
        t,
        0,
        1,
        t,
        0,
        -1,
        -t,
        0,
        1,
        -t,
        t,
        0,
        -1,
        t,
        0,
        1,
        -t,
        0,
        -1,
        -t,
        0,
        1,
    ]
    var indices: List[Int] = [
        0,
        11,
        5,
        0,
        5,
        1,
        0,
        1,
        7,
        0,
        7,
        10,
        0,
        10,
        11,
        1,
        5,
        9,
        5,
        11,
        4,
        11,
        10,
        2,
        10,
        7,
        6,
        7,
        1,
        8,
        3,
        9,
        4,
        3,
        4,
        2,
        3,
        2,
        6,
        3,
        6,
        8,
        3,
        8,
        9,
        4,
        9,
        5,
        2,
        4,
        11,
        6,
        2,
        10,
        8,
        6,
        7,
        9,
        8,
        1,
    ]
    return polyhedron(vertices, indices, radius, detail)


def dodecahedron(radius: Length, detail: Int = 0) raises -> BufferGeometry:
    """Return a dodecahedron, three.js's `DodecahedronGeometry`.

    Args:
        radius: How far every vertex lies from the origin.
        detail: How finely to cut it toward a sphere; see `polyhedron`.

    Returns:
        The geometry, twelve pentagons of three triangles each at a detail
        of zero.

    Raises:
        Error: If the radius is not positive or the detail is negative.
    """
    var t = GOLDEN
    var r = 1 / t
    var vertices: List[Float32] = [
        -1,
        -1,
        -1,
        -1,
        -1,
        1,
        -1,
        1,
        -1,
        -1,
        1,
        1,
        1,
        -1,
        -1,
        1,
        -1,
        1,
        1,
        1,
        -1,
        1,
        1,
        1,
        0,
        -r,
        -t,
        0,
        -r,
        t,
        0,
        r,
        -t,
        0,
        r,
        t,
        -r,
        -t,
        0,
        -r,
        t,
        0,
        r,
        -t,
        0,
        r,
        t,
        0,
        -t,
        0,
        -r,
        t,
        0,
        -r,
        -t,
        0,
        r,
        t,
        0,
        r,
    ]
    var indices: List[Int] = [
        3,
        11,
        7,
        3,
        7,
        15,
        3,
        15,
        13,
        7,
        19,
        17,
        7,
        17,
        6,
        7,
        6,
        15,
        17,
        4,
        8,
        17,
        8,
        10,
        17,
        10,
        6,
        8,
        0,
        16,
        8,
        16,
        2,
        8,
        2,
        10,
        0,
        12,
        1,
        0,
        1,
        18,
        0,
        18,
        16,
        6,
        10,
        2,
        6,
        2,
        13,
        6,
        13,
        15,
        2,
        16,
        18,
        2,
        18,
        3,
        2,
        3,
        13,
        18,
        1,
        9,
        18,
        9,
        11,
        18,
        11,
        3,
        4,
        14,
        12,
        4,
        12,
        0,
        4,
        0,
        8,
        11,
        9,
        5,
        11,
        5,
        19,
        11,
        19,
        7,
        19,
        5,
        14,
        19,
        14,
        4,
        19,
        4,
        17,
        1,
        12,
        14,
        1,
        14,
        5,
        1,
        5,
        9,
    ]
    return polyhedron(vertices, indices, radius, detail)
