# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The attributes a generated surface writes onto a geometry.

A plane, a sphere, a tube and the other generated solids all finish the
same way. `position_normal_surface` writes positions and normals.
`textured_surface` also writes texture coordinates. `indexed_surface`
also writes the triangle index. `record_kind` names the solid and starts
its parameter record. `record_sweep` writes the theta sweep.
`record_phi` writes the phi sweep. `record_tube` writes a tube's two
radii. `record_width_height` writes a rectangle's width and height.
`record_grid_segments` writes its two segment counts.
`record_shaft_segments` writes a shaft's two segment counts. They share the
checks for a positive radius, three segments, and positive or finite box
extents. A count below one is `require_at_least_one` in
`math.curve_checks`.

## Input validation difference

Shape dimensions must be finite before vertices are generated. NaN and
either infinity raise an error. This differs from the unchecked three.js
r186 input path. Finite supported inputs keep their existing behavior.
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
from math.finite import require_finite
from std.math import isfinite
from units.si import Angle, Length


def position_normal_surface(
    mut geometry: BufferGeometry,
    var positions: List[Float32],
    var normals: List[Float32],
) raises:
    """Attach positions and normals.

    Nothing. The two attributes are set on `geometry`.

    Args:
        geometry: The geometry to fill.
        positions: Vertex positions, three numbers each.
        normals: Vertex normals, three numbers each.

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

    Nothing. The three attributes are set on `geometry`.

    Args:
        geometry: The geometry to fill.
        positions: Vertex positions, three numbers each.
        normals: Vertex normals, three numbers each.
        uvs: Texture coordinates, two numbers each.

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

    Nothing. The attributes and the index are set on `geometry`.

    Args:
        geometry: The geometry to fill.
        positions: Vertex positions, three numbers each.
        normals: Vertex normals, three numbers each.
        uvs: Texture coordinates, two numbers each.
        index: Vertex indices, three per triangle.

    Raises:
        Error: If the index is not whole triangles, or an entry is negative.
    """
    textured_surface(geometry, positions^, normals^, uvs^)
    geometry.set_index(index^)


def record_kind(mut geometry: BufferGeometry, kind: GeometryType):
    """Name a generated solid and start its parameter record.

    Nothing. The kind and an empty parameter record are set.

    Error: Never.

    Args:
        geometry: The solid.
        kind: The three.js class, such as `SPHERE_GEOMETRY`.

    """
    geometry.kind = kind
    geometry.parameters = UserData()


def record_sweep(
    mut geometry: BufferGeometry, theta_start: Angle, theta_length: Angle
) raises:
    """Record where a theta sweep starts and how far it runs.

    Nothing. `thetaStart` and `thetaLength` hold the angles in radians.

    Args:
        geometry: The solid, after `record_kind`.
        theta_start: Where the sweep starts.
        theta_length: How far it sweeps.

    Raises:
        Error: If either angle in radians is not finite.
    """
    geometry.parameters.set_radians("thetaStart", theta_start)
    geometry.parameters.set_radians("thetaLength", theta_length)


def record_phi(
    mut geometry: BufferGeometry, phi_start: Angle, phi_length: Angle
) raises:
    """Record where a phi sweep starts and how far it runs.

    Nothing. `phiStart` and `phiLength` hold the angles in radians.

    Args:
        geometry: The solid, after `record_kind`.
        phi_start: Where the sweep starts.
        phi_length: How far it sweeps.

    Raises:
        Error: If either angle in radians is not finite.
    """
    geometry.parameters.set_radians("phiStart", phi_start)
    geometry.parameters.set_radians("phiLength", phi_length)


def record_tube(
    mut geometry: BufferGeometry, radius: Length, tube: Length
) raises:
    """Record a tube's path radius and its tube radius.

    Nothing. `radius` and `tube` hold the lengths in meters.

    Args:
        geometry: The solid, after `record_kind`.
        radius: The path radius.
        tube: The tube radius.

    Raises:
        Error: If either length in meters is not finite.
    """
    geometry.parameters.set_meters("radius", radius)
    geometry.parameters.set_meters("tube", tube)


def record_width_height(
    mut geometry: BufferGeometry, width: Length, height: Length
) raises:
    """Record a rectangle's width and height.

    Nothing. `width` and `height` hold the lengths in meters.

    Args:
        geometry: The solid, after `record_kind`.
        width: The width.
        height: The height.

    Raises:
        Error: If either length in meters is not finite.
    """
    geometry.parameters.set_meters("width", width)
    geometry.parameters.set_meters("height", height)


def record_grid_segments(
    mut geometry: BufferGeometry, width_segments: Int, height_segments: Int
) raises:
    """Record how many cells a grid has across and down.

    Nothing. `widthSegments` and `heightSegments` are set.

    Args:
        geometry: The solid, after `record_kind`.
        width_segments: How many cells across.
        height_segments: How many cells down.

    Raises:
        Error: If either count is not finite as a number.
    """
    geometry.parameters.set_number("widthSegments", Float64(width_segments))
    geometry.parameters.set_number("heightSegments", Float64(height_segments))


def record_shaft_segments(
    mut geometry: BufferGeometry,
    radial_segments: Int,
    height_segments: Int,
) raises:
    """Record how many cells a shaft has around and down its side.

    Nothing. `radialSegments` and `heightSegments` are set.

    Args:
        geometry: The solid, after `record_kind`.
        radial_segments: How many cells around.
        height_segments: How many cells down the side.

    Raises:
        Error: If either count is not finite as a number.
    """
    geometry.parameters.set_number("radialSegments", Float64(radial_segments))
    geometry.parameters.set_number("heightSegments", Float64(height_segments))


def require_positive_radius(radius: Float32, name: String) raises:
    """Refuse a radius that is not positive.

    Nothing. The call returns when the radius is positive.

    Args:
        radius: The radius.
        name: The solid, such as `sphere` or `tube`.

    Raises:
        Error: If the radius is not finite, or is zero or negative.
    """
    require_finite(Float64(radius), "A " + name + " needs a finite radius")
    # `not (radius > 0)`, not `radius <= 0`: NaN compares false both ways,
    # so the <= form would let it through.
    if not (radius > 0):
        raise Error("A " + name + " needs a positive radius")


def require_three_segments(count: Int, message: String) raises:
    """Refuse a loop of fewer than three segments.

    Nothing. The call returns when there are at least three segments.

    Args:
        count: How many segments the loop has.
        message: The error text for this solid.

    Raises:
        Error: If `count` is below three.
    """
    if count < 3:
        raise Error(message)


def require_positive_extents(
    width: Float32, height: Float32, depth: Float32, name: String
) raises:
    """Refuse a box whose width, height, or depth is not positive.

    Nothing. The call returns when every extent is positive.

    Args:
        width: The width.
        height: The height.
        depth: The depth.
        name: The solid, such as `box` or `rounded box`.

    Raises:
        Error: If any extent is zero or negative.
    """
    if width <= 0 or height <= 0 or depth <= 0:
        raise Error("A " + name + " needs positive extents")


def require_finite_extents(
    width: Float32, height: Float32, depth: Float32, name: String
) raises:
    """Refuse a box whose width, height, or depth is not finite.

    Nothing. The call returns when every extent is finite.

    Args:
        width: The width.
        height: The height.
        depth: The depth.
        name: The solid, such as `box of lines` or `rounded box`.

    Raises:
        Error: If any extent is not finite.
    """
    if not isfinite(width) or not isfinite(height) or not isfinite(depth):
        raise Error("A " + name + " needs finite extents")
