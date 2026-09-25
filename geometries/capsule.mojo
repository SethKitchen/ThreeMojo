# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A capsule, from three.js `src/geometries/CapsuleGeometry.js`.

A cylinder with a hemisphere on each end, standing on the y axis. Its
profile runs from the bottom pole up a quarter circle, up the straight
side, and in along a quarter circle to the top pole. The vertices are
rows of that profile, bottom to top, one vertex per step around and one
more for the seam, as three.js's builder lays them out.

The arithmetic is three.js's, in doubles. The sweep starts at -x, and a
pole's vertices take a half-step `u`, as three.js's do. A normal points
along the radius of whichever cap a point is on, and straight out on the
side. `v` is the distance along the profile, over its whole length. A
capsule of no length keeps its two rims and the side between them, which
has no height.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    CAPSULE_GEOMETRY,
    NORMAL,
    POSITION,
    UV,
)
from core.user_data import UserData
from std.math import cos, pi, sin, sqrt
from units.si import Length, METER


def capsule(
    radius: Length,
    length: Length,
    cap_segments: Int = 4,
    radial_segments: Int = 8,
    height_segments: Int = 1,
) raises -> BufferGeometry:
    """Return a capsule standing on the y axis, centered on the origin,
    three.js's `CapsuleGeometry`.

    Args:
        radius: The radius of the side and of both caps.
        length: How long the straight side is, between the caps, three.js's
            `height`. Zero makes a sphere.
        cap_segments: How many rows of cells each cap has, from its rim to
            its pole; at least one.
        radial_segments: How many cells around; at least three.
        height_segments: How many rows of cells the side has; at least one.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and an
        index buffer, wound counter-clockwise seen from outside. Vertices
        run in rows from the bottom pole to the top, `radial_segments + 1`
        to a row.

    Raises:
        Error: If the radius is not positive, the length is negative, or
            any segment count is too small.
    """
    if radius.value <= 0:
        raise Error("A capsule needs a positive radius")
    if length.value < 0:
        raise Error("A capsule's length cannot be negative")
    if cap_segments < 1:
        raise Error("A capsule needs at least one segment on each cap")
    if radial_segments < 3:
        raise Error("A capsule needs at least three segments around")
    if height_segments < 1:
        raise Error("A capsule needs at least one segment up its side")

    var r = Float64(radius.to(METER))
    var height = Float64(length.to(METER))
    var half = height / 2
    var cap_arc = (pi / 2) * r
    var total = 2 * cap_arc + height
    var rows = cap_segments * 2 + height_segments
    var per_row = radial_segments + 1

    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    var index = List[Int]()
    for iy in range(rows + 1):  # pragma: no branch
        var arc: Float64
        var profile_y: Float64
        var profile_radius: Float64
        var normal_y: Float64
        if iy <= cap_segments:
            var progress = Float64(iy) / Float64(cap_segments)
            var angle = (progress * pi) / 2
            profile_y = -half - r * cos(angle)
            profile_radius = r * sin(angle)
            normal_y = -r * cos(angle)
            arc = progress * cap_arc
        elif iy <= cap_segments + height_segments:
            var progress = Float64(iy - cap_segments) / Float64(height_segments)
            profile_y = -half + progress * height
            profile_radius = r
            normal_y = 0
            arc = cap_arc + progress * height
        else:
            var progress = Float64(
                iy - cap_segments - height_segments
            ) / Float64(cap_segments)
            var angle = (progress * pi) / 2
            profile_y = half + r * sin(angle)
            profile_radius = r * cos(angle)
            normal_y = r * sin(angle)
            arc = cap_arc + height + progress * cap_arc
        var v = max(Float64(0), min(Float64(1), arc / total))
        # The poles' vertices sit half a step round, as three.js's do.
        var u_offset = Float64(0)
        if iy == 0:
            u_offset = 0.5 / Float64(radial_segments)
        elif iy == rows:
            u_offset = -0.5 / Float64(radial_segments)
        for ix in range(radial_segments + 1):  # pragma: no branch
            var u = Float64(ix) / Float64(radial_segments)
            var theta = u * pi * 2
            var sin_theta = sin(theta)
            var cos_theta = cos(theta)
            var x = -profile_radius * cos_theta
            var z = profile_radius * sin_theta
            data.append(Float32(x))
            data.append(Float32(profile_y))
            data.append(Float32(z))
            # three.js's `normalize`: divided by its length. A normal is
            # never of no length: a pole's points straight along y.
            var scale = 1 / sqrt(x * x + normal_y * normal_y + z * z)
            normals.append(Float32(x * scale))
            normals.append(Float32(normal_y * scale))
            normals.append(Float32(z * scale))
            uvs.append(Float32(u + u_offset))
            uvs.append(Float32(v))
        if iy > 0:
            var previous = (iy - 1) * per_row
            for ix in range(radial_segments):  # pragma: no branch
                var i1 = previous + ix
                var i2 = previous + ix + 1
                var i3 = iy * per_row + ix
                var i4 = iy * per_row + ix + 1
                index.append(i1)
                index.append(i2)
                index.append(i3)
                index.append(i2)
                index.append(i4)
                index.append(i3)

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(index^)
    geometry.kind = CAPSULE_GEOMETRY
    geometry.parameters = UserData()
    geometry.parameters.set_number("radius", Float64(radius.to(METER)))
    geometry.parameters.set_number("height", Float64(length.to(METER)))
    geometry.parameters.set_number("capSegments", Float64(cap_segments))
    geometry.parameters.set_number("radialSegments", Float64(radial_segments))
    geometry.parameters.set_number("heightSegments", Float64(height_segments))
    return geometry^
