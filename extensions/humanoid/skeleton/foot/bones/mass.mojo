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
    Tally,
    add_fill,
    check_mass_step,
    finish_mass,
    grid_cells,
)
from extensions.humanoid.skeleton.tissue import (
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
    check_mass_step(step, label)
    cortical.validate()
    trabecular.validate()
    var field = FootBoneField(dimensions, part)
    var dx = step.value
    var dy = step.value
    var dz = step.value
    var nx = grid_cells(field.high.x - field.low.x, dx)
    var ny = grid_cells(field.high.y - field.low.y, dy)
    var nz = grid_cells(field.high.z - field.low.z, dz)
    var cell = dx * dy * dz
    var tally = Tally(0, 0, 0, 0, 0)
    for iz in range(nz):  # pragma: no branch
        var z = field.low.z + (Float32(iz) + Float32(0.5)) * dz
        for iy in range(ny):  # pragma: no branch
            var y = field.low.y + (Float32(iy) + Float32(0.5)) * dy
            for ix in range(nx):  # pragma: no branch
                var x = field.low.x + (Float32(ix) + Float32(0.5)) * dx
                add_fill(
                    tally,
                    _occupancy(field, Vector3(x, y, z)),
                    cell,
                    cortical,
                    trabecular,
                )
    return finish_mass(tally)


def _occupancy(field: FootBoneField, point: Vector3) -> BoneOccupancy:
    """Return what fills `point` in `field`. There is no marrow."""
    var d = field.distance(point)
    if d >= 0:
        return EMPTY
    if d > -field.shell:
        return CORTICAL_FILL
    return TRABECULAR_FILL
