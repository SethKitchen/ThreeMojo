# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Torso joint tissue or ligament meshes from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var solid = torso_ligament(person, COSTAL_CARTILAGES, RIGHT)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    TorsoDimensions,
    torso_dimensions,
)
from extensions.humanoid.skeleton.torso.ligaments.dimensions import (
    TorsoLigament,
    torso_ligament_field,
    torso_ligament_label,
)


def torso_ligament(
    spec: HumanoidSpec, part: TorsoLigament, side: BodySide, detail: Int = 16
) raises -> BufferGeometry:
    """Return one torso joint tissue or ligament sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which part to mesh.
        side: `RIGHT` or `LEFT`. A midline part ignores it.
        detail: Cells along the solid, eight through sixty-four,
            sixteen by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec`, `part` or `side` is refused, if `detail` is
            out of range, or if the field produces no surface.
    """
    return torso_ligament_from_dimensions(
        torso_dimensions(spec.stature, spec.sex, spec.genome), part, side, detail
    )


def torso_ligament_from_dimensions(
    dimensions: TorsoDimensions,
    part: TorsoLigament,
    side: BodySide,
    detail: Int = 16,
) raises -> BufferGeometry:
    """Return one part's mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `torso_dimensions`.
        part: Which part to mesh.
        side: `RIGHT` or `LEFT`. A midline part ignores it.
        detail: Cells along the solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `side` is not valid, if `detail` is out of
            range, or if the field produces no surface.
    """
    var field = torso_ligament_field(dimensions, part, side)
    var label = torso_ligament_label(part)
    check_detail(detail, label)
    return mesh_field(field, field.low, field.high, detail, label)
