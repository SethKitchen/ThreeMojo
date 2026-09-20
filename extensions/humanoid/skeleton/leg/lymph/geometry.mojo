# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Lymph meshes from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var nodes = lymph_mesh(person, INGUINAL_NODES)

The solids live in `dimensions`. This file extracts the zero set with
marching tetrahedra. Connectivity comes from the field.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.skeleton.leg.lymph.dimensions import (
    LymphPart,
    _display_lymph_field,
    lymph_part_label,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    MuscleDimensions,
    muscle_dimensions,
)


def lymph_mesh(
    spec: HumanoidSpec,
    part: LymphPart,
    side: BodySide = RIGHT,
    detail: Int = 16,
) raises -> BufferGeometry:
    """Return one named lymph solid sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which solid to mesh.
        side: `RIGHT` or `LEFT`. A right leg is the default.
        detail: Cells along the solid, eight through sixty-four,
            sixteen by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec`, `side` or `part` is refused, if `detail` is
            out of range, or if the field produces no surface.
    """
    return lymph_from_dimensions(muscle_dimensions(spec, side), part, detail)


def lymph_from_dimensions(
    dimensions: MuscleDimensions, part: LymphPart, detail: Int = 16
) raises -> BufferGeometry:
    """Return one lymph mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `muscle_dimensions`.
        part: Which solid to mesh.
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
        raise Error("A lymph part must be a named node group or trunk")
    var label = lymph_part_label(part)
    check_detail(detail, label)
    var field = _display_lymph_field(dimensions, part)
    return mesh_field(field, field.low, field.high, detail, label)
