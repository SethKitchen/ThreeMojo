# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Foot vessel meshes from stature and sex.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var artery = foot_vessel(person, DORSALIS_PEDIS_ARTERY)

The mesh uses a diagrammatic radius. Mass uses the physical radius.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    FootDimensions,
    foot_dimensions,
)
from extensions.humanoid.skeleton.foot.vessels.dimensions import (
    FootVessel,
    display_vessel_field,
    vessel_part_label,
)
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field


def foot_vessel(
    spec: HumanoidSpec,
    part: FootVessel,
    side: BodySide = RIGHT,
    detail: Int = 8,
) raises -> BufferGeometry:
    """Return one foot vessel sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        part: Which vessel to mesh.
        side: `RIGHT` or `LEFT`. A right foot is the default.
        detail: Cells along the solid, eight through sixty-four,
            eight by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec`, `side` or `part` is refused, if `detail` is
            out of range, or if the field produces no surface.
    """
    return vessel_from_dimensions(
        foot_dimensions(spec.stature, spec.sex, side), part, detail
    )


def vessel_from_dimensions(
    dimensions: FootDimensions, part: FootVessel, detail: Int = 8
) raises -> BufferGeometry:
    """Return one vessel mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `foot_dimensions`.
        part: Which vessel to mesh.
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
        raise Error("A foot vessel must be a named artery or vein")
    var label = vessel_part_label(part)
    check_detail(detail, label)
    var field = display_vessel_field(dimensions, part)
    return mesh_field(field, field.low, field.high, detail, label)
