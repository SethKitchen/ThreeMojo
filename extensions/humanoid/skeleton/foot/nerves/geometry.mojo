# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Foot nerve meshes from stature and sex.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var nerve = foot_nerve(person, TIBIAL_NERVE)

The mesh uses a diagrammatic radius. Mass uses the physical radius.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    FootDimensions,
    foot_dimensions,
)
from extensions.humanoid.skeleton.foot.nerves.dimensions import (
    FootNerve,
    display_nerve_field,
    nerve_part_label,
)
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field


def foot_nerve(
    spec: HumanoidSpec,
    part: FootNerve,
    side: BodySide = RIGHT,
    detail: Int = 8,
) raises -> BufferGeometry:
    """Return one foot nerve sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        part: Which nerve to mesh.
        side: `RIGHT` or `LEFT`. A right foot is the default.
        detail: Cells along the solid, eight through sixty-four,
            eight by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec`, `side` or `part` is refused, if `detail` is
            out of range, or if the field produces no surface.
    """
    return nerve_from_dimensions(
        foot_dimensions(spec.stature, spec.sex, side), part, detail
    )


def nerve_from_dimensions(
    dimensions: FootDimensions, part: FootNerve, detail: Int = 8
) raises -> BufferGeometry:
    """Return one nerve mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `foot_dimensions`.
        part: Which nerve to mesh.
        detail: Cells along the solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `detail` is out of range, or if the field
            produces no surface.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A foot nerve must be a named nerve")
    var label = nerve_part_label(part)
    check_detail(detail, label)
    var field = display_nerve_field(dimensions, part)
    return mesh_field(field, field.low, field.high, detail, label)
