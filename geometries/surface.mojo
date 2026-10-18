# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The attributes a generated surface writes onto a geometry.

A plane, a sphere, a tube and the other generated solids all finish the
same way: positions, normals, texture coordinates and a triangle index.
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
