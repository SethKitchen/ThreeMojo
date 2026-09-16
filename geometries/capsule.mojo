# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A capsule, from three.js `src/geometries/CapsuleGeometry.js`.

A cylinder with a hemisphere on each end, standing on the y axis. A profile
-- a quarter circle up from the bottom pole, a straight run up the side, a
quarter circle in to the top pole -- revolved around the axis, the way a
lathe turns it: one column of vertices per step around and one vertex per
profile point up each column. three.js once built it on its lathe and now
builds the same surface directly. This takes its normals from the profile
exactly, along the radius of whichever cap a point is on and straight out
on the side, rather than from the profile's neighboring points, so the
caps and the side meet without a crease.

Texture coordinates run around for `u` and up the profile for `v`, by
distance along it, so the caps and the side keep their share of the image
whatever the segment counts are. The sweep starts at +z, as the cylinder's
does; three.js's current builder starts at -x and gives its pole vertices a
half-step `u`. The shape is the same, and a texture lands a quarter turn
on.

Each pole is one point that every column repeats, for the reason the
sphere's are: the columns need a vertex to close on. The half of each cell
against a pole that has no area is left out, as the cylinder leaves out
the cells against its apex. A capsule of no length has one rim, not two:
its top cap continues from the bottom cap's rim, so nothing collapses.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from std.math import cos, pi, sin
from units.si import Length


def _append_profile_point(
    mut across: List[Float32],
    mut up: List[Float32],
    mut lean_across: List[Float32],
    mut lean_up: List[Float32],
    mut along: List[Float32],
    x: Float32,
    y: Float32,
    normal_x: Float32,
    normal_y: Float32,
    distance: Float32,
):
    """Append one point of the profile, the normal it carries, both in the
    plane the profile is drawn in with `x` out from the axis and `y` along
    it, and how far along the profile it lies from the bottom pole."""
    along.append(distance)
    across.append(x)
    up.append(y)
    lean_across.append(normal_x)
    lean_up.append(normal_y)


def capsule(
    radius: Length,
    length: Length,
    cap_segments: Int = 4,
    radial_segments: Int = 8,
    height_segments: Int = 1,
) raises -> BufferGeometry:
    """Return a capsule standing on the y axis, centered on the origin.

    Args:
        radius: The radius of the side and of both caps.
        length: How long the straight side is, between the caps. Zero
            makes a sphere.
        cap_segments: How many rows of cells each cap has, from its rim to
            its pole; at least one.
        radial_segments: How many cells around; at least three.
        height_segments: How many rows of cells the side has; at least one.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and an
        index buffer, wound counter-clockwise seen from outside. Vertices
        run in columns, one per step around, each from the bottom pole to
        the top. `u` runs around and `v` up the profile by distance along
        it, zero at the bottom pole and one at the top, so the caps and the
        side keep their share of the image whatever the segment counts.

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

    var r = radius.value
    var straight = length.value
    var half = straight / 2
    var quarter = Float32(pi) / 2
    # The profile's length from pole to pole: two quarter circles and the
    # side. `v` is a point's distance along it over this.
    var total = Float32(pi) * r + straight
    # The profile, bottom pole to top pole: a quarter circle around the
    # bottom cap's center, the side, and a quarter circle around the top's.
    # Each point carries the direction the surface faces there and how far
    # along the profile it lies. The segment counts were checked above, so
    # every cap loop runs.
    var across = List[Float32]()
    var up = List[Float32]()
    var lean_across = List[Float32]()
    var lean_up = List[Float32]()
    var along = List[Float32]()
    for step in range(cap_segments + 1):  # pragma: no branch
        var turn = Float32(step) / Float32(cap_segments) * quarter
        var angle = turn - quarter
        _append_profile_point(
            across,
            up,
            lean_across,
            lean_up,
            along,
            r * cos(angle),
            -half + r * sin(angle),
            cos(angle),
            sin(angle),
            r * turn,
        )
    if straight > 0:
        for step in range(1, height_segments):
            var rise = Float32(step) / Float32(height_segments) * straight
            _append_profile_point(
                across,
                up,
                lean_across,
                lean_up,
                along,
                r,
                -half + rise,
                1,
                0,
                quarter * r + rise,
            )
    # A capsule of no length has one rim, not two: the top cap continues
    # from the bottom cap's rim rather than repeating it, so there is no
    # side of collapsed cells between them.
    var first = 0
    if straight == 0:
        first = 1
    for step in range(first, cap_segments + 1):  # pragma: no branch
        var turn = Float32(step) / Float32(cap_segments) * quarter
        _append_profile_point(
            across,
            up,
            lean_across,
            lean_up,
            along,
            r * cos(turn),
            half + r * sin(turn),
            cos(turn),
            sin(turn),
            quarter * r + straight + r * turn,
        )

    var points = len(across)
    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    for column in range(radial_segments + 1):  # pragma: no branch
        var u = Float32(column) / Float32(radial_segments)
        var phi = u * 2 * Float32(pi)
        var sin_phi = sin(phi)
        var cos_phi = cos(phi)
        for row in range(points):  # pragma: no branch
            data.append(across[row] * sin_phi)
            data.append(up[row])
            data.append(across[row] * cos_phi)
            normals.append(lean_across[row] * sin_phi)
            normals.append(lean_up[row])
            normals.append(lean_across[row] * cos_phi)
            uvs.append(u)
            uvs.append(along[row] / total)

    var index = List[Int]()
    for column in range(radial_segments):  # pragma: no branch
        for row in range(points - 1):  # pragma: no branch
            var a = row + column * points
            var b = row + (column + 1) * points
            var c = row + 1 + (column + 1) * points
            var d = row + 1 + column * points
            # Two triangles per cell, counter-clockwise from outside, in
            # the lathe's order. The two corners on a pole coincide, so the
            # half of the cell they alone would span is left out.
            if row != 0:
                index.append(a)
                index.append(b)
                index.append(d)
            if row != points - 2:
                index.append(c)
                index.append(d)
                index.append(b)

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(index^)
    return geometry^
