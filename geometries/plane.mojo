# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A flat rectangle, from three.js `src/geometries/PlaneGeometry.js`.

The most used geometry after the box, and the one three examples had each
built by hand with their own corner order, winding and texture coordinates.
A floor, a wall, a pane of glass and a sprite are all this, positioned.

It lies in the xy plane facing +z and is centered on the origin, as three.js's
is. To make a floor, rotate its node a quarter turn about x so +z becomes +y.
Subdividing it into a grid is what makes a large ground plane light well and
clip cleanly: one quad to the horizon spans a lot of perspective and a lot of
lighting change, and the corners are the only places either is evaluated
exactly.

Texture coordinates run once across the whole rectangle, (0, 0) at the bottom
left and (1, 1) at the top right, which is what a texture expects and what
`box` does per face. A floor that wants its image tiled every meter scales
these itself, as `examples/floor.mojo` does; three.js would reach for
`texture.repeat`, which is not ported yet.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    NORMAL,
    PLANE_GEOMETRY,
    POSITION,
    UV,
)
from core.user_data import UserData
from units.si import Length, METER


def plane(
    width: Length,
    height: Length,
    width_segments: Int = 1,
    height_segments: Int = 1,
) raises -> BufferGeometry:
    """Return a rectangle in the xy plane, facing +z, centered on the origin.

    Args:
        width: Extent along x.
        height: Extent along y.
        width_segments: How many columns of quads across; at least one.
        height_segments: How many rows of quads down; at least one.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and an
        index buffer, wound counter-clockwise seen from +z.

    Raises:
        Error: If either extent is not positive, or either segment count is
            less than one.
    """
    if width.value <= 0 or height.value <= 0:
        raise Error("A plane needs positive extents")
    if width_segments < 1 or height_segments < 1:
        raise Error("A plane needs at least one segment each way")

    var half_width = width.value / 2
    var half_height = height.value / 2
    var columns = width_segments + 1
    var rows = height_segments + 1

    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    # Rows run from the top down, as three.js emits them, so the first
    # vertex is the top-left corner and its v is one.
    for row in range(rows):  # pragma: no branch
        var y = half_height - Float32(row) * height.value / Float32(
            height_segments
        )
        for column in range(columns):  # pragma: no branch
            var x = (
                Float32(column) * width.value / Float32(width_segments)
                - half_width
            )
            data.append(x)
            data.append(y)
            data.append(Float32(0))
            normals.append(Float32(0))
            normals.append(Float32(0))
            normals.append(Float32(1))
            uvs.append(Float32(column) / Float32(width_segments))
            uvs.append(1 - Float32(row) / Float32(height_segments))

    var index = List[Int]()
    for row in range(height_segments):  # pragma: no branch
        for column in range(width_segments):  # pragma: no branch
            var a = column + columns * row
            var b = column + columns * (row + 1)
            var c = column + 1 + columns * (row + 1)
            var d = column + 1 + columns * row
            # Two triangles per quad, each counter-clockwise from the front:
            # top-left, bottom-left, top-right, then bottom-left,
            # bottom-right, top-right.
            index.append(a)
            index.append(b)
            index.append(d)
            index.append(b)
            index.append(c)
            index.append(d)

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(index^)
    geometry.kind = PLANE_GEOMETRY
    geometry.parameters = UserData()
    geometry.parameters.set_number("width", Float64(width.to(METER)))
    geometry.parameters.set_number("height", Float64(height.to(METER)))
    geometry.parameters.set_number("widthSegments", Float64(width_segments))
    geometry.parameters.set_number("heightSegments", Float64(height_segments))
    return geometry^
