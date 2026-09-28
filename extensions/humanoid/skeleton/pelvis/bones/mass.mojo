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
from extensions.humanoid.skeleton.pelvis.bones.dimensions import (
    PelvisBone,
    PelvisBoneField,
    PelvisDimensions,
    pelvis_bone_label,
    pelvis_dimensions,
)
from extensions.humanoid.skeleton.tissue import (
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
    var d = field.distance(point)
    if d >= 0:
        return EMPTY
    if d > -field.shell:
        return CORTICAL_FILL
    return TRABECULAR_FILL


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
    if not part.is_valid():
        raise Error("A pelvic bone must be one of the four bones")
    var label = pelvis_bone_label(part)
    check_mass_step(step, label)
    cortical.validate()
    trabecular.validate()
    var field = PelvisBoneField(dimensions, part)
    var dx = step.value
    var nx = grid_cells(field.high.x - field.low.x, dx)
    var ny = grid_cells(field.high.y - field.low.y, dx)
    var nz = grid_cells(field.high.z - field.low.z, dx)
    var cell = dx * dx * dx
    var tally = Tally(0, 0, 0, 0, 0)
    for iz in range(nz):  # pragma: no branch
        var z = field.low.z + (Float32(iz) + Float32(0.5)) * dx
        for iy in range(ny):  # pragma: no branch
            var y = field.low.y + (Float32(iy) + Float32(0.5)) * dx
            for ix in range(nx):  # pragma: no branch
                var x = field.low.x + (Float32(ix) + Float32(0.5)) * dx
                add_fill(
                    tally,
                    pelvis_bone_field_occupancy(field, Vector3(x, y, z)),
                    cell,
                    cortical,
                    trabecular,
                )
    return finish_mass(tally)
