# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Arm hair meshes from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var shafts = arm_hair_mesh(person, FOREARM_HAIR, LEFT)

The solids live in `dimensions`. Each shaft is meshed on its own at
`DISPLAY_HAIR` times stature, so it shows; mass uses the physical
radius.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.skeleton.arm.frame import (
    ArmMuscleDimensions,
    arm_muscle_dimensions,
)
from extensions.humanoid.skeleton.arm.hair.dimensions import (
    ArmHair,
    arm_hair_field,
    arm_hair_label,
)
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.skeleton.torso.sweep import Dome, Sweep, SweepField
from extensions.humanoid.spec import HumanoidSpec
from geometries.utils import merge_geometries

# The radius a hair mesh shows, as a ratio of stature.
comptime DISPLAY_HAIR = Float32(0.0012)


def arm_hair_mesh(
    spec: HumanoidSpec, part: ArmHair, side: BodySide = RIGHT, detail: Int = 16
) raises -> BufferGeometry:
    """Return one arm hair group sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which group to mesh.
        side: `RIGHT` or `LEFT`. A right arm is the default.
        detail: Cells along each shaft, eight through sixty-four,
            sixteen by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec`, `part` or `side` is refused, if `detail` is
            out of range, or if a shaft produces no surface.
    """
    return arm_hair_from_dimensions(
        arm_muscle_dimensions(spec), part, side, detail
    )


def arm_hair_from_dimensions(
    dimensions: ArmMuscleDimensions,
    part: ArmHair,
    side: BodySide = RIGHT,
    detail: Int = 16,
) raises -> BufferGeometry:
    """Return one hair mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `arm_muscle_dimensions`.
        part: Which group to mesh.
        side: `RIGHT` or `LEFT`.
        detail: Cells along each shaft.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `side` is not valid, if `detail` is out of
            range, or if a shaft produces no surface.
    """
    var label = arm_hair_label(part)
    check_detail(detail, label)
    var field = arm_hair_field(dimensions, part, side)
    return hair_mesh_from_field(
        field, DISPLAY_HAIR * dimensions.arm.stature.value, detail, label
    )


def hair_mesh_from_field(
    field: SweepField, display: Float32, detail: Int, label: String
) raises -> BufferGeometry:
    """Mesh every shaft of a hair field on its own and merge them.

    Args:
        field: A hair group's field: one sweep per shaft.
        display: The radius each shaft shows, in meters.
        detail: Cells along each shaft.
        label: The group's name for error text.

    Returns:
        One geometry holding every shaft.

    Raises:
        Error: If a shaft produces no surface.
    """
    var parts = List[BufferGeometry]()
    var side = RIGHT
    if field.mirror:
        side = LEFT
    for index in range(len(field.sweeps)):  # pragma: no branch
        var one = List[Sweep]()
        one.append(field.sweeps[index].copy())
        var single = SweepField(
            one^, List[Dome](), side, field.k, field.epsilon, 0.002
        ).widened(display)
        parts.append(mesh_field(single, single.low, single.high, detail, label))
    return merge_geometries(parts)
