# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One head bone mesh from stature and sex.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var skull = head_bone(person, SKULL)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.head.bones.dimensions import (
    HeadBone,
    head_bone_field,
    head_bone_label,
)
from extensions.humanoid.skeleton.head.frame import (
    HeadDimensions,
    head_dimensions,
)
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field


def head_bone(
    spec: HumanoidSpec, part: HeadBone, detail: Int = 16
) raises -> BufferGeometry:
    """Return one head bone sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        part: Which bone to mesh.
        detail: Cells along the bone, eight through sixty-four,
            sixteen by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec` or `part` is refused, if `detail` is out of
            range, or if the field produces no surface.
    """
    return head_bone_from_dimensions(
        head_dimensions(spec.stature, spec.sex), part, detail
    )


def head_bone_from_dimensions(
    dimensions: HeadDimensions, part: HeadBone, detail: Int = 16
) raises -> BufferGeometry:
    """Return one bone mesh for already-computed landmarks.

    Args:
        dimensions: Landmarks from `head_dimensions`.
        part: Which bone to mesh.
        detail: Cells along the bone.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `detail` is out of range, or if the field
            produces no surface.
    """
    var field = head_bone_field(dimensions, part)
    var label = head_bone_label(part)
    check_detail(detail, label)
    return mesh_field(field, field.low, field.high, detail, label)
