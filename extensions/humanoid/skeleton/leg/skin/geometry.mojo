# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Skin mesh from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var envelope = skin_mesh(person)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra. Connectivity comes from the field.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    MuscleDimensions,
    muscle_dimensions,
)
from extensions.humanoid.skeleton.leg.skin.dimensions import SkinField


def skin_mesh(
    spec: HumanoidSpec, side: BodySide = RIGHT, detail: Int = 16
) raises -> BufferGeometry:
    """Return the skin envelope sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        side: `RIGHT` or `LEFT`. A right leg is the default.
        detail: Cells along the solid, eight through sixty-four,
            sixteen by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec` or `side` is refused, if `detail` is out of
            range, or if the field produces no surface.
    """
    return skin_from_dimensions(muscle_dimensions(spec, side), detail)


def skin_from_dimensions(
    dimensions: MuscleDimensions, detail: Int = 16
) raises -> BufferGeometry:
    """Return the skin mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `muscle_dimensions`.
        detail: Cells along the solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `detail`
            is out of range, or if the field produces no surface.
    """
    dimensions.validate()
    check_detail(detail, "skin")
    var field = SkinField(dimensions)
    return mesh_field(field, field.low, field.high, detail, "skin")
