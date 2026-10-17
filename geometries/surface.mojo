# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The attributes a generated surface writes onto a geometry.

A plane, a sphere, a tube and the other generated solids all finish the
same way: positions, normals, texture coordinates and a triangle index.
They also share the checks for a positive radius, three segments, and
positive box extents.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, UV, BufferGeometry


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
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(index^)


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
    if radius <= 0:
        raise Error("A " + name + " needs a positive radius")


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
