# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A box with rounded edges and corners, from three.js
`examples/jsm/geometries/RoundedBoxGeometry.js`.

three.js starts from a unit box cut into an odd number of cells on every
face, `2 * segments + 1`, so that a flat band of cells runs down the middle
of each face. Every vertex is then moved. Its normal is the direction from
the center of the unit box to the vertex, pulled half a cell in toward the
middle on each axis and made unit length. The new position is the corner of
a smaller box, shrunk by the radius, plus the radius along that normal. The
cells nearest the edges bend round the corner, and the middle band stays
flat, because every vertex in it points the same way.

three.js's `BoxGeometry` with segments is not ported, so this builds the
unit box itself, with three.js's `buildPlane` order and winding: the faces
right, left, top, bottom, front, back, each a grid of cells, two triangles
a cell. `box` here orders its faces differently and has no segments.

The texture coordinates are three.js's. Across each face, `u` and `v` are
measured along the arc of the rounded edge and the flat band between, so a
texture is not squeezed where the surface bends.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    MaterialIndex,
    NORMAL,
    POSITION,
    UV,
)
from std.math import acos, pi, sqrt
from units.si import Length, METER


def _sign(value: Float64) -> Float64:
    """Return JavaScript's `Math.sign`: one, minus one or zero."""
    return 1.0 if value > 0 else (-1.0 if value < 0 else 0.0)


def _length(v: List[Float64]) -> Float64:
    """Return the length of a three-number vector."""
    return sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])


def _get_uv(
    face_axis: Int,
    face_sign: Float64,
    normal: List[Float64],
    uv_axis: Int,
    projection_axis: Int,
    radius: Float64,
    side_length: Float64,
) -> Float64:
    """Return one texture coordinate of a vertex, three.js's `getUv`.

    The normal is flattened onto the plane across `projection_axis`, and
    the angle between it and the face's own direction says how far round
    the arc of the edge the vertex is.
    """
    var total_arc_length = 2 * pi * radius / 4
    var center_length = max(side_length - 2 * radius, 0)
    var half_arc = pi / 4
    var flat = normal.copy()
    flat[projection_axis] = 0
    # three.js's `normalize`, which multiplies by one over the length, or
    # by one when the length is zero.
    var flat_length = _length(flat)
    var scale = 1.0 / (flat_length if flat_length != 0 else 1.0)
    for axis in range(3):  # pragma: no branch
        flat[axis] = flat[axis] * scale
    var arc_uv_ratio = (
        0.5 * total_arc_length / (total_arc_length + center_length)
    )
    # three.js's `angleTo`, against a unit vector along the face's axis.
    var denominator = sqrt(
        flat[0] * flat[0] + flat[1] * flat[1] + flat[2] * flat[2]
    )
    var angle = (
        acos(
            min(max(flat[face_axis] * face_sign / denominator, -1), 1)
        ) if denominator
        != 0 else pi / 2
    )
    var arc_angle_ratio = 1.0 - angle / half_arc
    if _sign(flat[uv_axis]) == 1:
        return arc_angle_ratio * arc_uv_ratio
    var length_uv = center_length / (total_arc_length + center_length)
    return length_uv + arc_uv_ratio + arc_uv_ratio * (1.0 - arc_angle_ratio)


def _unit_box(segments: Int) -> List[Float64]:
    """Return the vertices of three.js's segmented unit box, three numbers
    each, read through its index so each triangle owns its corners.

    The six faces come in three.js's order, right, left, top, bottom,
    front and back, each with `segments` cells each way.
    """
    # Per face: the axes `u`, `v` and `w` stand for, the directions of `u`
    # and `v`, and the side of the box the face is on. From three.js's six
    # `buildPlane` calls, with every extent one.
    var u_axes = [2, 2, 0, 0, 0, 0]
    var v_axes = [1, 1, 2, 2, 1, 1]
    var w_axes = [0, 0, 1, 1, 2, 2]
    var u_dirs = [-1.0, 1.0, 1.0, 1.0, 1.0, -1.0]
    var v_dirs = [-1.0, -1.0, 1.0, -1.0, -1.0, -1.0]
    var w_sides = [0.5, -0.5, 0.5, -0.5, 0.5, -0.5]
    var step = 1.0 / Float64(segments)
    var row = segments + 1
    var out = List[Float64]()
    for face in range(6):  # pragma: no branch
        var grid = List[Float64]()
        for iy in range(row):  # pragma: no branch
            var y = Float64(iy) * step - 0.5
            for ix in range(row):  # pragma: no branch
                var x = Float64(ix) * step - 0.5
                var vector = [0.0, 0.0, 0.0]
                vector[u_axes[face]] = x * u_dirs[face]
                vector[v_axes[face]] = y * v_dirs[face]
                vector[w_axes[face]] = w_sides[face]
                # three.js stores the box in a `Float32Array` and reads it
                # back, so the numbers are rounded to `Float32` here too. It
                # matters: it decides which way a normal meant to be flat
                # on a face leans by a hair, and so which half of the face
                # `getUv` puts it in.
                for axis in range(3):  # pragma: no branch
                    grid.append(Float64(Float32(vector[axis])))
        for iy in range(segments):  # pragma: no branch
            for ix in range(segments):  # pragma: no branch
                var a = ix + row * iy
                var b = ix + row * (iy + 1)
                var c = (ix + 1) + row * (iy + 1)
                var d = (ix + 1) + row * iy
                var corners = [a, b, d, b, c, d]
                for corner in range(6):  # pragma: no branch
                    for axis in range(3):  # pragma: no branch
                        out.append(grid[corners[corner] * 3 + axis])
    return out^


