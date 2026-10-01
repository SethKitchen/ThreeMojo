# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One hand bone mesh from stature and sex.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var bone = hand_bone(person, CAPITATE, LEFT)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.arm.frame import (
    ArmDimensions,
    arm_dimensions,
)
from extensions.humanoid.skeleton.hand.bones.dimensions import (
    HandBone,
    hand_bone_field,
    hand_bone_label,
)
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.spec import HumanoidSpec


def hand_bone(
    spec: HumanoidSpec, part: HandBone, side: BodySide, detail: Int = 16
) raises -> BufferGeometry:
    """Return one hand bone sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        part: Which bone to mesh.
        side: `RIGHT` or `LEFT`.
        detail: Cells along the bone, eight through sixty-four,
            sixteen by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec`, `part` or `side` is refused, if `detail` is
            out of range, or if the field produces no surface.
    """
    return hand_bone_from_dimensions(
        arm_dimensions(spec.stature, spec.sex, spec.genome), part, side, detail
    )


def hand_bone_from_dimensions(
    dimensions: ArmDimensions, part: HandBone, side: BodySide, detail: Int = 16
) raises -> BufferGeometry:
    """Return one bone mesh for an already-computed frame.

    Args:
        dimensions: The arm's frame from `arm_dimensions`.
        part: Which bone to mesh.
        side: `RIGHT` or `LEFT`.
        detail: Cells along the bone.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `side` is not valid, if `detail` is out of
            range, or if the field produces no surface.
    """
    var field = hand_bone_field(dimensions, part, side)
    var label = hand_bone_label(part)
    check_detail(detail, label)
    return mesh_field(field, field.low, field.high, detail, label)
