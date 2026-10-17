# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The attributes a generated surface writes onto a geometry.

A plane, a sphere, a tube and the other generated solids all finish the
same way. `position_normal_surface` writes positions and normals.
`textured_surface` also writes texture coordinates. `indexed_surface`
also writes the triangle index. `record_kind` names the solid and starts
its parameter record. They share the checks for a positive
radius, three segments, and positive or finite box extents. A count
below one is `require_at_least_one` in `math.curve_checks`.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    NORMAL,
    POSITION,
    UV,
    BufferGeometry,
    GeometryType,
)
from core.user_data import UserData
from core.ordinal import require_positive
from std.math import isfinite


def position_normal_surface(
    mut geometry: BufferGeometry,
    var positions: List[Float32],
    var normals: List[Float32],
) raises:
    """Attach positions and normals.

    Args:
        geometry: The geometry to fill.
        positions: Vertex positions, three numbers each.
        normals: Vertex normals, three numbers each.

    Returns:
        Nothing. The two attributes are set on `geometry`.

    Raises:
        Error: If either list does not divide evenly into vertices.
    """
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))


def textured_surface(
    mut geometry: BufferGeometry,
    var positions: List[Float32],
    var normals: List[Float32],
    var uvs: List[Float32],
) raises:
    """Attach positions, normals and texture coordinates.

    Args:
        geometry: The geometry to fill.
        positions: Vertex positions, three numbers each.
        normals: Vertex normals, three numbers each.
        uvs: Texture coordinates, two numbers each.

    Returns:
        Nothing. The three attributes are set on `geometry`.

    Raises:
        Error: If a list does not divide evenly into vertices.
    """
    position_normal_surface(geometry, positions^, normals^)
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))


def indexed_surface(
    mut geometry: BufferGeometry,
    var positions: List[Float32],
    var normals: List[Float32],
    var uvs: List[Float32],
    var index: List[Int],
) raises:
    """Attach positions, normals, texture coordinates and an index.

    Args:
        geometry: The geometry to fill.
        positions: Vertex positions, three numbers each.
        normals: Vertex normals, three numbers each.
        uvs: Texture coordinates, two numbers each.
        index: Vertex indices, three per triangle.

    Returns:
        Nothing. The attributes and the index are set on `geometry`.

    Raises:
        Error: If the index is not whole triangles, or an entry is negative.
    """
    textured_surface(geometry, positions^, normals^, uvs^)
    geometry.set_index(index^)


def record_kind(mut geometry: BufferGeometry, kind: GeometryType):
    """Name a generated solid and start its parameter record.

    Args:
        geometry: The solid.
        kind: The three.js class, such as `SPHERE_GEOMETRY`.

    Returns:
        Nothing. The kind and an empty parameter record are set.

    Raises:
        Error: Never.
    """
    geometry.kind = kind
    geometry.parameters = UserData()


def require_positive_radius(radius: Float32, name: String) raises:
    """Refuse a radius that is not positive.

    Args:
        radius: The radius.
        name: The solid, such as `sphere` or `tube`.

    Returns:
        Nothing. The call returns when the radius is positive.

    Raises:
        Error: If the radius is zero or negative.
    """
    require_positive(radius, "A " + name + " needs a positive radius")


def require_three_segments(count: Int, message: String) raises:
    """Refuse a loop of fewer than three segments.

    Args:
        count: How many segments the loop has.
        message: The error text for this solid.

    Returns:
        Nothing. The call returns when there are at least three segments.

    Raises:
        Error: If `count` is below three.
    """
    if count < 3:
        raise Error(message)


def require_positive_extents(
    width: Float32, height: Float32, depth: Float32, name: String
) raises:
    """Refuse a box whose width, height, or depth is not positive.

    Args:
        width: The width.
        height: The height.
        depth: The depth.
        name: The solid, such as `box` or `rounded box`.

    Returns:
        Nothing. The call returns when every extent is positive.

    Raises:
        Error: If any extent is zero or negative.
    """
    if width <= 0 or height <= 0 or depth <= 0:
        raise Error("A " + name + " needs positive extents")


def require_finite_extents(
    width: Float32, height: Float32, depth: Float32, name: String
) raises:
    """Refuse a box whose width, height, or depth is not finite.

    Args:
        width: The width.
        height: The height.
        depth: The depth.
        name: The solid, such as `box of lines` or `rounded box`.

    Returns:
        Nothing. The call returns when every extent is finite.

    Raises:
        Error: If any extent is not finite.
    """
    if not isfinite(width) or not isfinite(height) or not isfinite(depth):
        raise Error("A " + name + " needs finite extents")
