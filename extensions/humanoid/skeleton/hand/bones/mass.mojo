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
from extensions.humanoid.skeleton.arm.bones.mass import fill_at
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
        arm_dimensions(spec.stature, spec.sex),
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
    check_mass_step(step, hand_bone_label(part))
    cortical.validate()
    trabecular.validate()
    var shell = HAND_SHELL * dimensions.stature.value
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
