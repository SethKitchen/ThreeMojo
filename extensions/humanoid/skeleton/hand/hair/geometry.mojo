# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Hand hair meshes from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var shafts = hand_hair_mesh(person, FINGER_HAIR, LEFT)

The solids live in `dimensions`. Each shaft is meshed on its own at
`DISPLAY_HAND_HAIR` times stature, so it shows; mass uses the physical
radius.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.arm.frame import (
    ArmMuscleDimensions,
    arm_muscle_dimensions,
)
from extensions.humanoid.skeleton.arm.hair.geometry import (
    hair_mesh_from_field,
)
from extensions.humanoid.skeleton.hand.hair.dimensions import (
    HandHair,
    hand_hair_field,
    hand_hair_label,
)
from extensions.humanoid.skeleton.isosurface import check_detail
from extensions.humanoid.spec import HumanoidSpec

# The radius a hand hair mesh shows, as a ratio of stature: finer than
# the arm's, since a hand is seen close.
comptime DISPLAY_HAND_HAIR = Float32(0.0005)


def hand_hair_mesh(
    spec: HumanoidSpec, part: HandHair, side: BodySide = RIGHT, detail: Int = 16
) raises -> BufferGeometry:
    """Return one hand hair group sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which group to mesh.
        side: `RIGHT` or `LEFT`. A right hand is the default.
        detail: Cells along each shaft, eight through sixty-four,
            sixteen by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec`, `part` or `side` is refused, if `detail` is
            out of range, or if a shaft produces no surface.
    """
    return hand_hair_from_dimensions(
        arm_muscle_dimensions(spec), part, side, detail
    )


def hand_hair_from_dimensions(
    dimensions: ArmMuscleDimensions,
    part: HandHair,
    side: BodySide = RIGHT,
    detail: Int = 16,
) raises -> BufferGeometry:
    """Return one hair mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `arm_muscle_dimensions`.
        part: Which group to mesh.
        side: `RIGHT` or `LEFT`.
        detail: Cells along each shaft.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `side` is not valid, if `detail` is out of
            range, or if a shaft produces no surface.
    """
    var label = hand_hair_label(part)
    check_detail(detail, label)
    var field = hand_hair_field(dimensions, part, side)
    return hair_mesh_from_field(
        field, DISPLAY_HAND_HAIR * dimensions.arm.stature.value, detail, label
    )
