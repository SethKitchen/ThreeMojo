# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Hand muscle and tendon meshes from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var solid = hand_muscle(person, ADDUCTOR_POLLICIS, RIGHT)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra. A tendon group's mesh widens its thinnest tendons
to `DISPLAY_TENDON` times stature, so they survive a coarse grid. Mass
uses the physical radius.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.arm.frame import (
    ArmMuscleDimensions,
    arm_muscle_dimensions,
)
from extensions.humanoid.skeleton.hand.muscles.dimensions import (
    HandMuscle,
    hand_muscle_field,
    is_hand_tendon,
    hand_muscle_label,
)
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.spec import HumanoidSpec

# The thinnest radius a tendon mesh shows, as a ratio of stature.
comptime DISPLAY_TENDON = Float32(0.0016)


def hand_muscle(
    spec: HumanoidSpec, part: HandMuscle, side: BodySide, detail: Int = 16
) raises -> BufferGeometry:
    """Return one hand muscle sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which part to mesh.
        side: `RIGHT` or `LEFT`.
        detail: Cells along the solid, eight through sixty-four,
            sixteen by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec`, `part` or `side` is refused, if `detail` is
            out of range, or if the field produces no surface.
    """
    return hand_muscle_from_dimensions(
        arm_muscle_dimensions(spec), part, side, detail
    )


def hand_muscle_from_dimensions(
    dimensions: ArmMuscleDimensions,
    part: HandMuscle,
    side: BodySide,
    detail: Int = 16,
) raises -> BufferGeometry:
    """Return one part's mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `arm_muscle_dimensions`.
        part: Which part to mesh.
        side: `RIGHT` or `LEFT`.
        detail: Cells along the solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `side` is not valid, if `detail` is out of
            range, or if the field produces no surface.
    """
    var field = hand_muscle_field(dimensions, part, side)
    if is_hand_tendon(part):
        field = field.widened(DISPLAY_TENDON * dimensions.arm.stature.value)
    var label = hand_muscle_label(part)
    check_detail(detail, label)
    return mesh_field(field, field.low, field.high, detail, label)
