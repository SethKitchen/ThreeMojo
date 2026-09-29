# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The neck's and the head's skin mesh from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var skin = head_skin_mesh(person)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.skeleton.head.frame import (
    HeadMuscleDimensions,
    head_muscle_dimensions,
)
from extensions.humanoid.skeleton.head.skin.dimensions import HeadSkinField
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.spec import HumanoidSpec


def head_skin_mesh(
    spec: HumanoidSpec, detail: Int = 32
) raises -> BufferGeometry:
    """Return the neck's and the head's skin envelope sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        detail: Cells along the solid, eight through sixty-four,
            32 by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec` is refused, if `detail` is out of range, or if
            the field produces no surface.
    """
    return head_skin_from_dimensions(head_muscle_dimensions(spec), detail)


def head_skin_from_dimensions(
    dimensions: HeadMuscleDimensions, detail: Int = 32
) raises -> BufferGeometry:
    """Return the neck's and the head's skin mesh for already-computed
    dimensions.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        detail: Cells along the solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `detail` is
            out of range, or if the field produces no surface.
    """
    check_detail(detail, "head skin")
    var field = HeadSkinField(dimensions)
    return mesh_field(field, field.low, field.high, detail, "head skin")
