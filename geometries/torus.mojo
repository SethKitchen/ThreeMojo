# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A torus and a torus knot, from three.js `src/geometries/TorusGeometry.js`
and `src/geometries/TorusKnotGeometry.js`.

A torus is a tube bent around a circle in the xy plane: a ring of vertices
around the tube at each step around the circle, two triangles per cell, the
grid the sphere and the cylinder are. A vertex's normal is its direction
from the center of the tube where it sits, so the shading is smooth around
the tube and along it.

A torus knot is the same tube bent around a knot: a curve that winds `p`
times around the axis while it winds `q` times through the hole, in
three.js's parametrization. The frame the tube is built in is three.js's
rather than a Frenet frame: the tangent, a second direction taken as the
sum of two nearby points on the curve, and their cross products, normalized.
It gives the same vertices three.js gives, so a texture mapped there lands
the same way here.

Both close on themselves. `u` runs once along the tube's path and `v` once
around the tube, and each seam has a vertex on each side for the reason the
sphere's does: one carries zero and the other one.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from geometries.circle import FULL_TURN, check_sweep
from math.vector3 import Vector3
from std.math import cos, pi, sin
from units.si import Angle, Length

# How far along the knot's parameter the second point is taken, to give the
# frame a tangent. three.js's step, so the frames and therefore the vertices
# match.
comptime KNOT_STEP = Float32(0.01)


def _append_tube_vertex(
    mut data: List[Float32],
    mut normals: List[Float32],
    mut uvs: List[Float32],
    vertex: Vector3,
    center: Vector3,
    u: Float32,
    v: Float32,
):
    """Append a vertex on a tube, its normal pointing away from `center`."""
    data.append(vertex.x)
    data.append(vertex.y)
    data.append(vertex.z)
    var normal = vertex - center
    normal.normalize()
    normals.append(normal.x)
    normals.append(normal.y)
    normals.append(normal.z)
    uvs.append(u)
    uvs.append(v)


def _grid_index(rows: Int, columns: Int, row_first: Bool) -> List[Int]:
    """Return the index of a grid of `rows + 1` by `columns + 1` vertices,
    two triangles per cell.

    three.js winds its two tubes opposite ways round the cell, because their
    rows run opposite ways round the tube: the torus starts each cell on the
    current row and the knot on the row before. `row_first` picks which, so
    both come out counter-clockwise seen from outside and cell for cell what
    three.js emits.
    """
    var stride = columns + 1
    var index = List[Int]()
    for row in range(1, rows + 1):  # pragma: no branch
        var before = stride * (row - 1)
        var here = stride * row
        for column in range(1, columns + 1):  # pragma: no branch
            var a: Int
            var b: Int
            var c: Int
            var d: Int
            if row_first:
                a = here + column - 1
                b = before + column - 1
                c = before + column
                d = here + column
            else:
                a = before + column - 1
                b = here + column - 1
                c = here + column
                d = before + column
            index.append(a)
            index.append(b)
            index.append(d)
            index.append(b)
            index.append(c)
            index.append(d)
    return index^


