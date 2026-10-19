# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bone-tissue mass of one pelvic bone from its solid and tissues.

The hip bones, the sacrum and the coccyx are flat and irregular bones.
They have no modeled marrow cavity. A thin cortical shell wraps a
trabecular interior, and the red marrow lives in the trabecular pores.
Porosity is applied once through apparent density.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = pelvis_bone_mass(person, RIGHT_HIP_BONE)
"""

from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.occupancy import (
    DEFAULT_STEP,
    BoneMass,
    BoneOccupancy,
    sample_bone_mass,
)
from extensions.humanoid.skeleton.shell_sample import fill_at
from extensions.humanoid.skeleton.pelvis.bones.dimensions import (
    PelvisBone,
    require_pelvis_bone,
    PelvisBoneField,
    PelvisDimensions,
    pelvis_bone_label,
    pelvis_dimensions,
)
from extensions.anatomy.tissue import (
    BoneTissue,
    cortical_tissue,
    trabecular_tissue,
)
from math.vector3 import Vector3
from units.si import Length


def pelvis_bone_occupancy(
    dimensions: PelvisDimensions, part: PelvisBone, point: Vector3
) raises -> BoneOccupancy:
    """Return what fills `point` in one sized pelvic bone.

    Args:
        dimensions: A pelvis already sized from stature and sex.
        part: Which bone to sample.
        point: A point in the pelvis frame, in meters.

    Returns:
        `EMPTY` outside, `CORTICAL_FILL` in the shell, or
        `TRABECULAR_FILL` in the interior. There is no marrow cavity.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return pelvis_bone_field_occupancy(PelvisBoneField(dimensions, part), point)


def pelvis_bone_field_occupancy(
    field: PelvisBoneField, point: Vector3
) -> BoneOccupancy:
    """Return what fills `point` in an already-built pelvic bone field.

    Use this where one field is sampled at many points;
    `pelvis_bone_occupancy` builds the field for every call.

    Args:
        field: The bone's field.
        point: A point in the pelvis frame, in meters.

    Returns:
        `EMPTY` outside, `CORTICAL_FILL` in the shell, or
        `TRABECULAR_FILL` inside it.
    """
    return fill_at(field.distance(point), field.shell)


def pelvis_bone_mass(
    spec: HumanoidSpec, part: PelvisBone, step: Length = DEFAULT_STEP
) raises -> BoneMass:
    """Return the bone-tissue mass of one pelvic bone sized for `spec`.

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
    return pelvis_bone_mass_from_dimensions(
        pelvis_dimensions(spec.stature, spec.sex),
        part,
        cortical_tissue(),
        trabecular_tissue(),
        step,
    )


def pelvis_bone_mass_from_dimensions(
    dimensions: PelvisDimensions,
    part: PelvisBone,
    cortical: BoneTissue,
    trabecular: BoneTissue,
    step: Length = DEFAULT_STEP,
) raises -> BoneMass:
    """Return the bone-tissue mass of an already-sized pelvic bone.

    Args:
        dimensions: Landmarks from `pelvis_dimensions`.
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
    dimensions.validate()
    require_pelvis_bone(part)
    var label = pelvis_bone_label(part)
    var field = PelvisBoneField(dimensions, part)
    return sample_bone_mass[pelvis_bone_field_occupancy](
        field, field.low, field.high, cortical, trabecular, step, label
    )
