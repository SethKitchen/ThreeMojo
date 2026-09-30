# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Head hair meshes from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var hair = head_hair(person, SCALP_HAIR, RIGHT)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.head.frame import (
    HeadMuscleDimensions,
    head_muscle_dimensions,
)
from extensions.humanoid.skeleton.head.hair.dimensions import (
    HeadHair,
    head_hair_field,
    head_hair_label,
)
from extensions.humanoid.skeleton.isosurface import check_detail
from extensions.humanoid.skeleton.surface_nets import mesh_surface
from extensions.humanoid.spec import HumanoidSpec


def head_hair(
    spec: HumanoidSpec, part: HeadHair, side: BodySide, detail: Int = 16
) raises -> BufferGeometry:
    """Return one head hair group sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which group to mesh.
        side: `RIGHT` or `LEFT`. The scalp's hair ignores it.
        detail: Cells along the solid, eight through sixty-four,
            sixteen by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec`, `part` or `side` is refused, if `detail` is
            out of range, or if the field produces no surface.
    """
    return head_hair_from_dimensions(
        head_muscle_dimensions(spec), part, side, detail
    )


def head_hair_from_dimensions(
    dimensions: HeadMuscleDimensions,
    part: HeadHair,
    side: BodySide,
    detail: Int = 16,
) raises -> BufferGeometry:
    """Return one hair group's mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        part: Which group to mesh.
        side: `RIGHT` or `LEFT`. The scalp's hair ignores it.
        detail: Cells along the solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `side` is not valid, if `detail` is out of
            range, or if the field produces no surface.
    """
    var field = head_hair_field(dimensions, part, side)
    var label = head_hair_label(part)
    check_detail(detail, label)
    return mesh_surface(field, field.low, field.high, detail, label)
