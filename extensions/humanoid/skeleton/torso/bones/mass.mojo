# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bone-tissue mass of one torso bone from its solid and tissues.

Vertebrae, ribs and the sternum carry red marrow in trabecular bone.
There is no modeled marrow cavity. A thin cortical shell wraps the
trabecular interior. Porosity is applied once through apparent density.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = torso_bone_mass(person, L3)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
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
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    TORSO_SHELL,
    TorsoBone,
    TorsoDimensions,
    torso_bone_field,
    torso_bone_label,
    torso_dimensions,
)
from math.vector3 import Vector3
from units.si import Length


def torso_bone_occupancy(
    dimensions: TorsoDimensions,
    part: TorsoBone,
    side: BodySide,
    point: Vector3,
) raises -> BoneOccupancy:
    """Return what fills `point` in one sized torso bone.

    Args:
        dimensions: Landmarks from `torso_dimensions`.
        part: Which bone to sample.
        side: `RIGHT` or `LEFT`. A midline bone ignores it.
        point: A point in the pelvis frame, in meters.

    Returns:
        `EMPTY` outside, `CORTICAL_FILL` in the shell, or
        `TRABECULAR_FILL` inside it.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    var shell = TORSO_SHELL * dimensions.stature.value
    return fill_at(
        torso_bone_field(dimensions, part, side).distance(point), shell
    )


def torso_bone_mass(
    spec: HumanoidSpec, part: TorsoBone, step: Length = DEFAULT_STEP
) raises -> BoneMass:
    """Return the bone-tissue mass of one torso bone sized for `spec`.

    A rib is one side's.

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
    return torso_bone_mass_from_dimensions(
        torso_dimensions(spec.stature, spec.sex, spec.genome),
        part,
        cortical_tissue(),
        trabecular_tissue(),
        step,
    )


def torso_bone_mass_from_dimensions(
    dimensions: TorsoDimensions,
    part: TorsoBone,
    cortical: BoneTissue,
    trabecular: BoneTissue,
    step: Length = DEFAULT_STEP,
) raises -> BoneMass:
    """Return the bone-tissue mass of an already-sized torso bone.

    Args:
        dimensions: Landmarks from `torso_dimensions`.
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
    var field = torso_bone_field(dimensions, part, RIGHT)
    var shell = TORSO_SHELL * dimensions.stature.value
    var low = field.low
    var high = field.high
    return sample_bone_mass[shelled_sweep_occupancy](
        ShelledSweep(field^, shell),
        low,
        high,
        cortical,
        trabecular,
        step,
        torso_bone_label(part),
    )
