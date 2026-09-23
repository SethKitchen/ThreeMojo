# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One foot bone mesh from stature and sex.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var bone = foot_bone(person, CALCANEUS)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra. Connectivity comes from the field.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    FootBone,
    FootBoneField,
    FootDimensions,
    bone_part_label,
    foot_dimensions,
)
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field


def foot_bone(
    spec: HumanoidSpec,
    part: FootBone,
    side: BodySide = RIGHT,
    detail: Int = 8,
) raises -> BufferGeometry:
    """Return one foot bone sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        part: Which bone to mesh.
        side: `RIGHT` or `LEFT`. A right foot is the default.
        detail: Cells along the bone, eight through sixty-four,
            eight by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec`, `side` or `part` is refused, if `detail` is
            out of range, or if the field produces no surface.
    """
    return bone_from_dimensions(
        foot_dimensions(spec.stature, spec.sex, side), part, detail
    )


def bone_from_dimensions(
    dimensions: FootDimensions, part: FootBone, detail: Int = 8
) raises -> BufferGeometry:
    """Return one bone mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `foot_dimensions`.
        part: Which bone to mesh.
        detail: Cells along the bone.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `detail` is out of range, or if the field
            produces no surface.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A foot bone must be one of the twenty-six bones")
    var label = bone_part_label(part)
    check_detail(detail, label)
    var field = FootBoneField(dimensions, part)
    return mesh_field(field, field.low, field.high, detail, label)
