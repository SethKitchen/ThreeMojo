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
    return _fill(
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
    check_mass_step(step, torso_bone_label(part))
    cortical.validate()
    trabecular.validate()
    var shell = TORSO_SHELL * dimensions.stature.value
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
                    _fill(field.distance(Vector3(x, y, z)), shell),
                    cell,
                    cortical,
                    trabecular,
                )
    return finish_mass(tally)


def _fill(d: Float32, shell: Float32) -> BoneOccupancy:
    """Return the fill at a signed distance from the bone's surface."""
    if d >= 0:
        return EMPTY
    if d > -shell:
        return CORTICAL_FILL
    return TRABECULAR_FILL
