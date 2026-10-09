# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Display meshes for a bundle of diagrammatic hair shafts.

Leg hair and foot hair place their own centerlines. Both mesh each
shaft on its own and merge the results. Add another bundle by passing
its centerlines here.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, UV, BufferGeometry
from extensions.humanoid.skeleton.field import (
    DistanceField,
    empty_bounds,
    sd_segment,
)
from extensions.humanoid.skeleton.isosurface import mesh_field
from math.vector3 import Vector3


struct _HairShaftField(DistanceField, ImplicitlyCopyable):
    """One diagrammatic hair shaft for meshing."""

    var a: Vector3
    var b: Vector3
    var radius: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, a: Vector3, b: Vector3, radius: Float32):
        """Build one display shaft around its physical centerline."""
        self.a = a
        self.b = b
        self.radius = radius
        var box = empty_bounds()
        box.include_sphere(a, radius)
        box.include_sphere(b, radius)
        var padded = box.padded(Float32(0.002) + radius)
        self.low = padded.low
        self.high = padded.high

    def distance(self, point: Vector3) -> Float32:
        """Return distance to the display shaft, in meters."""
        return sd_segment(point, self.a, self.b, self.radius, self.radius)


def mesh_hair_shafts(
    starts: List[Vector3],
    ends: List[Vector3],
    radius: Float32,
    detail: Int,
    label: String,
) raises -> BufferGeometry:
    """Mesh each centerline at `radius` and merge the shafts in order.

    Args:
        starts: The root of each shaft.
        ends: The tip of each shaft, in the same order and count.
        radius: The display radius, in meters.
        detail: Cells along each shaft.
        label: The group's name for error text.

    Returns:
        One indexed geometry with position, normal and uv attributes.

    Raises:
        Error: If a shaft produces no surface.
    """
    var parts = List[BufferGeometry]()
    for index in range(len(starts)):  # pragma: no branch
        var field = _HairShaftField(starts[index], ends[index], radius)
        parts.append(mesh_field(field, field.low, field.high, detail, label))
    return _merge_shafts(parts)


def _merge_shafts(parts: List[BufferGeometry]) raises -> BufferGeometry:
    """Merge shaft geometries into one indexed geometry."""
    var positions = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    var indices = List[Int]()
    for index in range(len(parts)):  # pragma: no branch
        _append_geometry(positions, normals, uvs, indices, parts[index])
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
