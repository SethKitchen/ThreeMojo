# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The eyeballs: where they sit, how big they are, and their mesh.

Each eyeball is a sphere about 24 mm across on the six-foot template,
with the cornea standing a little proud of it at the front. It sits in
the orbit behind the lids, and the skin's lids open over it in an
almond-shaped slit. The genome's `EYE_SIZE` scales it; the eye genes
that move the orbit move it with the orbit.

The mesh's texture coordinates run `u` around the eye's axis and `v`
from the front pole, at 0, to the back, at 1, which is how
`iris_albedo` lays out the pupil, the iris and the sclera.

    var dims = head_muscle_dimensions(person)
    var eye = eyeball_mesh(dims, RIGHT, 24)
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.skeleton.head.frame import (
    HeadDimensions,
    HeadMuscleDimensions,
)
from extensions.humanoid.skeleton.morph import EYE_X, EYE_Y, EYE_Z
from math.vector3 import Vector3
from std.math import cos, max, pi, sin, sqrt

# The eyeball's radius on the template, in centimeters.
comptime EYEBALL_RADIUS = Float32(1.2)
# How far the cornea stands proud of the sphere, as a share of the
# radius, and the half-angle of the cap it covers.
comptime CORNEA_RISE = Float32(0.07)
comptime CORNEA_COS = Float32(0.86)
comptime MIN_EYE_DETAIL = 8
comptime MAX_EYE_DETAIL = 64


def _side_sign(side: BodySide) raises -> Float32:
    """Return one for the right eye and minus one for the left."""
    if not side.is_valid():
        raise Error("An eye's side must be RIGHT or LEFT")
    if side == LEFT:
        return -1
    return 1


def eye_center(dimensions: HeadDimensions, side: BodySide) raises -> Vector3:
    """Return the center of one eyeball in the pelvis frame.

    Args:
        dimensions: Landmarks from `head_dimensions`.
        side: `RIGHT` or `LEFT`.

    Returns:
        The center, in meters.

    Raises:
        Error: If `side` is not valid.
    """
    var sign = _side_sign(side)
    return dimensions.at(sign * EYE_X, EYE_Y, EYE_Z)


def eye_radius(dimensions: HeadDimensions) -> Float32:
    """Return the radius of each eyeball, in meters.

    Args:
        dimensions: Landmarks from `head_dimensions`.

    Returns:
        The template's 12 mm, scaled by stature and `EYE_SIZE`.
    """
    return dimensions.cm(EYEBALL_RADIUS) * dimensions.frame.morph.eye_scale()


def _radius_at(radius: Float32, cosine: Float32) -> Float32:
    """Return the eye's radius at an angle from its front pole."""
    if cosine <= CORNEA_COS:
        return radius
    var t = (cosine - CORNEA_COS) / (1 - CORNEA_COS)
    return radius * (1 + CORNEA_RISE * sqrt(t))


def eyeball_mesh(
    dimensions: HeadMuscleDimensions, side: BodySide, detail: Int = 24
) raises -> BufferGeometry:
    """Return one eyeball as a mesh, looking straight ahead.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        side: `RIGHT` or `LEFT`.
        detail: Rings from the front pole to the back, eight through
            sixty-four. Twice as many segments run around.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `side` is
            not valid, or if `detail` is out of range.
    """
    dimensions.validate()
    if detail < MIN_EYE_DETAIL:
        raise Error("An eye needs a detail of at least eight")
    if detail > MAX_EYE_DETAIL:
        raise Error("An eye's detail cannot exceed sixty-four")
    var center = eye_center(dimensions.head, side)
    var radius = eye_radius(dimensions.head)
    var rings = detail
    var around = detail * 2
    var positions = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    for ring in range(rings + 1):  # pragma: no branch
        var v = Float32(ring) / Float32(rings)
        var polar = v * pi
        var cz = cos(polar)
        var sz = sin(polar)
        var r = _radius_at(radius, cz)
        for step in range(around + 1):  # pragma: no branch
            var u = Float32(step) / Float32(around)
            var angle = u * 2 * pi
            var direction = Vector3(sz * cos(angle), sz * sin(angle), cz)
            positions.append(center.x + direction.x * r)
            positions.append(center.y + direction.y * r)
            positions.append(center.z + direction.z * r)
            normals.append(direction.x)
            normals.append(direction.y)
            normals.append(direction.z)
            uvs.append(u)
            uvs.append(v)
    var indices = List[Int]()
    var row = around + 1
    for ring in range(rings):  # pragma: no branch
        for step in range(around):  # pragma: no branch
            var a = ring * row + step
            var b = a + row
            # Counter-clockwise seen from outside.
            if ring > 0:
                indices.append(a)
                indices.append(b)
                indices.append(a + 1)
            if ring < rings - 1:
                indices.append(a + 1)
                indices.append(b)
                indices.append(b + 1)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(indices^)
    return geometry^
