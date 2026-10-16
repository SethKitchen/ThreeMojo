# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bone-tissue mass of one foot bone from its solid and tissues.

Tarsals, metatarsals and phalanges have no modeled marrow cavity. A
thin cortical shell wraps a trabecular interior. Porosity is applied
once through apparent density.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = foot_bone_mass(person, CALCANEUS)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    FootBone,
    FootBoneField,
    FootDimensions,
    bone_part_label,
    foot_dimensions,
)
from extensions.humanoid.skeleton.occupancy import (
    CORTICAL_FILL,
    DEFAULT_STEP,
    EMPTY,
    TRABECULAR_FILL,
    BoneMass,
    BoneOccupancy,
    sample_bone_mass,
)
from extensions.anatomy.tissue import (
    BoneTissue,
    cortical_tissue,
    trabecular_tissue,
)
from math.vector3 import Vector3
from units.si import Length


def foot_bone_occupancy(
    dimensions: FootDimensions, part: FootBone, point: Vector3
) raises -> BoneOccupancy:
    """Return what fills `point` in one sized foot bone.

    Args:
        dimensions: A foot already sized from stature and sex.
        part: Which bone to sample.
        point: A point in the foot frame, in meters.

    Returns:
        `EMPTY` outside, `CORTICAL_FILL` in the shell, or
        `TRABECULAR_FILL` in the interior. There is no marrow.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return _occupancy(FootBoneField(dimensions, part), point)


def foot_bone_mass(
    spec: HumanoidSpec,
    part: FootBone,
    side: BodySide = RIGHT,
    step: Length = DEFAULT_STEP,
) raises -> BoneMass:
    """Return the bone-tissue mass of one foot bone sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        part: Which bone to sample.
        side: `RIGHT` or `LEFT`. A right foot is the default.
        step: Grid cell size. 2 mm through 20 mm, 5 mm by default.

    Returns:
        Sampled volumes and the bone-tissue mass.

    Raises:
        Error: If `spec`, `side` or `part` is refused, or `step` is
            out of range.
    """
    return foot_bone_mass_from_dimensions(
        foot_dimensions(spec.stature, spec.sex, side),
        part,
        cortical_tissue(),
        trabecular_tissue(),
        step,
    )


def foot_bone_mass_from_dimensions(
    dimensions: FootDimensions,
    part: FootBone,
    cortical: BoneTissue,
    trabecular: BoneTissue,
    step: Length = DEFAULT_STEP,
) raises -> BoneMass:
    """Return the bone-tissue mass of an already-sized foot bone.

    Args:
        dimensions: Landmarks from `foot_dimensions`.
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
    if not part.is_valid():
        raise Error("A foot bone must be one of the twenty-six bones")
    var label = bone_part_label(part)
    var field = FootBoneField(dimensions, part)
    return sample_bone_mass[foot_bone_field_occupancy](
        field, field.low, field.high, cortical, trabecular, step, label
    )


def foot_bone_field_occupancy(
    field: FootBoneField, point: Vector3
) -> BoneOccupancy:
    """Return what fills `point` in an already-built foot bone field.

    Use this where one field is sampled at many points;
    `foot_bone_occupancy` builds the field for every call.

    Args:
        field: The bone's field.
        point: A point in the foot frame, in meters.

    Returns:
        `EMPTY` outside, `CORTICAL_FILL` in the shell, or
        `TRABECULAR_FILL` inside it.
    """
    return _occupancy(field, point)


def _occupancy(field: FootBoneField, point: Vector3) -> BoneOccupancy:
    """Return what fills `point` in `field`. There is no marrow."""
    var d = field.distance(point)
    if d >= 0:
        return EMPTY
    if d > -field.shell:
        return CORTICAL_FILL
    return TRABECULAR_FILL