def torus(
    radius: Length,
    tube: Length,
    radial_segments: Int = 12,
    tubular_segments: Int = 48,
    arc: Angle = FULL_TURN,
) raises -> BufferGeometry:
    """Return a torus around the z axis, centered on the origin.

    Args:
        radius: From the center of the torus to the center of the tube.
        tube: The radius of the tube.
        radial_segments: How many cells around the tube; at least three.
        tubular_segments: How many cells along it; at least three.
        arc: How far around the circle the tube runs, from +x toward +y.
            A full turn, the default, closes the ring.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and an
        index buffer, wound counter-clockwise seen from outside. Vertices
        run in rows, one row per step around the tube, `tubular_segments +
        1` to a row. `u` runs along the tube and `v` around it.

    Raises:
        Error: If either radius is not positive, either segment count is
            less than three, or the arc is not positive or is more than a
            turn.
    """
    if radius.value <= 0 or tube.value <= 0:
        raise Error("A torus needs a positive radius and a positive tube")
    if radial_segments < 3:
        raise Error("A torus needs at least three segments around its tube")
    if tubular_segments < 3:
        raise Error("A torus needs at least three segments along its tube")
    check_sweep(arc)

    var big = radius.value
    var small = tube.value
    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    # The segment counts were checked above, so every loop runs.
    for row in range(radial_segments + 1):  # pragma: no branch
        var v = Float32(row) / Float32(radial_segments)
        var around = v * 2 * Float32(pi)
        for column in range(tubular_segments + 1):  # pragma: no branch
            var u = Float32(column) / Float32(tubular_segments)
            var along = u * arc.value
            var center = Vector3(big * cos(along), big * sin(along), 0)
            var reach = big + small * cos(around)
            _append_tube_vertex(
                data,
                normals,
                uvs,
                Vector3(
                    reach * cos(along), reach * sin(along), small * sin(around)
                ),
                center,
                u,
                v,
            )

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(_grid_index(radial_segments, tubular_segments, True))
    return geometry^


def _knot_point(u: Float32, p: Int, q: Int, radius: Float32) -> Vector3:
    """Return the point of three.js's torus knot at parameter `u`."""
    var cu = cos(u)
    var su = sin(u)
    var through = Float32(q) / Float32(p) * u
    var cs = cos(through)
    return Vector3(
        radius * (2 + cs) * 0.5 * cu,
        radius * (2 + cs) * su * 0.5,
        radius * sin(through) * 0.5,
    )


def torus_knot(
    radius: Length,
    tube: Length,
    tubular_segments: Int = 64,
    radial_segments: Int = 8,
    p: Int = 2,
    q: Int = 3,
) raises -> BufferGeometry:
    """Return a tube bent around a torus knot, centered on the origin.

    Args:
        radius: The size of the knot, as three.js measures it: the curve
            lies between half and one and a half of this from the axis.
        tube: The radius of the tube.
        tubular_segments: How many cells along the curve; at least three.
        radial_segments: How many cells around the tube; at least three.
        p: How many times the curve winds around the axis; at least one.
        q: How many times it winds through the hole; at least one.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and an
        index buffer, wound counter-clockwise seen from outside. Vertices
        run in rings, one per step along the curve, `radial_segments + 1`
        to a ring. `u` runs along the curve and `v` around the tube.

    Raises:
        Error: If either radius is not positive, either segment count is
            less than three, or `p` or `q` is less than one.
    """
    if radius.value <= 0 or tube.value <= 0:
        raise Error("A torus knot needs a positive radius and a positive tube")
    if tubular_segments < 3:
        raise Error("A torus knot needs at least three segments along it")
    if radial_segments < 3:
        raise Error("A torus knot needs at least three segments around it")
    if p < 1 or q < 1:
        raise Error("A torus knot's p and q must be at least one")

    var big = radius.value
    var small = tube.value
    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    # The segment counts were checked above, so every loop runs.
    for ring in range(tubular_segments + 1):  # pragma: no branch
        var u = Float32(ring) / Float32(tubular_segments)
        var along = u * Float32(p) * 2 * Float32(pi)
        var here = _knot_point(along, p, q, big)
        var ahead = _knot_point(along + KNOT_STEP, p, q, big)
        # three.js's frame: the tangent, a direction across the curve taken
        # as the sum of the two points, which works because the knot goes
        # around the origin, and the two cross products, made unit length.
        var tangent = ahead - here
        var across = ahead + here
        var binormal = tangent
        binormal.cross(across)
        var normal = binormal
        normal.cross(tangent)
        binormal.normalize()
        normal.normalize()
        for step in range(radial_segments + 1):  # pragma: no branch
            var v = Float32(step) / Float32(radial_segments)
            var around = v * 2 * Float32(pi)
            var cx = -small * cos(around)
            var cy = small * sin(around)
            _append_tube_vertex(
                data,
                normals,
                uvs,
                here + normal * cx + binormal * cy,
                here,
                u,
                v,
            )

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(_grid_index(tubular_segments, radial_segments, False))
    return geometry^
