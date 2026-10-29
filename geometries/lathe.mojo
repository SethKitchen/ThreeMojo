# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A profile revolved around the y axis, from three.js
`src/geometries/LatheGeometry.js`.

A lathe turns a flat profile -- a list of points with `x` out from the axis
and `y` along it -- into a solid of revolution: a vase, a bowl, a bottle.
One column of vertices per step around, one vertex per profile point up
each column, two triangles per cell. The capsule is one of these with its
profile built in and its normals worked out exactly; this takes any
profile and works its normals out the way three.js does, from the profile's
own segments: each segment faces away from itself, turned a quarter turn
and as long as the segment is, and a corner faces the sum of the two
segments it joins, made unit length. The longer segment pulls the corner
its way, which is three.js's weighting exactly. The first point faces the
way its segment does, made unit length. The last faces the way its own
segment does, and three.js leaves that one as long as the segment, so
this does too.

A profile that comes back along a segment to exactly the point before it
leaves that corner facing nowhere: the two normals cancel, and there is no
direction to make unit length. It is refused, rather than given a normal
that is not one.

A point on the axis, with `x` of zero, is one point that every column
repeats, a pole. The half of each cell against it has no area. three.js
emits it and lets the rasterizer discard it, and so does this, so the
index is three.js's.

The profile's numbers are bare meters, as a `Vector3` position is: the
lathe is where a shape drawn by hand meets the scene, and the drawing is
made of plain points.

The arithmetic is three.js's, in doubles, and each number is rounded to
`Float32` once, when it is stored. three.js clamps the sweep to a turn,
and so does this, so a `Float32` full turn is three.js's `Math.PI * 2`.
"""

from core.buffer_geometry import BufferGeometry, LATHE_GEOMETRY
from geometries.surface import (
    indexed_surface,
    record_kind,
    record_phi,
    require_grid_cells,
)
from math.curve_checks import require_at_least_one
from core.user_data import json_number_text
from geometries.circle import FULL_TURN, check_sweep
from math.finite import require_finite, require_finite_group
from math.norm import rounded_product
from math.vector2 import Vector2
from std.math import cos, pi, sin, sqrt
from units.si import Angle, RADIAN


comptime _Normal = SIMD[DType.float64, 2]


def _unit(v: _Normal) -> _Normal:
    """Return three.js's `Vector3.normalize` of a nonzero direction in the
    profile's plane: the direction times one over its length."""
    var length = sqrt(rounded_product(v[0], v[0]) + rounded_product(v[1], v[1]))
    return v * (1 / length)


def _wide_unit(before: Vector2, after: Vector2) raises -> _Normal:
    """Return the unit normal of the outer endpoint difference."""
    var x = Float64(after.y) - Float64(before.y)
    var y = Float64(before.x) - Float64(after.x)
    if x == 0 and y == 0:
        raise Error("A lathe's profile cannot turn straight back")
    return _unit(_Normal(x, y))


def _profile_normals(points: List[Vector2]) raises -> List[_Normal]:
    """Return the direction each profile point faces, three.js's way, in
    doubles.

    A segment from one point to the next faces `(dy, -dx)`, its direction
    turned a quarter turn toward +x and as long as the segment. The first
    point faces the way its segment does; every point after it faces the
    sum of the segment before it and the segment after it, so a corner
    shades smoothly and a longer segment weighs more; the last point, with
    no segment after it, faces the way the last segment does, left as long
    as that segment, as three.js leaves it.
    Consecutive points were checked to differ, so no segment is zero, but
    two that cancel are caught here. No difference of `Float32` points, nor
    its square, overflows a double.

    Raises:
        Error: If a point's two segments face exactly opposite ways, which
            leaves it no direction to face, or the last unnormalized normal
            cannot fit in Float32.
    """
    var normals = List[_Normal]()
    var previous = _Normal(0, 0)
    for index in range(len(points)):  # pragma: no branch
        if index == len(points) - 1:
            # Checked radii are nonnegative Float32 values, so their
            # difference (previous[1]) fits in Float32.
            require_finite(
                Float64(Float32(previous[0])),
                "A lathe's final profile normal must fit in Float32",
            )
            normals.append(previous)
            continue
        var dx = Float64(points[index + 1].x) - Float64(points[index].x)
        var dy = Float64(points[index + 1].y) - Float64(points[index].y)
        var ahead = _Normal(dy, -dx)
        if index == 0:
            normals.append(_unit(ahead))
        else:
            var summed = ahead + previous
            if summed[0] == 0 and summed[1] == 0:
                # The two segment normals cancel, and three.js would leave
                # a zero normal. The outer endpoint difference tells an
                # exact return from cancellation in rounded differences.
                normals.append(_wide_unit(points[index - 1], points[index + 1]))
            else:
                normals.append(_unit(summed))
        previous = ahead
    return normals^


