# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bone-tissue mass of one arm bone from its solid and tissues.

A long bone is a cortical tube around a medullary canal. The shaft's
wall is thick and its canal holds yellow marrow; the ends are
trabecular bone in a thin shell. This solid models the wall as a shell
of `ARM_SHELL` times stature, and fills the rest with trabecular bone.
Porosity is applied once through apparent density.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = arm_bone_mass(person, HUMERUS)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.arm.bones.dimensions import (
    ARM_SHELL,
    ArmBone,
    arm_bone_field,
    arm_bone_label,
)
from extensions.humanoid.skeleton.arm.frame import (
    ArmDimensions,
    arm_dimensions,
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
from math.vector3 import Vector3
from units.si import Length


def arm_bone_occupancy(
    dimensions: ArmDimensions, part: ArmBone, side: BodySide, point: Vector3
) raises -> BoneOccupancy:
    """Return what fills `point` in one sized arm bone.

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
    var shell = ARM_SHELL * dimensions.stature.value
    return fill_at(
        arm_bone_field(dimensions, part, side).distance(point), shell
    )


def arm_bone_mass(
    spec: HumanoidSpec, part: ArmBone, step: Length = DEFAULT_STEP
) raises -> BoneMass:
    """Return the bone-tissue mass of one arm bone sized for `spec`.

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
    return arm_bone_mass_from_dimensions(
        arm_dimensions(spec.stature, spec.sex, spec.genome),
        part,
        cortical_tissue(),
        trabecular_tissue(),
        step,
    )


def arm_bone_mass_from_dimensions(
    dimensions: ArmDimensions,
    part: ArmBone,
    cortical: BoneTissue,
    trabecular: BoneTissue,
    step: Length = DEFAULT_STEP,
) raises -> BoneMass:
    """Return the bone-tissue mass of an already-sized arm bone.

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
    var field = arm_bone_field(dimensions, part, RIGHT)
    var shell = ARM_SHELL * dimensions.stature.value
    var low = field.low
    var high = field.high
    return sample_bone_mass[shelled_sweep_occupancy](
        ShelledSweep(field^, shell),
        low,
        high,
        cortical,
        trabecular,
        step,
        arm_bone_label(part),
    )
