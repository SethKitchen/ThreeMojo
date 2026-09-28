# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Torso skin mesh from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var envelope = torso_skin_mesh(person)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra. Connectivity comes from the field.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.skeleton.torso.muscles.dimensions import (
    TorsoMuscleDimensions,
    torso_muscle_dimensions,
)
from extensions.humanoid.skeleton.torso.skin.dimensions import TorsoSkinField


def torso_skin_mesh(
    spec: HumanoidSpec, detail: Int = 16
) raises -> BufferGeometry:
    """Return the torso skin envelope sized for `spec`.

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
    return torso_skin_from_dimensions(torso_muscle_dimensions(spec), detail)


def torso_skin_from_dimensions(
    dimensions: TorsoMuscleDimensions, detail: Int = 16
) raises -> BufferGeometry:
    """Return the torso skin mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `torso_muscle_dimensions`.
        detail: Cells along the solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `detail`
            is out of range, or if the field produces no surface.
    """
    check_detail(detail, "torso skin")
    var field = TorsoSkinField(dimensions)
    return mesh_field(field, field.low, field.high, detail, "torso skin")
