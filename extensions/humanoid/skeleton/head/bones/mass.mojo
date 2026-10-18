# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bone-tissue mass of one head bone from its solid and tissues.

A vertebra, the mandible and the hyoid are trabecular bone in a
cortical shell of `HEAD_SHELL` times stature. The skull's vault is a
thin dome, most of which is inside that shell and so is cortical.
Porosity is applied once through apparent density.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = head_bone_mass(person, SKULL)
"""

from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.head.bones.dimensions import (
    HEAD_SHELL,
    HeadBone,
    head_bone_field,
    head_bone_label,
)
from extensions.humanoid.skeleton.head.frame import (
    HeadDimensions,
    head_dimensions,
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


def head_bone_occupancy(
    dimensions: HeadDimensions, part: HeadBone, point: Vector3
) raises -> BoneOccupancy:
    """Return what fills `point` in one sized head bone.

    Args:
        dimensions: Landmarks from `head_dimensions`.
        part: Which bone to sample.
        point: A point in the pelvis frame, in meters.

    Returns:
        `EMPTY` outside, `CORTICAL_FILL` in the shell, or
        `TRABECULAR_FILL` inside it.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or if `part`
            is not named.
    """
    var shell = HEAD_SHELL * dimensions.stature.value
    return fill_at(head_bone_field(dimensions, part).distance(point), shell)


def head_bone_mass(
    spec: HumanoidSpec, part: HeadBone, step: Length = DEFAULT_STEP
) raises -> BoneMass:
    """Return the bone-tissue mass of one head bone sized for `spec`.

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
    return head_bone_mass_from_dimensions(
        head_dimensions(spec.stature, spec.sex, spec.genome),
        part,
        cortical_tissue(),
        trabecular_tissue(),
        step,
    )


def head_bone_mass_from_dimensions(
    dimensions: HeadDimensions,
    part: HeadBone,
    cortical: BoneTissue,
    trabecular: BoneTissue,
    step: Length = DEFAULT_STEP,
) raises -> BoneMass:
    """Return the bone-tissue mass of an already-sized head bone.

    Args:
        dimensions: Landmarks from `head_dimensions`.
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
    var field = head_bone_field(dimensions, part)
    var shell = HEAD_SHELL * dimensions.stature.value
    var low = field.low
    var high = field.high
    return sample_bone_mass[shelled_sweep_occupancy](
        ShelledSweep(field^, shell),
        low,
        high,
        cortical,
        trabecular,
        step,
        head_bone_label(part),
    )
