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
from extensions.humanoid.skeleton.arm.bones.mass import fill_at
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
    check_mass_step(step, head_bone_label(part))
    cortical.validate()
    trabecular.validate()
    var shell = HEAD_SHELL * dimensions.stature.value
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
                    fill_at(field.distance(Vector3(x, y, z)), shell),
                    cell,
                    cortical,
                    trabecular,
                )
    return finish_mass(tally)
