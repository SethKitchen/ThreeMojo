# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bone-tissue mass of one hand bone from its solid and tissues.

The carpals are trabecular bone in a thin cortical shell. The
metacarpals and the phalanges are short long bones: a cortical wall
around a narrow canal, with trabecular ends. This solid models the
wall as a shell of `HAND_SHELL` times stature, and fills the rest with
trabecular bone. Porosity is applied once through apparent density.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = hand_bone_mass(person, METACARPAL_3)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.arm.frame import (
    ArmDimensions,
    arm_dimensions,
)
from extensions.humanoid.skeleton.hand.bones.dimensions import (
    HAND_SHELL,
    HandBone,
    hand_bone_field,
    hand_bone_label,
)
from extensions.humanoid.skeleton.occupancy import (
    DEFAULT_STEP,
    BoneMass,
    BoneOccupancy,
    sample_bone_mass,
)
from extensions.humanoid.skeleton.shell_sample import (
    ShelledSweep,
    fill_at,
    shelled_sweep_occupancy,
)
from extensions.anatomy.tissue import (
    BoneTissue,
    cortical_tissue,
    trabecular_tissue,
)
from extensions.humanoid.spec import HumanoidSpec
from math.vector3 import Vector3
from units.si import Length


def hand_bone_occupancy(
    dimensions: ArmDimensions, part: HandBone, side: BodySide, point: Vector3
) raises -> BoneOccupancy:
    """Return what fills `point` in one sized hand bone.

    Args:
        dimensions: The arm's frame from `arm_dimensions`.
        part: Which bone to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        `EMPTY` outside, `CORTICAL_FILL` in the shell, or
        `TRABECULAR_FILL` inside it.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    var shell = HAND_SHELL * dimensions.stature.value
    return fill_at(
        hand_bone_field(dimensions, part, side).distance(point), shell
    )


def hand_bone_mass(
    spec: HumanoidSpec, part: HandBone, step: Length = DEFAULT_STEP
) raises -> BoneMass:
    """Return the bone-tissue mass of one hand bone sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        part: Which bone to sample.
        step: Grid cell size. 2 mm through 20 mm, 5 mm by default.

    Returns:
        Sampled volumes and the bone-tissue mass.

    Raises:
        Error: If `spec` or `part` is refused, or `step` is out of
            range.
    """
    return hand_bone_mass_from_dimensions(
        arm_dimensions(spec.stature, spec.sex, spec.genome),
        part,
        cortical_tissue(),
        trabecular_tissue(),
        step,
    )


def hand_bone_mass_from_dimensions(
    dimensions: ArmDimensions,
    part: HandBone,
    cortical: BoneTissue,
    trabecular: BoneTissue,
    step: Length = DEFAULT_STEP,
) raises -> BoneMass:
    """Return the bone-tissue mass of an already-sized hand bone.

    Args:
        dimensions: The arm's frame from `arm_dimensions`.
        part: Which bone to sample.
        cortical: Cortical tissue for the shell.
        trabecular: Trabecular tissue for the interior.
        step: Grid cell size.

    Returns:
        Sampled volumes and the bone-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `step` is out of range, or either tissue
            fails `validate`.
    """
    var field = hand_bone_field(dimensions, part, RIGHT)
    var shell = HAND_SHELL * dimensions.stature.value
    var low = field.low
    var high = field.high
    return sample_bone_mass[shelled_sweep_occupancy](
        ShelledSweep(field^, shell),
        low,
        high,
        cortical,
        trabecular,
        step,
        hand_bone_label(part),
    )
