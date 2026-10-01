# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Hand skin meshes from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var skin = hand_skin_mesh(person, LEFT)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.arm.frame import (
    ArmMuscleDimensions,
    arm_muscle_dimensions,
)
from extensions.humanoid.skeleton.hand.skin.dimensions import HandSkinField
from extensions.humanoid.skeleton.isosurface import check_detail
from extensions.humanoid.skeleton.surface_nets import mesh_surface
from extensions.humanoid.spec import HumanoidSpec


def hand_skin_mesh(
    spec: HumanoidSpec, side: BodySide = RIGHT, detail: Int = 40
) raises -> BufferGeometry:
    """Return one hand's skin envelope sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        side: `RIGHT` or `LEFT`. A right hand is the default.
        detail: Cells along the solid, eight through sixty-four,
            40 by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec` or `side` is refused, if `detail` is out of
            range, or if the field produces no surface.
    """
    return hand_skin_from_dimensions(arm_muscle_dimensions(spec), side, detail)


def hand_skin_from_dimensions(
    dimensions: ArmMuscleDimensions, side: BodySide = RIGHT, detail: Int = 40
) raises -> BufferGeometry:
    """Return one hand's skin mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `arm_muscle_dimensions`.
        side: `RIGHT` or `LEFT`.
        detail: Cells along the solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `side` is
            not valid, if `detail` is out of range, or if the field
            produces no surface.
    """
    check_detail(detail, "hand skin")
    var field = HandSkinField(dimensions, side)
    return mesh_surface(field, field.low, field.high, detail, "hand skin")
