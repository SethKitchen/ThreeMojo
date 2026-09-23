# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A stick at every vertex along its normal or its tangent, from three.js
`src/helpers/VertexNormalsHelper.js` and
`examples/jsm/helpers/VertexTangentsHelper.js`.

Each vertex's position is carried into world space by the mesh node's
world matrix, and a stick of `size` leaves it along the vertex's normal or
tangent, also carried into world space. The `Line` belongs on a node at
the origin, as three.js's helper keeps the identity for its own matrix.

A normal is carried by the normal matrix, the inverse transpose of the
world matrix, so it stays perpendicular to the surface under a scale that
is not uniform. A tangent lies along the surface, so it is carried by the
world matrix itself, as three.js's `transformDirection` does. Both are
then made unit length and scaled to `size`. A normal or tangent of no
length gives a stick of no length.

A geometry here holds any attribute by name, so it can hold the four
floats per vertex of three.js's `tangent` attribute under `TANGENT`. The
fourth float, the handedness, is not read, as three.js does not read it.
Nothing here computes tangents: three.js's `computeTangents` is not
ported, so the attribute comes from a loader or from the caller.
"""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from helpers.segments import Segments
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from units.si import Length, METER

# The name three.js gives the tangent attribute: four floats a vertex,
# the tangent and then its handedness.
comptime TANGENT = "tangent"
# three.js's defaults: one unit long, red normals and cyan tangents.
comptime DEFAULT_NORMALS_SIZE = Length(1.0, METER)
comptime DEFAULT_NORMALS_COLOR = Color(0xFF, 0x00, 0x00)
comptime DEFAULT_TANGENTS_COLOR = Color(0x00, 0xFF, 0xFF)


def _sticks(
    geometry: BufferGeometry,
    name: String,
    carry: Matrix4,
    world: Matrix4,
    size: Length,
    color: Color,
) raises -> BufferGeometry:
    """Return one stick per vertex along the attribute `name`, carried by
    `carry` and made `size` long."""
    var length = size.to(METER)
    if length <= 0:
        raise Error("A vertex helper needs a positive size")
    ref positions = geometry.attribute_view(String(POSITION))
    ref directions = geometry.attribute_view(name)
    if directions.count() != positions.count():
        raise Error("A vertex helper needs one " + name + " per vertex")
    var paint = FloatColor(srgb=color)
    var segments = Segments()
    for vertex in range(positions.count()):
        var start = world.transform_point(positions.vector3(vertex))
        var along = carry.transform_direction(directions.vector3(vertex))
        along.normalize()
        segments.add(start, start + along * length, paint)
    return segments.geometry()


def vertex_normals_helper(
    geometry: BufferGeometry,
    world: Matrix4,
    size: Length = DEFAULT_NORMALS_SIZE,
    color: Color = DEFAULT_NORMALS_COLOR,
) raises -> BufferGeometry:
    """Return a stick at every vertex along its normal, for a `Line` in
    `SEGMENTS` mode on a node at the origin.

    Args:
        geometry: The geometry whose normals to show. It must have a
            `normal` attribute with one normal per position.
        world: The world matrix of the node the geometry is drawn on,
            from `Scene.world_matrix`.
        size: How long each stick is. Must be positive.
        color: The color of every stick, as authored in sRGB.

    Returns:
        Two points per vertex, the vertex and the end of its stick, in
        world space, with a `color` attribute in linear light.

    Raises:
        Error: If `size` is not positive; the geometry has no positions,
            no normals, or not one normal per position; or `world` has no
            normal matrix, as a scale of zero has none.
    """
    return _sticks(
        geometry, String(NORMAL), world.normal_matrix(), world, size, color
    )


def vertex_tangents_helper(
    geometry: BufferGeometry,
    world: Matrix4,
    size: Length = DEFAULT_NORMALS_SIZE,
    color: Color = DEFAULT_TANGENTS_COLOR,
) raises -> BufferGeometry:
    """Return a stick at every vertex along its tangent, for a `Line` in
    `SEGMENTS` mode on a node at the origin.

    Args:
        geometry: The geometry whose tangents to show. It must have a
            `tangent` attribute, `TANGENT`, of at least three floats a
            vertex and one tangent per position.
        world: The world matrix of the node the geometry is drawn on.
        size: How long each stick is. Must be positive.
        color: The color of every stick, as authored in sRGB.

    Returns:
        Two points per vertex, the vertex and the end of its stick, in
        world space, with a `color` attribute in linear light.

    Raises:
        Error: If `size` is not positive; the geometry has no positions,
            no tangents, not one tangent per position, or fewer than three
            floats a tangent.
    """
    return _sticks(geometry, String(TANGENT), world, world, size, color)
