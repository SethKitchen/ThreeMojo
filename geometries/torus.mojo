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

## Doubles, as in three.js

Both builders compute in `Float64`, as three.js computes in JavaScript
numbers. Each product is rounded on its own, as JavaScript rounds it. A
position, a normal and a texture coordinate is rounded to `Float32` once,
when it is stored. The knot's frame subtracts two points 0.01 apart along
the curve. In `Float32` that difference kept about two digits, and the
vertices moved by about 1e-5 meters. A torus normal subtracts the tube's
center from a point on it, and a thin tube lost digits the same way.

The arc is an `Angle`, which holds a `Float32`. A full turn is then
1.7e-7 more than three.js's `Math.PI * 2`, so a full torus can differ
from three.js's by that fraction of a vertex's distance from the center.

## Numerical range correction

Finite norm-dependent directions and lengths use scale-safe arithmetic.
Extreme finite results can differ from direct three.js r180 arithmetic.
See `docs/wiki/Norm-consumers.md` for the changed operations, retained
limits, and explicit zero and nonfinite rules.

## Input validation difference

Shape dimensions must be finite before vertices are generated. NaN and
either infinity raise an error. This differs from the unchecked three.js
r186 input path. Finite supported inputs keep their existing behavior.
"""

from core.buffer_geometry import (
    BufferGeometry,
    TORUS_GEOMETRY,
    TORUS_KNOT_GEOMETRY,
)
from geometries.surface import (
    indexed_surface,
    record_kind,
    record_tube,
    require_grid_cells,
    require_three_segments,
)
from geometries.circle import FULL_TURN, check_sweep
from geometries.grid import grid_index
from math.finite import require_finite
from math.norm import rounded_dot3, rounded_product
from std.math import cos, pi, sin, sqrt
from units.si import Angle, Length

# How far along the knot's parameter the second point is taken, to give the
# frame a tangent. three.js's step, so the frames and therefore the vertices
# match.
comptime KNOT_STEP = Float64(0.01)

comptime _Vector = SIMD[DType.float64, 4]


def _normalized(vector: _Vector) -> _Vector:
    """Return three.js's `Vector3.normalize`: the vector times one over its
    length, or the vector itself when its length is zero."""
    var length = sqrt(
        rounded_dot3(
            vector[0], vector[1], vector[2], vector[0], vector[1], vector[2]
        )
    )
    return vector * (1 / (length if length != 0 else 1))


def _cross(a: _Vector, b: _Vector) -> _Vector:
    """Return three.js's `crossVectors(a, b)`, each product rounded."""
    return _Vector(
        rounded_product(a[1], b[2]) - rounded_product(a[2], b[1]),
        rounded_product(a[2], b[0]) - rounded_product(a[0], b[2]),
        rounded_product(a[0], b[1]) - rounded_product(a[1], b[0]),
        0,
    )


def _append_tube_vertex(
    mut data: List[Float32],
    mut normals: List[Float32],
    mut uvs: List[Float32],
    vertex: _Vector,
    center: _Vector,
    u: Float64,
    v: Float64,
):
    """Append a vertex on a tube, its normal pointing away from `center`.
    The numbers are rounded to `Float32` here, once each."""
    var normal = _normalized(vertex - center)
    for axis in range(3):  # pragma: no branch
        data.append(Float32(vertex[axis]))
        normals.append(Float32(normal[axis]))
    uvs.append(Float32(u))
    uvs.append(Float32(v))


