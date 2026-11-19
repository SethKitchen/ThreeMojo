# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Weld, smooth and measure a triangle mesh, such as a label surface.

`label_surface` gives a mesh with steps of one voxel. `weld_surface`
joins the corners that have the same position, so that each vertex is
stored once and the triangles share it. `smooth_surface` then applies
Taubin's lambda-mu filter. Each pass is a step that shrinks and a step
that inflates. Each step moves each vertex toward the mean of its
neighbors by the factor of the step:

    p' = p + f * (mean(neighbors) - p)

The shrink factor `f = lambda` is positive and the inflate factor
`f = mu` is below `-lambda`. The pair removes the steps of the voxels,
which have a high spatial frequency, and keeps the shape and nearly all
of the volume. A plain Laplacian filter shrinks the mesh at each step.

`surface_area` and `enclosed_volume` measure a mesh. The volume comes
from the divergence theorem: it is exact for a closed mesh whose faces
turn outward.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION, UV
from geometries.surface import indexed_surface
from math.vector3 import Vector3
from std.math import max, sqrt
from std.memory import bitcast
from units.si import Area64, CUBIC_METER, SQUARE_METER, Volume64

# Taubin's factors for a pass band of about 0.1.
comptime TAUBIN_SHRINK = 0.5
comptime TAUBIN_INFLATE = -0.53


struct _Welded(Movable):
    """A mesh with each position stored once."""

    var points: List[Float64]
    """Three coordinates per vertex, in meters."""
    var uvs: List[Float32]
    """Two texture coordinates per vertex."""
    var faces: List[Int]
    """Three vertices per triangle."""

    def __init__(out self):
        self.points = List[Float64]()
        self.uvs = List[Float32]()
        self.faces = List[Int]()


def _bits(value: Float32) -> Int:
    """Return the bit pattern of a float, with -0 as +0."""
    # -0 + 0 is +0, so the two zeros share one pattern.
    return Int(bitcast[DType.uint32](value + 0))


def _key(p: Vector3) -> String:
    """Return a key that two corners share only at the same position."""
    return String(_bits(p.x), " ", _bits(p.y), " ", _bits(p.z))


def _weld(geometry: BufferGeometry) raises -> _Welded:
    """Join the corners of a geometry that have the same position."""
    ref points = geometry.attribute_view(POSITION)
    var has_uv = geometry.has_attribute(UV)
    var out = _Welded()
    var first = Dict[String, Int]()
    for triangle in range(geometry.triangle_count()):
        var corners = List[Int]()
        var keys = List[String]()
        for corner in range(3):  # pragma: no branch
            var vertex = geometry.corner_index(triangle, corner)
            corners.append(vertex)
            keys.append(_key(points.vector3(vertex)))
        # A triangle with two corners at one place has no area.
        if keys[0] == keys[1] or keys[1] == keys[2] or keys[0] == keys[2]:
            continue
        for corner in range(3):  # pragma: no branch
            var found = first.get(keys[corner])
            if found:
                out.faces.append(found.value())
                continue
            var kept = len(out.points) // 3
            first[keys[corner]] = kept
            out.faces.append(kept)
            var p = points.vector3(corners[corner])
            out.points.append(Float64(p.x))
            out.points.append(Float64(p.y))
            out.points.append(Float64(p.z))
            if has_uv:
                ref uv = geometry.attribute_view(UV)
                out.uvs.append(uv.component(corners[corner], 0))
                out.uvs.append(uv.component(corners[corner], 1))
            else:
                out.uvs.append(0)
                out.uvs.append(0)
    if len(out.faces) == 0:
        raise Error("A surface needs at least one triangle with area")
    return out^


def _link(mut around: List[Int], vertex: Int):
    """Add a neighbor once."""
    for known in around:
        if known == vertex:
            return
    around.append(vertex)


