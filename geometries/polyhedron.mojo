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

The arithmetic is three.js's, in doubles, each product before a sum
rounded on its own, and each number is rounded to `Float32` once, when it
is stored. The icosahedron and the dodecahedron are built on three.js's
golden ratio in doubles.

## Numerical range correction

Finite norm-dependent directions and lengths use scale-safe arithmetic.
Extreme finite results can differ from direct three.js r180 arithmetic.
See `docs/wiki/Norm-consumers.md` for the changed operations, retained
limits, and explicit zero and nonfinite rules.
"""

from core.ordinal import require_index_in_count, require_non_negative
from geometries.surface import (
    record_kind,
    require_positive_radius,
    textured_surface,
)
from math.norm import rounded_dot3, rounded_product
from core.buffer_geometry import (
    BufferGeometry,
    DODECAHEDRON_GEOMETRY,
    ICOSAHEDRON_GEOMETRY,
    OCTAHEDRON_GEOMETRY,
    POLYHEDRON_GEOMETRY,
    TETRAHEDRON_GEOMETRY,
    GeometryType,
)
from core.user_data import json_number_text
from std.math import atan2, pi, sqrt
from units.si import Length

# The golden ratio, (1 + root 5) / 2, which the icosahedron and the
# dodecahedron are built on: three.js's `( 1 + Math.sqrt( 5 ) ) / 2`.
comptime GOLDEN = (1 + sqrt(Float64(5))) / 2

comptime _Point = SIMD[DType.float64, 4]

# Each face becomes `(detail + 1)` squared triangles, and the row loop is
# one longer than that. A detail of `Int.MAX` wraps that count and the
# solid comes back with no vertices. A detail just below it never leaves
# the row loop. This is the finest solid this port builds.
comptime MAX_POLYHEDRON_DETAIL = 256


def _lerp(a: _Point, b: _Point, alpha: Float64) -> _Point:
    """Return three.js's `a.clone().lerp( b, alpha )`, the product rounded
    on its own."""
    var out = a
    for axis in range(3):  # pragma: no branch
        out[axis] = a[axis] + rounded_product(b[axis] - a[axis], alpha)
    return out


def _subdivide_face(
    a: _Point, b: _Point, c: _Point, detail: Int, mut data: List[_Point]
):
    """Cut one triangle into `(detail + 1)` squared and append them.

    three.js's construction: `detail + 1` rows of points from the edge `ab`
    up to the corner `c`, each one point shorter than the last, and then
    the triangles between each pair of rows, pointing up and down by turns.
    The apex row has one point and no length to interpolate along, which is
    the one case taken outright.
    """
    var columns = detail + 1
    var rows = List[List[_Point]]()
    for i in range(columns + 1):  # pragma: no branch
        var fraction = Float64(i) / Float64(columns)
        var along_a = _lerp(a, c, fraction)
        var along_b = _lerp(b, c, fraction)
        var length = columns - i
        var row = List[_Point]()
        for j in range(length + 1):  # pragma: no branch
            if j == 0 and i == columns:
                row.append(along_a)
            else:
                row.append(
                    _lerp(along_a, along_b, Float64(j) / Float64(length))
                )
        rows.append(row^)
    for i in range(columns):  # pragma: no branch
        for j in range(2 * (columns - i) - 1):  # pragma: no branch
            var k = j // 2
            if j % 2 == 0:
                data.append(rows[i][k + 1])
                data.append(rows[i + 1][k])
                data.append(rows[i][k])
            else:
                data.append(rows[i][k + 1])
                data.append(rows[i + 1][k + 1])
                data.append(rows[i + 1][k])


def _normalized(point: _Point) -> _Point:
    """Return three.js's `Vector3.normalize`: the point times one over its
    length, or the point itself when its length is zero."""
    var length = sqrt(
        rounded_dot3(point[0], point[1], point[2], point[0], point[1], point[2])
    )
    return point * (1 / (length if length != 0 else 1))


def _azimuth(point: _Point) -> Float64:
    """Return a point's longitude, three.js's way round: zero at -x."""
    return atan2(point[2], -point[0])


def _inclination(point: _Point) -> Float64:
    """Return a point's latitude, negative toward +y, as three.js has it."""
    return atan2(
        -point[1],
        sqrt(
            rounded_product(point[0], point[0])
            + rounded_product(point[2], point[2])
        ),
    )


