# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A box, from three.js `src/geometries/BoxGeometry.js`.

The box is built from twenty-four vertices rather than eight, four per face.
Sharing the eight corners would be smaller, but a corner shared between three
faces can only carry one normal and one texture coordinate, so the faces could
never be shaded or textured separately. three.js splits them for that reason
and so does this, even though normals are not here yet — changing the vertex
layout later would silently invalidate every index buffer built against it.

Faces are emitted in a fixed order, two triangles each, so triangle index
divided by two identifies the face. `examples/cubes.mojo` uses exactly that to
shade the sides differently.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from math.vector3 import Vector3
from units.si import Length


def _push(mut data: List[Float32], x: Float32, y: Float32, z: Float32):
    """Append one vertex position to a flat attribute array."""
    data.append(x)
    data.append(y)
    data.append(z)


def _quad(mut index: List[Int], start: Int):
    """Append the two triangles of a face whose four vertices begin at `start`.

    Wound counter-clockwise seen from outside, which is what lets a reversed
    winding on screen identify a face pointing away.
    """
    index.append(start)
    index.append(start + 1)
    index.append(start + 2)
    index.append(start)
    index.append(start + 2)
    index.append(start + 3)


def box(width: Length, height: Length, depth: Length) raises -> BufferGeometry:
    """Return a box centred on the origin, in metres.

    Args:
        width: Extent along x.
        height: Extent along y.
        depth: Extent along z.

    Returns:
        A geometry with a `position` attribute and an index buffer, its faces
        ordered front, back, left, right, top, bottom.

    Raises:
        Error: If any extent is not positive.
    """
    if width.value <= 0 or height.value <= 0 or depth.value <= 0:
        raise Error("A box needs positive extents")

    var x = width.value / 2
    var y = height.value / 2
    var z = depth.value / 2

    var data = List[Float32]()
    # Front (+z)
    _push(data, -x, -y, z)
    _push(data, x, -y, z)
    _push(data, x, y, z)
    _push(data, -x, y, z)
    # Back (-z)
    _push(data, x, -y, -z)
    _push(data, -x, -y, -z)
    _push(data, -x, y, -z)
    _push(data, x, y, -z)
    # Left (-x)
    _push(data, -x, -y, -z)
    _push(data, -x, -y, z)
    _push(data, -x, y, z)
    _push(data, -x, y, -z)
    # Right (+x)
    _push(data, x, -y, z)
    _push(data, x, -y, -z)
    _push(data, x, y, -z)
    _push(data, x, y, z)
    # Top (+y)
    _push(data, -x, y, z)
    _push(data, x, y, z)
    _push(data, x, y, -z)
    _push(data, -x, y, -z)
    # Bottom (-y)
    _push(data, -x, -y, -z)
    _push(data, x, -y, -z)
    _push(data, x, -y, z)
    _push(data, -x, -y, z)

    var index = List[Int]()
    # A box always has six faces, so this cannot run zero times.
    for face in range(6):  # pragma: no branch
        _quad(index, face * 4)

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_index(index^)
    return geometry^


def cube(edge: Length) raises -> BufferGeometry:
    """Return a box with all three extents equal.

    Args:
        edge: The length of every edge.

    Returns:
        The geometry.

    Raises:
        Error: If `edge` is not positive.
    """
    return box(edge, edge, edge)