def _points_json(points: List[Vector2]) raises -> String:
    """Return the profile as three.js's JSON writes its `points`: an
    object of `x` and `y` for each."""
    var out = String("[")
    for at in range(len(points)):  # pragma: no branch
        if at > 0:
            out += ","
        out += '{"x":' + json_number_text(Float64(points[at].x))
        out += ',"y":' + json_number_text(Float64(points[at].y)) + "}"
    return out + "]"


def lathe(
    points: List[Vector2],
    segments: Int = 12,
    phi_start: Angle = Angle(0.0, RADIAN),
    phi_length: Angle = FULL_TURN,
) raises -> BufferGeometry:
    """Return a profile revolved around the y axis.

    Args:
        points: The profile, at least two points, each with `x` out from
            the axis, zero or more, and `y` along it, in meters. Consecutive
            points must differ.
        segments: How many cells around; at least one.
        phi_start: Where the sweep starts, at +z and running toward +x.
        phi_length: How far it sweeps. A full turn, the default, closes the
            solid; less makes a section.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and an
        index buffer, wound counter-clockwise seen from outside. Vertices
        run in columns, one per step around, one vertex per profile point.
        `u` runs around and `v` up the profile, one point per equal step.

    Raises:
        Error: If there are fewer than two points, a point is not finite
            or has a negative `x`, two consecutive points coincide, the profile turns
            straight back to the point before, there are fewer than one
            segment, the grid has more than 16777216 cells, the final
            profile normal cannot fit in Float32, or the sweep is not
            positive or is more than a turn.
    """
    if len(points) < 2:
        raise Error("A lathe needs a profile of at least two points")
    for index in range(len(points)):  # pragma: no branch
        require_finite_group(
            points[index].is_finite(),
            "A lathe's profile points must be finite",
        )
        if points[index].x < 0:
            raise Error("A lathe's profile lies on one side of the axis")
    for index in range(len(points) - 1):  # pragma: no branch
        if (
            points[index].x == points[index + 1].x
            and points[index].y == points[index + 1].y
        ):
            raise Error("A lathe's profile cannot repeat a point")
    require_at_least_one(segments, "A lathe needs at least one segment around")
    require_grid_cells(
        segments,
        len(points) - 1,
        "A lathe's segment count is larger than this port builds",
    )
    check_sweep(phi_length)

    var normals_2d = _profile_normals(points)
    var count = len(points)
    # three.js's arithmetic, in doubles, the product before each sum
    # rounded on its own. The sweep is clamped to a turn, so a Float32 full
    # turn becomes three.js's `Math.PI * 2`.
    var inverse_segments = 1.0 / Float64(segments)
    var sweep = min(Float64(phi_length.value), pi * 2)
    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    for column in range(segments + 1):  # pragma: no branch
        var phi = Float64(phi_start.value) + rounded_product(
            Float64(column) * inverse_segments, sweep
        )
        var sin_phi = sin(phi)
        var cos_phi = cos(phi)
        for row in range(count):  # pragma: no branch
            var x = Float64(points[row].x)
            data.append(Float32(x * sin_phi))
            data.append(points[row].y)
            data.append(Float32(x * cos_phi))
            normals.append(Float32(normals_2d[row][0] * sin_phi))
            normals.append(Float32(normals_2d[row][1]))
            normals.append(Float32(normals_2d[row][0] * cos_phi))
            uvs.append(Float32(Float64(column) / Float64(segments)))
            uvs.append(Float32(Float64(row) / Float64(count - 1)))

    var index = List[Int]()
    for column in range(segments):  # pragma: no branch
        for row in range(count - 1):  # pragma: no branch
            var a = row + column * count
            var b = row + (column + 1) * count
            var c = row + 1 + (column + 1) * count
            var d = row + 1 + column * count
            # Two triangles per cell in three.js's order, the one against
            # a pole included.
            index.append(a)
            index.append(b)
            index.append(d)
            index.append(c)
            index.append(d)
            index.append(b)

    var geometry = BufferGeometry()
    indexed_surface(geometry, data^, normals^, uvs^, index^)
    record_kind(geometry, LATHE_GEOMETRY)
    geometry.parameters.set_json("points", _points_json(points))
    geometry.parameters.set_number("segments", Float64(segments))
    record_phi(geometry, phi_start, phi_length)
    return geometry^
