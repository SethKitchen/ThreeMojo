# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Pelvic ligament and joint-tissue meshes from stature and sex.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var band = pelvis_ligament(person, SACROTUBEROUS, RIGHT)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra. Connectivity comes from the field.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.skeleton.pelvis.ligaments.dimensions import (
    PelvisLigament,
    PelvisLigamentField,
    pelvis_ligament_label,
)
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    PelvisMuscleDimensions,
    pelvis_muscle_dimensions,
)


def pelvis_ligament(
    spec: HumanoidSpec, part: PelvisLigament, side: BodySide, detail: Int = 16
) raises -> BufferGeometry:
    """Return one pelvic ligament or joint tissue sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which part to mesh.
        side: `RIGHT` or `LEFT`.
        detail: Cells along the solid, eight through sixty-four,
            sixteen by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec`, `part` or `side` is refused, if `detail` is
            out of range, or if the field produces no surface.
    """
    return pelvis_ligament_from_dimensions(
        pelvis_muscle_dimensions(spec), part, side, detail
    )


def pelvis_ligament_from_dimensions(
    dimensions: PelvisMuscleDimensions,
    part: PelvisLigament,
    side: BodySide,
    detail: Int = 16,
) raises -> BufferGeometry:
    """Return one part's mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        part: Which part to mesh.
        side: `RIGHT` or `LEFT`.
        detail: Cells along the solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `side` is not valid, if `detail` is out of
            range, or if the field produces no surface.
    """
    var field = PelvisLigamentField(dimensions, part, side)
    var label = pelvis_ligament_label(part)
    check_detail(detail, label)
    return mesh_field(field, field.low, field.high, detail, label)
