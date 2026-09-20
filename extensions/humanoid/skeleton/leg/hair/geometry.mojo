# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Hair meshes from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var shafts = hair_mesh(person, THIGH_HAIR)

The solids live in `dimensions`. This file extracts the zero set with
marching tetrahedra. Connectivity comes from the field.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, UV, BufferGeometry
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import (
    DistanceField,
    empty_bounds,
    field_gradient,
    sd_segment,
)
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.skeleton.leg.hair.dimensions import (
    HairField,
    HairPart,
    hair_part_label,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    MuscleDimensions,
    muscle_dimensions,
)
from math.vector3 import Vector3


def hair_mesh(
    spec: HumanoidSpec,
    part: HairPart,
    side: BodySide = RIGHT,
    detail: Int = 16,
) raises -> BufferGeometry:
    """Return one named hair group sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which solid to mesh.
        side: `RIGHT` or `LEFT`. A right leg is the default.
        detail: Cells along the solid, eight through sixty-four,
            sixteen by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec`, `side` or `part` is refused, if `detail` is
            out of range, or if the field produces no surface.
    """
    return hair_from_dimensions(muscle_dimensions(spec, side), part, detail)


def hair_from_dimensions(
    dimensions: MuscleDimensions, part: HairPart, detail: Int = 16
) raises -> BufferGeometry:
    """Return one hair mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `muscle_dimensions`.
        part: Which solid to mesh.
        detail: Cells along the solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `detail` is out of range, or if the field
            produces no surface.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A hair part must be a named hair group")
    var label = hair_part_label(part)
    check_detail(detail, label)
    var field = HairField(dimensions, part)
    var radius = 0.0015 * dimensions.stature.value
    return _merge_six(
        _shaft_mesh(field.a0, field.b0, radius, detail, label),
        _shaft_mesh(field.a1, field.b1, radius, detail, label),
        _shaft_mesh(field.a2, field.b2, radius, detail, label),
        _shaft_mesh(field.a3, field.b3, radius, detail, label),
        _shaft_mesh(field.a4, field.b4, radius, detail, label),
        _shaft_mesh(field.a5, field.b5, radius, detail, label),
    )


struct _HairShaftField(DistanceField, ImplicitlyCopyable):
    """One diagrammatic hair shaft for meshing."""

    var a: Vector3
    var b: Vector3
    var radius: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, a: Vector3, b: Vector3, radius: Float32):
        """Build one display shaft around its physical centerline."""
        self.a = a
        self.b = b
        self.radius = radius
        self.epsilon = Float32(0.25) * radius
        var box = empty_bounds()
        box.include_sphere(a, radius)
        box.include_sphere(b, radius)
        var padded = box.padded(Float32(0.002) + radius)
        self.low = padded.low
        self.high = padded.high

    def distance(self, point: Vector3) -> Float32:
        """Return distance to the display shaft, in meters."""
        return sd_segment(point, self.a, self.b, self.radius, self.radius)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal at `point`."""
        return field_gradient(self, point, self.epsilon)


def _shaft_mesh(
    a: Vector3,
    b: Vector3,
    radius: Float32,
    detail: Int,
    label: String,
) raises -> BufferGeometry:
    """Return one display shaft mesh."""
    var field = _HairShaftField(a, b, radius)
    return mesh_field(field, field.low, field.high, detail, label)


def _merge_six(
    var g0: BufferGeometry,
    var g1: BufferGeometry,
    var g2: BufferGeometry,
    var g3: BufferGeometry,
    var g4: BufferGeometry,
    var g5: BufferGeometry,
) raises -> BufferGeometry:
    """Merge six shaft geometries into one indexed geometry."""
    var positions = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    var indices = List[Int]()
    _append_geometry(positions, normals, uvs, indices, g0)
    _append_geometry(positions, normals, uvs, indices, g1)
    _append_geometry(positions, normals, uvs, indices, g2)
    _append_geometry(positions, normals, uvs, indices, g3)
    _append_geometry(positions, normals, uvs, indices, g4)
    _append_geometry(positions, normals, uvs, indices, g5)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(indices^)
    return geometry^


def _append_geometry(
    mut positions: List[Float32],
    mut normals: List[Float32],
    mut uvs: List[Float32],
    mut indices: List[Int],
    geometry: BufferGeometry,
) raises:
    """Append one indexed geometry to flat merged buffers."""
    var base = len(positions) // 3
    ref p = geometry.attribute_view(String(POSITION))
    ref n = geometry.attribute_view(String(NORMAL))
    ref uv = geometry.attribute_view(String(UV))
    for index in range(len(p.data)):  # pragma: no branch
        positions.append(p.data[index])
    for index in range(len(n.data)):  # pragma: no branch
        normals.append(n.data[index])
    for index in range(len(uv.data)):  # pragma: no branch
        uvs.append(uv.data[index])
    for index in range(len(geometry.index)):  # pragma: no branch
        indices.append(base + geometry.index[index])