def rounded_box(
    width: Length,
    height: Length,
    depth: Length,
    segments: Int = 2,
    radius: Length = Length(0.1, METER),
) raises -> BufferGeometry:
    """Return a box with rounded edges, centered on the origin, three.js's
    `RoundedBoxGeometry`.

    Args:
        width: Extent along x.
        height: Extent along y.
        depth: Extent along z.
        segments: Cells round each rounded edge, one or more. Two by
            default, as in three.js.
        radius: The radius of the edges, zero or more. A tenth of a meter by
            default, as in three.js. A radius over half the shortest extent
            is cut down to that half.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and no
        index. It has six groups, one a face, in three.js's order: right,
        left, top, bottom, front, back.

    Raises:
        Error: If an extent is not positive, `segments` is less than one, or
            the radius is negative.
    """
    if width.value <= 0 or height.value <= 0 or depth.value <= 0:
        raise Error("A rounded box needs positive extents")
    if segments < 1:
        raise Error("A rounded box needs one segment round each edge")
    if radius.value < 0:
        raise Error("A rounded box needs a radius of zero or more")

    var sizes = [
        Float64(width.value),
        Float64(height.value),
        Float64(depth.value),
    ]
    var r = min(
        min(sizes[0] / 2, sizes[1] / 2),
        min(sizes[2] / 2, Float64(radius.value)),
    )
    var total_segments = segments * 2 + 1
    var unit = _unit_box(total_segments)
    var inner = [sizes[0] / 2 - r, sizes[1] / 2 - r, sizes[2] / 2 - r]
    var half_segment = 0.5 / Float64(total_segments)
    var per_side = len(unit) // 3 // 6

    # Per face: the axis and direction it faces, then for `u` and for `v`
    # the axis measured, the axis flattened out and whether the coordinate
    # is flipped. From three.js's `switch ( side )`.
    var face_axes = [0, 0, 1, 1, 2, 2]
    var face_signs = [1.0, -1.0, 1.0, -1.0, 1.0, -1.0]
    var u_axes = [2, 2, 0, 0, 0, 0]
    var u_projections = [1, 1, 2, 2, 1, 1]
    var u_flips = [False, True, True, True, True, False]
    var v_axes = [1, 1, 2, 2, 1, 1]
    var v_projections = [2, 2, 0, 0, 0, 0]
    var v_flips = [True, True, False, True, True, True]

    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    for vertex in range(len(unit) // 3):  # pragma: no branch
        var position: List[Float64] = [
            unit[vertex * 3],
            unit[vertex * 3 + 1],
            unit[vertex * 3 + 2],
        ]
        var normal = position.copy()
        for axis in range(3):  # pragma: no branch
            normal[axis] -= _sign(normal[axis]) * half_segment
        var scale = 1.0 / _length(normal)
        for axis in range(3):  # pragma: no branch
            normal[axis] = normal[axis] * scale
        for axis in range(3):  # pragma: no branch
            data.append(
                Float32(inner[axis] * _sign(position[axis]) + normal[axis] * r)
            )
            normals.append(Float32(normal[axis]))
        var side = vertex // per_side
        var u = _get_uv(
            face_axes[side],
            face_signs[side],
            normal,
            u_axes[side],
            u_projections[side],
            r,
            sizes[u_axes[side]],
        )
        var v = _get_uv(
            face_axes[side],
            face_signs[side],
            normal,
            v_axes[side],
            v_projections[side],
            r,
            sizes[v_axes[side]],
        )
        uvs.append(Float32(1.0 - u if u_flips[side] else u))
        uvs.append(Float32(1.0 - v if v_flips[side] else v))

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    for side in range(6):  # pragma: no branch
        geometry.add_group(side * per_side, per_side, MaterialIndex(side))
    return geometry^
