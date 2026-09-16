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
way its segment does, and the last the way its own does.

A profile that comes back along a segment to exactly the point before it
leaves that corner facing nowhere: the two normals cancel, and there is no
direction to make unit length. It is refused, rather than given a normal
that is not one.

A point on the axis, with `x` of zero, is one point that every column
repeats, a pole. The half of each cell against it that has no area is left
out, as the cylinder leaves out the cells against its apex; three.js emits
those triangles and lets the rasterizer discard them.

The profile's numbers are bare meters, as a `Vector3` position is: the
lathe is where a shape drawn by hand meets the scene, and the drawing is
made of plain points.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from geometries.circle import FULL_TURN, check_sweep
from math.vector2 import Vector2
from std.math import cos, sin, sqrt
from units.si import Angle, RADIAN


def _unit(x: Float32, y: Float32) -> Vector2:
    """Return a direction in the profile's plane made unit length. The
    caller has checked the direction is not zero."""
    var length = sqrt(x * x + y * y)
    return Vector2(x / length, y / length)


def _profile_normals(points: List[Vector2]) raises -> List[Vector2]:
    """Return the direction each profile point faces, three.js's way.

    A segment from one point to the next faces `(dy, -dx)`, its direction
    turned a quarter turn toward +x and as long as the segment. The first
    point faces the way its segment does; every point after it faces the
    sum of the segment before it and the segment after it, so a corner
    shades smoothly and a longer segment weighs more; the last point, with
    no segment after it, faces the way the last segment does. The ends are
    made unit length as well, which three.js leaves undone for the last.
    Consecutive points were checked to differ, so no segment is zero, but
    two that cancel are caught here.

    Raises:
        Error: If a point's two segments face exactly opposite ways, which
            leaves it no direction to face.
    """
    var normals = List[Vector2]()
    var previous = Vector2(0, 0)
    for index in range(len(points)):  # pragma: no branch
        if index == len(points) - 1:
            normals.append(_unit(previous.x, previous.y))
            continue
        var dx = points[index + 1].x - points[index].x
        var dy = points[index + 1].y - points[index].y
        var ahead = Vector2(dy, -dx)
        if index == 0:
            normals.append(_unit(ahead.x, ahead.y))
        else:
            var summed = Vector2(ahead.x + previous.x, ahead.y + previous.y)
            if summed.x == 0 and summed.y == 0:
                raise Error("A lathe's profile cannot turn straight back")
            normals.append(_unit(summed.x, summed.y))
        previous = ahead
    return normals^


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
        Error: If there are fewer than two points, a point has a negative
            `x`, two consecutive points coincide, the profile turns
            straight back to the point before, there are fewer than one
            segment, or the sweep is not positive or is more than a turn.
    """
    if len(points) < 2:
        raise Error("A lathe needs a profile of at least two points")
    for index in range(len(points)):  # pragma: no branch
        if points[index].x < 0:
            raise Error("A lathe's profile lies on one side of the axis")
    for index in range(len(points) - 1):  # pragma: no branch
        if (
            points[index].x == points[index + 1].x
            and points[index].y == points[index + 1].y
        ):
            raise Error("A lathe's profile cannot repeat a point")
    if segments < 1:
        raise Error("A lathe needs at least one segment around")
    check_sweep(phi_length)

    var normals_2d = _profile_normals(points)
    var count = len(points)
    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    for column in range(segments + 1):  # pragma: no branch
        var u = Float32(column) / Float32(segments)
        var phi = phi_start.value + u * phi_length.value
        var sin_phi = sin(phi)
        var cos_phi = cos(phi)
        for row in range(count):  # pragma: no branch
            data.append(points[row].x * sin_phi)
            data.append(points[row].y)
            data.append(points[row].x * cos_phi)
            normals.append(normals_2d[row].x * sin_phi)
            normals.append(normals_2d[row].y)
            normals.append(normals_2d[row].x * cos_phi)
            uvs.append(u)
            uvs.append(Float32(row) / Float32(count - 1))

    var index = List[Int]()
    for column in range(segments):  # pragma: no branch
        for row in range(count - 1):  # pragma: no branch
            var a = row + column * count
            var b = row + (column + 1) * count
            var c = row + 1 + (column + 1) * count
            var d = row + 1 + column * count
            # Two triangles per cell in three.js's order, less the half
            # whose two corners sit on the axis.
            if points[row].x != 0:
                index.append(a)
                index.append(b)
                index.append(d)
            if points[row + 1].x != 0:
                index.append(c)
                index.append(d)
                index.append(b)

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(index^)
    return geometry^
