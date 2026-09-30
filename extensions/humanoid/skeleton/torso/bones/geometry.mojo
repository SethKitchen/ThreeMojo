# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One torso bone mesh from stature and sex.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var rib = torso_bone(person, RIB_7, LEFT)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra. Connectivity comes from the field.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    TorsoBone,
    TorsoDimensions,
    torso_bone_field,
    torso_bone_label,
    torso_dimensions,
)


def torso_bone(
    spec: HumanoidSpec, part: TorsoBone, side: BodySide, detail: Int = 16
) raises -> BufferGeometry:
    """Return one torso bone sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        part: Which bone to mesh.
        side: `RIGHT` or `LEFT`. A midline bone ignores it.
        detail: Cells along the bone, eight through sixty-four,
            sixteen by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec`, `part` or `side` is refused, if `detail` is
            out of range, or if the field produces no surface.
    """
    return torso_bone_from_dimensions(
        torso_dimensions(spec.stature, spec.sex, spec.genome), part, side, detail
    )


def torso_bone_from_dimensions(
    dimensions: TorsoDimensions,
    part: TorsoBone,
    side: BodySide,
    detail: Int = 16,
) raises -> BufferGeometry:
    """Return one bone mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `torso_dimensions`.
        part: Which bone to mesh.
        side: `RIGHT` or `LEFT`. A midline bone ignores it.
        detail: Cells along the bone.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `side` is not valid, if `detail` is out of
            range, or if the field produces no surface.
    """
    var field = torso_bone_field(dimensions, part, side)
    var label = torso_bone_label(part)
    check_detail(detail, label)
    return mesh_field(field, field.low, field.high, detail, label)
