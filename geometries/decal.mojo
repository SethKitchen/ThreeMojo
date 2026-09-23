# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A decal: the part of a mesh inside a box, with the box's own texture
coordinates, from three.js `examples/jsm/geometries/DecalGeometry.js`.

A decal is a sticker. A box, the projector, stands at a position and an
orientation with a width, a height and a depth. Every triangle of the mesh
is moved into the projector's frame and cut against the six faces of the
box. What is left is the part of the surface the sticker covers. Its
texture coordinates are where each vertex lies across the box's width and
height, so the image is projected straight down the box's z axis.

The cut is three.js's. A triangle with one corner outside a face becomes
two triangles, and one with two corners outside becomes one. A new corner
is placed along an edge where the edge crosses the face, and its normal is
the same blend of the two ends' normals. three.js does not make that blend
unit length again, and nor does this.

The result is in world space, because three.js's is. Put it on a mesh at
the origin with no rotation or scale, and draw it a little in front of the
surface it covers, with a polygon offset, or it fights that surface for
depth.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from math.euler import Euler
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from units.si import Length


@fieldwise_init
struct _DecalVertex(ImplicitlyCopyable):
    """One corner on its way through the cut, three.js's `DecalVertex`.

    The normal is zero and unread when the mesh has none.
    """

    var position: Vector3
    var normal: Vector3


def _clip(
    v0: _DecalVertex, v1: _DecalVertex, plane: Vector3, s: Float32
) -> _DecalVertex:
    """Return the point where the edge from `v0` to `v1` crosses a face of
    the box, with the normal blended the same way."""
    var d0 = v0.position.dot(plane) - s
    var d1 = v1.position.dot(plane) - s
    var s0 = d0 / (d0 - d1)
    var position = Vector3(
        v0.position.x + s0 * (v1.position.x - v0.position.x),
        v0.position.y + s0 * (v1.position.y - v0.position.y),
        v0.position.z + s0 * (v1.position.z - v0.position.z),
    )
    var normal = Vector3(
        v0.normal.x + s0 * (v1.normal.x - v0.normal.x),
        v0.normal.y + s0 * (v1.normal.y - v0.normal.y),
        v0.normal.z + s0 * (v1.normal.z - v0.normal.z),
    )
    return _DecalVertex(position, normal)


def _clip_geometry(
    vertices: List[_DecalVertex], plane: Vector3, size: Vector3
) -> List[_DecalVertex]:
    """Return the triangles of `vertices`, three a triangle, cut against one
    face of the box, three.js's `clipGeometry`."""
    var out = List[_DecalVertex]()
    var s = 0.5 * abs(size.dot(plane))
    var i = 0
    while i < len(vertices):
        var a = vertices[i]
        var b = vertices[i + 1]
        var c = vertices[i + 2]
        var v1_out = a.position.dot(plane) - s > 0
        var v2_out = b.position.dot(plane) - s > 0
        var v3_out = c.position.dot(plane) - s > 0
        var total = Int(v1_out) + Int(v2_out) + Int(v3_out)
        if total == 0:
            # The whole triangle is inside.
            out.append(a)
            out.append(b)
            out.append(c)
        elif total == 1:
            # One corner is outside: the four-sided rest is two triangles.
            if v2_out:
                var n3 = _clip(b, a, plane, s)
                var n4 = _clip(b, c, plane, s)
                out.append(n3)
                out.append(c)
                out.append(a)
                out.append(c)
                out.append(n3)
                out.append(n4)
            else:
                var n1 = a if v3_out else b
                var n2 = b if v3_out else c
                var away = c if v3_out else a
                var n3 = _clip(away, n1, plane, s)
                var n4 = _clip(away, n2, plane, s)
                out.append(n1)
                out.append(n2)
                out.append(n3)
                out.append(n4)
                out.append(n3)
                out.append(n2)
        elif total == 2:
            # Two corners are outside: the rest is one triangle, started
            # from the corner inside.
            var first = c
            var second = a
            var third = b
            if not v1_out:
                first = a
                second = b
                third = c
            elif not v2_out:
                first = b
                second = c
                third = a
            out.append(first)
            out.append(_clip(first, second, plane, s))
            out.append(_clip(first, third, plane, s))
        # Three corners outside: the triangle is dropped.
        i += 3
    return out^


def decal(
    geometry: BufferGeometry,
    matrix_world: Matrix4,
    position: Vector3,
    orientation: Euler,
    width: Length,
    height: Length,
    depth: Length,
) raises -> BufferGeometry:
    """Return the part of a mesh inside a projector box, three.js's
    `DecalGeometry`.

    Args:
        geometry: The mesh's geometry. It needs `position`; `normal` is
            carried through when it is there.
        matrix_world: The mesh's world matrix, from `scene.world_matrix`.
        position: Where the center of the box stands, in meters, in world
            space.
        orientation: How the box is turned. It projects along its own z.
        width: The box's extent along its x, which `u` spans.
        height: The box's extent along its y, which `v` spans.
        depth: The box's extent along its z, the direction it projects.

    Returns:
        A geometry in world space with `position`, `uv` and, when the mesh
        has normals and anything is inside the box, `normal`. It has no
        index: each triangle owns its corners.

    Raises:
        Error: If an extent is not positive, the geometry has no positions,
            an index entry points past the last vertex, the orientation's
            order is not valid, or the mesh has normals and its world matrix
            flattens a dimension.
    """
    if width.value <= 0 or height.value <= 0 or depth.value <= 0:
        raise Error("A decal needs a box with positive extents")
    var size = Vector3(width.value, height.value, depth.value)

    var projector = orientation.to_matrix()
    projector.elements[12] = position.x
    projector.elements[13] = position.y
    projector.elements[14] = position.z
    var projector_inverse = projector
    projector_inverse.invert()

    var has_normals = geometry.has_attribute(String(NORMAL))
    var normal_matrix = Matrix4()
    if has_normals:
        normal_matrix = matrix_world.normal_matrix()

    ref positions = geometry.attribute_view(String(POSITION))
    var vertices = List[_DecalVertex]()
    for triangle in range(geometry.triangle_count()):
        for corner in range(3):  # pragma: no branch
            var vertex = geometry.corner_index(triangle, corner)
            var point = projector_inverse.transform_point(
                matrix_world.transform_point(positions.vector3(vertex))
            )
            var normal = Vector3(0, 0, 0)
            if has_normals:
                normal = normal_matrix.transform_direction(
                    geometry.attribute_view(String(NORMAL)).vector3(vertex)
                )
                normal.normalize()
            vertices.append(_DecalVertex(point, normal))

    vertices = _clip_geometry(vertices, Vector3(1, 0, 0), size)
    vertices = _clip_geometry(vertices, Vector3(-1, 0, 0), size)
    vertices = _clip_geometry(vertices, Vector3(0, 1, 0), size)
    vertices = _clip_geometry(vertices, Vector3(0, -1, 0), size)
    vertices = _clip_geometry(vertices, Vector3(0, 0, 1), size)
    vertices = _clip_geometry(vertices, Vector3(0, 0, -1), size)

    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    for vertex in vertices:
        uvs.append(0.5 + vertex.position.x / size.x)
        uvs.append(0.5 + vertex.position.y / size.y)
        var world = projector.transform_point(vertex.position)
        data.append(world.x)
        data.append(world.y)
        data.append(world.z)
        if has_normals:
            normals.append(vertex.normal.x)
            normals.append(vertex.normal.y)
            normals.append(vertex.normal.z)

    var result = BufferGeometry()
    result.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    result.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    if len(normals) > 0:
        result.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    return result^
