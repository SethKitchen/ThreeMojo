# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Pelvic skin mesh from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var envelope = pelvis_skin_mesh(person)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra. Connectivity comes from the field.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    PelvisMuscleDimensions,
    pelvis_muscle_dimensions,
)
from extensions.humanoid.skeleton.pelvis.skin.dimensions import PelvisSkinField


def pelvis_skin_mesh(
    spec: HumanoidSpec, detail: Int = 16
) raises -> BufferGeometry:
    """Return the pelvic skin envelope sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        detail: Cells along the solid, eight through sixty-four,
            sixteen by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec` is refused, if `detail` is out of range, or if
            the field produces no surface.
    """
    return pelvis_skin_from_dimensions(pelvis_muscle_dimensions(spec), detail)


def pelvis_skin_from_dimensions(
    dimensions: PelvisMuscleDimensions, detail: Int = 16
) raises -> BufferGeometry:
    """Return the pelvic skin mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        detail: Cells along the solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `detail`
            is out of range, or if the field produces no surface.
    """
    check_detail(detail, "pelvic skin")
    var field = PelvisSkinField(dimensions)
    return mesh_field(field, field.low, field.high, detail, "pelvic skin")