def _neighbors(count: Int, faces: List[Int]) -> List[List[Int]]:
    """Return the vertices that share an edge with each vertex."""
    var out = List[List[Int]](length=count, fill=List[Int]())
    for face in range(len(faces) // 3):  # pragma: no branch
        for corner in range(3):  # pragma: no branch
            var a = faces[3 * face + corner]
            var b = faces[3 * face + (corner + 1) % 3]
            _link(out[a], b)
            _link(out[b], a)
    return out^


def _step(
    mut points: List[Float64], neighbors: List[List[Int]], factor: Float64
):
    """Move each vertex toward the mean of its neighbors by `factor`."""
    var moved = points.copy()
    for vertex in range(len(neighbors)):  # pragma: no branch
        ref around = neighbors[vertex]
        var sum_x = 0.0
        var sum_y = 0.0
        var sum_z = 0.0
        # Each vertex is a corner of a triangle with area.
        for other in around:  # pragma: no branch
            sum_x += points[3 * other]
            sum_y += points[3 * other + 1]
            sum_z += points[3 * other + 2]
        var share = 1.0 / Float64(len(around))
        for axis in range(3):  # pragma: no branch
            var mean = [sum_x, sum_y, sum_z][axis] * share
            var here = points[3 * vertex + axis]
            moved[3 * vertex + axis] = here + factor * (mean - here)
    points = moved^


def _geometry(var welded: _Welded) raises -> BufferGeometry:
    """Return a geometry with area-weighted vertex normals."""
    var count = len(welded.points) // 3
    var normals = List[Float64](length=3 * count, fill=0)
    for face in range(len(welded.faces) // 3):  # pragma: no branch
        var a = welded.faces[3 * face]
        var b = welded.faces[3 * face + 1]
        var c = welded.faces[3 * face + 2]
        var e = _edge(welded.points, a, b)
        var f = _edge(welded.points, a, c)
        # The cross product is twice the area along the normal.
        var n = [
            e[1] * f[2] - e[2] * f[1],
            e[2] * f[0] - e[0] * f[2],
            e[0] * f[1] - e[1] * f[0],
        ]
        for vertex in [a, b, c]:  # pragma: no branch
            for axis in range(3):  # pragma: no branch
                normals[3 * vertex + axis] += n[axis]
    var positions = List[Float32](capacity=3 * count)
    var unit = List[Float32](capacity=3 * count)
    for vertex in range(count):  # pragma: no branch
        var nx = normals[3 * vertex]
        var ny = normals[3 * vertex + 1]
        var nz = normals[3 * vertex + 2]
        var size = max(sqrt(nx * nx + ny * ny + nz * nz), 1.0e-300)
        for axis in range(3):  # pragma: no branch
            positions.append(Float32(welded.points[3 * vertex + axis]))
            unit.append(Float32(normals[3 * vertex + axis] / size))
    var geometry = BufferGeometry()
    indexed_surface(
        geometry, positions^, unit^, welded.uvs.copy(), welded.faces.copy()
    )
    return geometry^


def _edge(points: List[Float64], a: Int, b: Int) -> List[Float64]:
    """Return the vector from vertex `a` to vertex `b`."""
    return [
        points[3 * b] - points[3 * a],
        points[3 * b + 1] - points[3 * a + 1],
        points[3 * b + 2] - points[3 * a + 2],
    ]


def weld_surface(geometry: BufferGeometry) raises -> BufferGeometry:
    """Return a mesh with each position stored once.

    Corners at the same position, to the bit, become one vertex. The two
    zeros, -0 and +0, are one position. A
    triangle with two corners at one position has no area and is
    dropped. Each vertex keeps the texture coordinates of its first
    corner, or zero when the geometry has none. The normals are the
    area-weighted mean of the faces around each vertex.

    Args:
        geometry: A triangle mesh with positions, indexed or not.

    Returns:
        An indexed geometry with `position`, `normal` and `uv`.

    Raises:
        Error: If the geometry has no positions, or no triangle with area.
    """
    return _geometry(_weld(geometry))


def smooth_surface(
    geometry: BufferGeometry,
    passes: Int,
    shrink: Float64 = TAUBIN_SHRINK,
    inflate: Float64 = TAUBIN_INFLATE,
) raises -> BufferGeometry:
    """Return a welded mesh smoothed by Taubin's lambda-mu filter.

    Args:
        geometry: A triangle mesh with positions, indexed or not.
        passes: The number of passes. Each pass is a step by `shrink` and
            a step by `inflate`. Zero passes only weld the mesh.
        shrink: The factor of the first step, lambda. Above 0 and at most 1.
        inflate: The factor of the second step, mu. From -1 to less than
            `-shrink`.

    Returns:
        An indexed geometry with `position`, `normal` and `uv`, with the
        topology of `weld_surface(geometry)`.

    Raises:
        Error: If `passes` is negative, a factor is out of its range, the
            geometry has no positions, or it has no triangle with area.
    """
    if passes < 0:
        raise Error("The passes of a smoothing cannot be negative")
    if not (shrink > 0 and shrink <= 1):
        raise Error("The shrink factor must be above 0 and at most 1")
    if not (inflate >= -1 and inflate < -shrink):
        raise Error(
            "The inflate factor must be from -1 to less than the negative"
            " of the shrink factor"
        )
    var welded = _weld(geometry)
    var neighbors = _neighbors(len(welded.points) // 3, welded.faces)
    for _ in range(passes):
        _step(welded.points, neighbors, shrink)
        _step(welded.points, neighbors, inflate)
    return _geometry(welded^)


def surface_area(geometry: BufferGeometry) raises -> Area64:
    """Return the total area of the triangles of a mesh.

    Args:
        geometry: A triangle mesh with positions in meters.

    Returns:
        The sum of the triangle areas.

    Raises:
        Error: If the geometry has no positions.
    """
    ref points = geometry.attribute_view(POSITION)
    var total = 0.0
    for triangle in range(geometry.triangle_count()):
        var corners = _corners(geometry, points, triangle)
        var e = corners[1] - corners[0]
        var f = corners[2] - corners[0]
        var n = _cross(e, f)
        total += 0.5 * sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2])
    return Area64(total, SQUARE_METER)


def enclosed_volume(geometry: BufferGeometry) raises -> Volume64:
    """Return the volume that a closed mesh encloses.

    Each triangle adds the signed volume of the tetrahedron from the
    origin to it. The sum is the enclosed volume for a closed mesh whose
    faces turn outward, wherever the origin is. Faces that turn inward give
    a negative volume.

    Args:
        geometry: A closed triangle mesh with positions in meters.

    Returns:
        The signed volume.

    Raises:
        Error: If the geometry has no positions.
    """
    ref points = geometry.attribute_view(POSITION)
    var total = 0.0
    for triangle in range(geometry.triangle_count()):
        var corners = _corners(geometry, points, triangle)
        var n = _cross(corners[1], corners[2])
        var a = corners[0]
        total += (a[0] * n[0] + a[1] * n[1] + a[2] * n[2]) / 6.0
    return Volume64(total, CUBIC_METER)


def _corners(
    geometry: BufferGeometry, points: BufferAttribute, triangle: Int
) raises -> List[SIMD[DType.float64, 4]]:
    """Return the three corners of a triangle in Float64."""
    var out = List[SIMD[DType.float64, 4]]()
    for corner in range(3):  # pragma: no branch
        var p = points.vector3(geometry.corner_index(triangle, corner))
        out.append(
            SIMD[DType.float64, 4](Float64(p.x), Float64(p.y), Float64(p.z), 0)
        )
    return out^


def _cross(
    a: SIMD[DType.float64, 4], b: SIMD[DType.float64, 4]
) -> SIMD[DType.float64, 4]:
    """Return the cross product of the first three lanes."""
    return SIMD[DType.float64, 4](
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
        0,
    )
