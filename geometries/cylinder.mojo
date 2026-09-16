# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cylinder and a cone, from three.js `src/geometries/CylinderGeometry.js`
and `src/geometries/ConeGeometry.js`.

A cylinder stands on the y axis, centered on the origin, with one radius at
the top and another at the bottom: a cone is a cylinder whose top radius is
zero, and a frustum one whose two radii differ. The side is the plane's grid
bent around the axis, a row of vertices at each height from the top down and
a column at each angle, two triangles per cell. Each cap is a fan like
`circle`'s, except that three.js gives it one center vertex per segment
rather than one for the whole cap, and so does this, so the two ports have
the same vertex count.

The side's normals lean with the side. On a cylinder they are horizontal; on
a cone they tilt up by the slope of the side, the same tilt in every row, so
the apex has one normal per column and light falls across it the way it
falls across the side below. A cap's normals point straight along the axis.

The sweep starts at +z and runs toward +x, as three.js's does, which is not
the convention `circle` uses: its rim starts at +x. Both are kept because
both are three.js's, so a texture mapped in three.js lands the same way
here. A full turn puts the first and last column in the same place, for the
reason the sphere's seam does: u is zero on one and one on the other.

A zero radius at one end makes that end a point. Its row of vertices all sit
on the axis, one per column so that each carries its own normal, and the
cells against it are triangles rather than quads: three.js skips the half of
each cell that has no area, and so does this. That end gets no cap.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from geometries.circle import FULL_TURN, check_sweep
from std.math import cos, sin, sqrt
from units.si import Angle, Length, METER, RADIAN


def _append_cap(
    mut data: List[Float32],
    mut normals: List[Float32],
    mut uvs: List[Float32],
    mut index: List[Int],
    radius: Float32,
    half_height: Float32,
    radial_segments: Int,
    theta_start: Float32,
    theta_length: Float32,
    top: Bool,
):
    """Append one cap: a fan facing up from the top or down from the bottom.

    The center comes first, one vertex per segment as three.js emits it, then
    the rim, one vertex longer than the segment count so the seam has a
    vertex on each side. Each rim vertex maps to where it lies in the square
    around the cap, seen from outside: the bottom is seen from below, so its
    v runs the other way.
    """
    var sign = Float32(1)
    if not top:
        sign = -1
    var y = half_height * sign
    var center_start = len(data) // 3
    for _ in range(radial_segments):  # pragma: no branch
        data.append(Float32(0))
        data.append(y)
        data.append(Float32(0))
        normals.append(Float32(0))
        normals.append(sign)
        normals.append(Float32(0))
        uvs.append(Float32(0.5))
        uvs.append(Float32(0.5))
    var rim_start = len(data) // 3
    for column in range(radial_segments + 1):  # pragma: no branch
        var theta = (
            theta_start
            + Float32(column) / Float32(radial_segments) * theta_length
        )
        var cos_theta = cos(theta)
        var sin_theta = sin(theta)
        data.append(radius * sin_theta)
        data.append(y)
        data.append(radius * cos_theta)
        normals.append(Float32(0))
        normals.append(sign)
        normals.append(Float32(0))
        uvs.append(cos_theta * 0.5 + 0.5)
        uvs.append(sin_theta * 0.5 * sign + 0.5)
    for column in range(radial_segments):  # pragma: no branch
        var center = center_start + column
        var rim = rim_start + column
        # Counter-clockwise seen from outside: from above for the top cap,
        # from below for the bottom, which reverses the two rim corners.
        if top:
            index.append(rim)
            index.append(rim + 1)
        else:
            index.append(rim + 1)
            index.append(rim)
        index.append(center)


