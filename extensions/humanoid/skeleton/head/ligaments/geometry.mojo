# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Head joint tissue, ligament and cartilage meshes from stature and sex.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var solid = head_ligament(person, LARYNX, RIGHT)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.skeleton.head.frame import (
    HeadDimensions,
    head_dimensions,
)
from extensions.humanoid.skeleton.head.ligaments.dimensions import (
    HeadLigament,
    head_ligament_field,
    head_ligament_label,
)


def head_ligament(
    spec: HumanoidSpec, part: HeadLigament, side: BodySide, detail: Int = 16
) raises -> BufferGeometry:
    """Return one head joint tissue or cartilage sized for `spec`.

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
    return head_ligament_from_dimensions(
        head_dimensions(spec.stature, spec.sex), part, side, detail
    )


def head_ligament_from_dimensions(
    dimensions: HeadDimensions,
    part: HeadLigament,
    side: BodySide,
    detail: Int = 16,
) raises -> BufferGeometry:
    """Return one part's mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `head_dimensions`.
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
    var field = head_ligament_field(dimensions, part, side)
    var label = head_ligament_label(part)
    check_detail(detail, label)
    return mesh_field(field, field.low, field.high, detail, label)