def _correct_uv(
    mut uvs: List[Float64], index: Int, point: _Point, face_azimuth: Float64
):
    """Repair one corner's u, three.js's `correctUV`: a corner on the seam
    takes the side its face's middle is on, and a corner at a pole, which
    has no longitude of its own, takes its face's."""
    if face_azimuth < 0 and uvs[index * 2] == 1:
        uvs[index * 2] = uvs[index * 2] - 1
    if point[0] == 0 and point[2] == 0:
        uvs[index * 2] = face_azimuth / 2 / pi + 0.5


def _correct_seam(mut uvs: List[Float64], triangle: Int):
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


def _numbers_json(values: List[Float64]) raises -> String:
    """Return numbers as a JSON array."""
    var out = String("[")
    for at in range(len(values)):  # pragma: no branch
        if at > 0:
            out += ","
        out += json_number_text(values[at])
    return out + "]"


def _integers_json(values: List[Int]) -> String:
    """Return whole numbers as a JSON array."""
    var out = String("[")
    for at in range(len(values)):  # pragma: no branch
        if at > 0:
            out += ","
        out += String(values[at])
    return out + "]"


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
        Error: If the radius is not positive, the detail is negative or
            above 256, the vertices are not whole triples, the indices are
            not whole triangles, either list is empty, or an index names
            no vertex.
    """
    var wide = List[Float64](capacity=len(vertices))
    for value in vertices:
        wide.append(Float64(value))
    return _polyhedron(wide, indices, radius, detail)


def _polyhedron(
    vertices: List[Float64],
    indices: List[Int],
    radius: Length,
    detail: Int,
) raises -> BufferGeometry:
    """Return a polyhedron from vertices in doubles, three.js's
    `PolyhedronGeometry`.

    The arithmetic is three.js's, in doubles, each product before a sum
    rounded on its own. A number is rounded to `Float32` once, when it is
    stored. At a detail above zero each normal is three.js's
    `normalizeNormals` of the stored position.

    Raises:
        Error: As `polyhedron` raises.
    """
    require_positive_radius(radius.value, "polyhedron")
    require_non_negative(detail, "A polyhedron's detail cannot be negative")
    if detail > MAX_POLYHEDRON_DETAIL:
        raise Error("A polyhedron's detail is larger than this port builds")
    if len(vertices) == 0 or len(vertices) % 3 != 0:
        raise Error("A polyhedron's vertices come three floats at a time")
    if len(indices) == 0 or len(indices) % 3 != 0:
        raise Error("A polyhedron's faces come three indices at a time")
    var given = len(vertices) // 3
    for slot in range(len(indices)):  # pragma: no branch
        require_index_in_count(
            indices[slot],
            given,
            "A polyhedron's face names a vertex that is not there",
        )

    var points = List[_Point]()
    for face in range(len(indices) // 3):  # pragma: no branch
        _subdivide_face(
            _vertex(vertices, indices[face * 3]),
            _vertex(vertices, indices[face * 3 + 1]),
            _vertex(vertices, indices[face * 3 + 2]),
            detail,
            points,
        )

    # Every point out onto the sphere, three.js's `applyRadius`.
    var count = len(points)
    var scale = Float64(radius.value)
    for vertex in range(count):  # pragma: no branch
        points[vertex] = _normalized(points[vertex]) * scale

    # Longitude and latitude, three.js's `generateUVs`. Latitude runs the
    # other way from the inclination: one at the top, as the sphere's v
    # does and as three.js writes it.
    var uvs = List[Float64]()
    for vertex in range(count):  # pragma: no branch
        uvs.append(_azimuth(points[vertex]) / 2 / pi + 0.5)
        uvs.append(1 - (_inclination(points[vertex]) / pi + 0.5))

    # The seam repairs, per face, in three.js's order. A face's middle is
    # three.js's `divideScalar( 3 )`, a product with a third.
    for triangle in range(count // 3):  # pragma: no branch
        var middle = (points[triangle * 3] + points[triangle * 3 + 1]) + points[
            triangle * 3 + 2
        ]
        var face_azimuth = _azimuth(middle * (1.0 / 3))
        for corner in range(3):  # pragma: no branch
            var index = triangle * 3 + corner
            _correct_uv(uvs, index, points[index], face_azimuth)
    for triangle in range(count // 3):  # pragma: no branch
        _correct_seam(uvs, triangle)

    var data = List[Float32](capacity=count * 3)
    var normals = List[Float32](capacity=count * 3)
    for vertex in range(count):  # pragma: no branch
        var stored = _Point(
            Float64(Float32(points[vertex][0])),
            Float64(Float32(points[vertex][1])),
            Float64(Float32(points[vertex][2])),
            0,
        )
        var normal = _normalized(stored)
        for axis in range(3):  # pragma: no branch
            data.append(Float32(stored[axis]))
            normals.append(Float32(normal[axis]))
    var texture = List[Float32](capacity=len(uvs))
    for value in uvs:  # pragma: no branch
        texture.append(Float32(value))

    var geometry = BufferGeometry()
    textured_surface(geometry, data^, normals^, texture^)
    if detail == 0:
        geometry.compute_vertex_normals()
    record_kind(geometry, POLYHEDRON_GEOMETRY)
    geometry.parameters.set_json("vertices", _numbers_json(vertices))
    geometry.parameters.set_json("indices", _integers_json(indices))
    geometry.parameters.set_meters("radius", radius)
    geometry.parameters.set_number("detail", Float64(detail))
    return geometry^


def _vertex(vertices: List[Float64], index: Int) -> _Point:
    """Return one vertex of a flat list of triples."""
    return _Point(
        vertices[index * 3], vertices[index * 3 + 1], vertices[index * 3 + 2], 0
    )


def _regular_solid(
    vertices: List[Float64],
    indices: List[Int],
    radius: Length,
    detail: Int,
    kind: GeometryType,
) raises -> BufferGeometry:
    """Return a regular solid with its radius and detail recorded.

    The four named solids share this finish. The kind is the three.js
    class, and the parameters are the radius and the detail.
    """
    var geometry = _polyhedron(vertices, indices, radius, detail)
    record_kind(geometry, kind)
    geometry.parameters.set_meters("radius", radius)
    geometry.parameters.set_number("detail", Float64(detail))
    return geometry^


def tetrahedron(radius: Length, detail: Int = 0) raises -> BufferGeometry:
    """Return a tetrahedron, three.js's `TetrahedronGeometry`.

    Args:
        radius: How far every vertex lies from the origin.
        detail: How finely to cut it toward a sphere; see `polyhedron`.

    Returns:
        The geometry, four faces at a detail of zero.

    Raises:
        Error: If the radius is not positive, or the detail is negative
            or above 256.
    """
    var vertices: List[Float64] = [1, 1, 1, -1, -1, 1, -1, 1, -1, 1, -1, -1]
    var indices: List[Int] = [2, 1, 0, 0, 3, 2, 1, 3, 0, 2, 3, 1]
    return _regular_solid(
        vertices, indices, radius, detail, TETRAHEDRON_GEOMETRY
    )


def octahedron(radius: Length, detail: Int = 0) raises -> BufferGeometry:
    """Return an octahedron, three.js's `OctahedronGeometry`.

    Args:
        radius: How far every vertex lies from the origin.
        detail: How finely to cut it toward a sphere; see `polyhedron`.

    Returns:
        The geometry, eight faces at a detail of zero.

    Raises:
        Error: If the radius is not positive, or the detail is negative
            or above 256.
    """
    var vertices: List[Float64] = [
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
    return _regular_solid(
        vertices, indices, radius, detail, OCTAHEDRON_GEOMETRY
    )


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
        Error: If the radius is not positive, or the detail is negative
            or above 256.
    """
    var t = GOLDEN
    var vertices: List[Float64] = [
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
    return _regular_solid(
        vertices, indices, radius, detail, ICOSAHEDRON_GEOMETRY
    )


def dodecahedron(radius: Length, detail: Int = 0) raises -> BufferGeometry:
    """Return a dodecahedron, three.js's `DodecahedronGeometry`.

    Args:
        radius: How far every vertex lies from the origin.
        detail: How finely to cut it toward a sphere; see `polyhedron`.

    Returns:
        The geometry, twelve pentagons of three triangles each at a detail
        of zero.

    Raises:
        Error: If the radius is not positive, or the detail is negative
            or above 256.
    """
    var t = GOLDEN
    var r = 1 / t
    var vertices: List[Float64] = [
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
    return _regular_solid(
        vertices, indices, radius, detail, DODECAHEDRON_GEOMETRY
    )
