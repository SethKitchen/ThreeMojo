# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A box, from three.js `src/geometries/BoxGeometry.js`.

The box is built from twenty-four vertices rather than eight, four per face.
Sharing the eight corners would be smaller, but a corner shared between three
faces can only carry one normal, so the faces could never be shaded
separately. That is no longer hypothetical: each of a face's four vertices
carries that face's outward normal, which is what keeps a cube's edges
crisp when the renderer interpolates normals across a triangle.

Faces are emitted in a fixed order, two triangles each, so triangle index
divided by two identifies the face. `examples/cubes.mojo` uses exactly that to
shade the sides differently.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from math.vector3 import Vector3
from units.si import Length


def _push(mut data: List[Float32], x: Float32, y: Float32, z: Float32):
    """Append one vertex position to a flat attribute array."""
    data.append(x)
    data.append(y)
    data.append(z)


def _face(
    mut data: List[Float32],
    mut normals: List[Float32],
    mut uvs: List[Float32],
    a: Vector3,
    b: Vector3,
    c: Vector3,
    d: Vector3,
    nx: Float32,
    ny: Float32,
    nz: Float32,
):
    """Append one face's four corners, with its normal and texture coordinates.

    The corners arrive counter-clockwise from the face's bottom-left seen from
    outside, so the texture covers each face once from (0,0) at that corner to
    (1,1) diagonally opposite. Every face gets the whole image, which is what
    three.js's BoxGeometry does too.
    """
    var u = [Float32(0), Float32(1), Float32(1), Float32(0)]
    var v = [Float32(0), Float32(0), Float32(1), Float32(1)]
    var corners = [a, b, c, d]
    for corner in range(4):  # pragma: no branch
        _push(data, corners[corner].x, corners[corner].y, corners[corner].z)
        _push(normals, nx, ny, nz)
        uvs.append(u[corner])
        uvs.append(v[corner])


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
    """Return a box centered on the origin, in meters.

    Args:
        width: Extent along x.
        height: Extent along y.
        depth: Extent along z.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and an
        index buffer, its faces ordered front, back, left, right, top,
        bottom.

    Raises:
        Error: If any extent is not positive.
    """
    if width.value <= 0 or height.value <= 0 or depth.value <= 0:
        raise Error("A box needs positive extents")

    var x = width.value / 2
    var y = height.value / 2
    var z = depth.value / 2

    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()

    _face(
        data,
        normals,
        uvs,
        Vector3(-x, -y, z),
        Vector3(x, -y, z),
        Vector3(x, y, z),
        Vector3(-x, y, z),
        0,
        0,
        1,
    )  # front
    _face(
        data,
        normals,
        uvs,
        Vector3(x, -y, -z),
        Vector3(-x, -y, -z),
        Vector3(-x, y, -z),
        Vector3(x, y, -z),
        0,
        0,
        -1,
    )  # back
    _face(
        data,
        normals,
        uvs,
        Vector3(-x, -y, -z),
        Vector3(-x, -y, z),
        Vector3(-x, y, z),
        Vector3(-x, y, -z),
        -1,
        0,
        0,
    )  # left
    _face(
        data,
        normals,
        uvs,
        Vector3(x, -y, z),
        Vector3(x, -y, -z),
        Vector3(x, y, -z),
        Vector3(x, y, z),
        1,
        0,
        0,
    )  # right
    _face(
        data,
        normals,
        uvs,
        Vector3(-x, y, z),
        Vector3(x, y, z),
        Vector3(x, y, -z),
        Vector3(-x, y, -z),
        0,
        1,
        0,
    )  # top
    _face(
        data,
        normals,
        uvs,
        Vector3(-x, -y, -z),
        Vector3(x, -y, -z),
        Vector3(x, -y, z),
        Vector3(-x, -y, z),
        0,
        -1,
        0,
    )  # bottom

    var index = List[Int]()
    # A box always has six faces, so this cannot run zero times.
    for face in range(6):  # pragma: no branch
        _quad(index, face * 4)

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
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