def _require_tube_radii(radius: Float32, tube: Float32, name: String) raises:
    """Refuse a tube whose path radius or tube radius is not positive.

    Nothing. The call returns when both radii are positive.

    Args:
        radius: The path radius.
        tube: The tube radius.
        name: `torus` or `torus knot`.

    Raises:
        Error: If either radius is not finite or not positive.
    """
    require_finite(Float64(radius), "A " + name + " needs finite radii")
    require_finite(Float64(tube), "A " + name + " needs finite radii")
    # `not (x > 0)`, not `x <= 0`: NaN compares false both ways, so the
    # <= form would let it through.
    if not (radius > 0) or not (tube > 0):
        raise Error(
            "A " + name + " needs a positive radius and a positive tube"
        )


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
            less than three, the grid has more than 16777216 cells, or the
            arc is not positive or is more than a turn.
    """
    _require_tube_radii(radius.value, tube.value, "torus")
    require_three_segments(
        radial_segments, "A torus needs at least three segments around its tube"
    )
    require_three_segments(
        tubular_segments, "A torus needs at least three segments along its tube"
    )
    require_grid_cells(
        radial_segments,
        tubular_segments,
        "A torus's segment count is larger than this port builds",
    )
    check_sweep(arc)

    var big = Float64(radius.value)
    var small = Float64(tube.value)
    var sweep = Float64(arc.value)
    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    # The segment counts were checked above, so every loop runs.
    for row in range(radial_segments + 1):  # pragma: no branch
        var around = Float64(row) / Float64(radial_segments) * pi * 2
        var reach = big + rounded_product(small, cos(around))
        for column in range(tubular_segments + 1):  # pragma: no branch
            var along = Float64(column) / Float64(tubular_segments) * sweep
            _append_tube_vertex(
                data,
                normals,
                uvs,
                _Vector(
                    reach * cos(along),
                    reach * sin(along),
                    small * sin(around),
                    0,
                ),
                _Vector(big * cos(along), big * sin(along), 0, 0),
                Float64(column) / Float64(tubular_segments),
                Float64(row) / Float64(radial_segments),
            )

    var geometry = BufferGeometry()
    indexed_surface(
        geometry,
        data^,
        normals^,
        uvs^,
        grid_index(radial_segments, tubular_segments, True),
    )
    record_kind(geometry, TORUS_GEOMETRY)
    record_tube(geometry, radius, tube)
    geometry.parameters.set_number("radialSegments", Float64(radial_segments))
    geometry.parameters.set_number("tubularSegments", Float64(tubular_segments))
    geometry.parameters.set_radians("arc", arc)
    return geometry^


def _knot_point(u: Float64, p: Int, q: Int, radius: Float64) -> _Vector:
    """Return the point of three.js's torus knot at parameter `u`, three.js's
    `calculatePositionOnCurve`."""
    var cu = cos(u)
    var su = sin(u)
    var through = Float64(q) / Float64(p) * u
    var cs = cos(through)
    return _Vector(
        radius * (2 + cs) * 0.5 * cu,
        radius * (2 + cs) * su * 0.5,
        radius * sin(through) * 0.5,
        0,
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
            less than three, the grid has more than 16777216 cells, or
            `p` or `q` is less than one.
    """
    _require_tube_radii(radius.value, tube.value, "torus knot")
    require_three_segments(
        tubular_segments, "A torus knot needs at least three segments along it"
    )
    require_three_segments(
        radial_segments, "A torus knot needs at least three segments around it"
    )
    require_grid_cells(
        radial_segments,
        tubular_segments,
        "A torus knot's segment count is larger than this port builds",
    )
    if p < 1 or q < 1:
        raise Error("A torus knot's p and q must be at least one")

    var big = Float64(radius.value)
    var small = Float64(tube.value)
    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    # The segment counts were checked above, so every loop runs.
    for ring in range(tubular_segments + 1):  # pragma: no branch
        var u = Float64(ring) / Float64(tubular_segments)
        var along = u * Float64(p) * pi * 2
        var here = _knot_point(along, p, q, big)
        var ahead = _knot_point(along + KNOT_STEP, p, q, big)
        # three.js's frame: the tangent, a direction across the curve taken
        # as the sum of the two points, which works because the knot goes
        # around the origin, and the two cross products, made unit length.
        var tangent = ahead - here
        var binormal = _cross(tangent, ahead + here)
        var normal = _normalized(_cross(binormal, tangent))
        binormal = _normalized(binormal)
        for step in range(radial_segments + 1):  # pragma: no branch
            var v = Float64(step) / Float64(radial_segments)
            var around = v * pi * 2
            var cx = -small * cos(around)
            var cy = small * sin(around)
            var offset = _Vector(
                rounded_product(cx, normal[0])
                + rounded_product(cy, binormal[0]),
                rounded_product(cx, normal[1])
                + rounded_product(cy, binormal[1]),
                rounded_product(cx, normal[2])
                + rounded_product(cy, binormal[2]),
                0,
            )
            _append_tube_vertex(data, normals, uvs, here + offset, here, u, v)

    var geometry = BufferGeometry()
    indexed_surface(
        geometry,
        data^,
        normals^,
        uvs^,
        grid_index(tubular_segments, radial_segments, False),
    )
    record_kind(geometry, TORUS_KNOT_GEOMETRY)
    record_tube(geometry, radius, tube)
    geometry.parameters.set_number("tubularSegments", Float64(tubular_segments))
    geometry.parameters.set_number("radialSegments", Float64(radial_segments))
    geometry.parameters.set_number("p", Float64(p))
    geometry.parameters.set_number("q", Float64(q))
    return geometry^