def cylinder(
    radius_top: Length,
    radius_bottom: Length,
    height: Length,
    radial_segments: Int = 32,
    height_segments: Int = 1,
    open_ended: Bool = False,
    theta_start: Angle = Angle(0.0, RADIAN),
    theta_length: Angle = FULL_TURN,
) raises -> BufferGeometry:
    """Return a cylinder standing on the y axis, centered on the origin.

    Args:
        radius_top: The radius at +y. Zero makes a point there.
        radius_bottom: The radius at -y. Zero makes a point there.
        height: How tall, from the bottom to the top.
        radial_segments: How many cells around; at least three.
        height_segments: How many rows of cells down the side; at least
            one.
        open_ended: True to leave off the caps and make a pipe.
        theta_start: Where the sweep starts, at +z and running toward +x.
        theta_length: How far it sweeps. A full turn, the default, closes
            the side; less makes a section.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and an
        index buffer, wound counter-clockwise seen from outside. The side
        comes first, in rows from the top down, `radial_segments + 1`
        vertices to a row; then the top cap, then the bottom, each one
        center vertex per segment and a rim.

    Raises:
        Error: If either radius is negative or both are zero, the height is
            not positive, either segment count is too small, or the sweep
            is not positive or is more than a turn.
    """
    if radius_top.value < 0 or radius_bottom.value < 0:
        raise Error("A cylinder's radii cannot be negative")
    if radius_top.value == 0 and radius_bottom.value == 0:
        raise Error("A cylinder needs a radius at one end or the other")
    if height.value <= 0:
        raise Error("A cylinder needs a positive height")
    if radial_segments < 3:
        raise Error("A cylinder needs at least three segments around")
    if height_segments < 1:
        raise Error("A cylinder needs at least one segment down its side")
    check_sweep(theta_length)

    var top = radius_top.value
    var bottom = radius_bottom.value
    var tall = height.value
    var half_height = tall / 2
    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()

    # The side: rows from the top down, each one vertex longer than there
    # are cells around so the seam has a vertex on each side. A normal leans
    # by the side's slope, the same in every row, and is unit length by
    # construction. The segment counts were checked above, so every loop
    # runs.
    var slope = (bottom - top) / tall
    var lean = sqrt(1 + slope * slope)
    for row in range(height_segments + 1):  # pragma: no branch
        var v = Float32(row) / Float32(height_segments)
        var radius = v * (bottom - top) + top
        var y = half_height - v * tall
        for column in range(radial_segments + 1):  # pragma: no branch
            var u = Float32(column) / Float32(radial_segments)
            var theta = theta_start.value + u * theta_length.value
            var sin_theta = sin(theta)
            var cos_theta = cos(theta)
            data.append(radius * sin_theta)
            data.append(y)
            data.append(radius * cos_theta)
            normals.append(sin_theta / lean)
            normals.append(slope / lean)
            normals.append(cos_theta / lean)
            uvs.append(u)
            uvs.append(1 - v)

    var stride = radial_segments + 1
    var index = List[Int]()
    # Column by column and then down the rows, the order three.js walks the
    # side in, so the two index buffers match cell for cell. The order shows
    # only where it is the order things blend in: a translucent pipe's inner
    # and outer walls.
    for column in range(radial_segments):  # pragma: no branch
        for row in range(height_segments):  # pragma: no branch
            var a = column + stride * row
            var b = column + stride * (row + 1)
            var c = column + 1 + stride * (row + 1)
            var d = column + 1 + stride * row
            # Two triangles per cell, counter-clockwise from outside. A cell
            # against a point has two corners on the axis, so the half that
            # would have no area is left out, as three.js leaves it out.
            if top > 0 or row != 0:
                index.append(a)
                index.append(b)
                index.append(d)
            if bottom > 0 or row != height_segments - 1:
                index.append(b)
                index.append(c)
                index.append(d)

    if not open_ended:
        if top > 0:
            _append_cap(
                data,
                normals,
                uvs,
                index,
                top,
                half_height,
                radial_segments,
                theta_start.value,
                theta_length.value,
                True,
            )
        if bottom > 0:
            _append_cap(
                data,
                normals,
                uvs,
                index,
                bottom,
                half_height,
                radial_segments,
                theta_start.value,
                theta_length.value,
                False,
            )

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(index^)
    return geometry^


def cone(
    radius: Length,
    height: Length,
    radial_segments: Int = 32,
    height_segments: Int = 1,
    open_ended: Bool = False,
    theta_start: Angle = Angle(0.0, RADIAN),
    theta_length: Angle = FULL_TURN,
) raises -> BufferGeometry:
    """Return a cone standing on the y axis, its point at +y.

    three.js's `ConeGeometry`: a cylinder whose top radius is zero.

    Args:
        radius: The radius of the base, at -y.
        height: How tall, from the base to the point.
        radial_segments: How many cells around; at least three.
        height_segments: How many rows of cells down the side; at least
            one.
        open_ended: True to leave off the base.
        theta_start: Where the sweep starts, at +z and running toward +x.
        theta_length: How far it sweeps; a full turn by default.

    Returns:
        The geometry `cylinder` returns for a top radius of zero.

    Raises:
        Error: If the radius or the height is not positive, either segment
            count is too small, or the sweep is not positive or is more than
            a turn.
    """
    return cylinder(
        Length(0.0, METER),
        radius,
        height,
        radial_segments,
        height_segments,
        open_ended,
        theta_start,
        theta_length,
    )
