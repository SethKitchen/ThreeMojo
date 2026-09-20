# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Nerve meshes from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var sciatic = nerve_mesh(person, SCIATIC_NERVE)

The solids live in `dimensions`. This file extracts the zero set with
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
from extensions.humanoid.skeleton.leg.nerves.dimensions import (
    NerveField,
    NervePart,
    nerve_part_label,
)


def nerve_mesh(
    spec: HumanoidSpec,
    part: NervePart,
    side: BodySide = RIGHT,
    detail: Int = 16,
) raises -> BufferGeometry:
    """Return one named nerve sized for `spec`.

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
    return nerve_from_dimensions(muscle_dimensions(spec, side), part, detail)


def nerve_from_dimensions(
    dimensions: MuscleDimensions, part: NervePart, detail: Int = 16
) raises -> BufferGeometry:
    """Return one nerve mesh for already-computed dimensions.

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
        raise Error("A nerve part must be a named peripheral nerve")
    var label = nerve_part_label(part)
    check_detail(detail, label)
    var field = NerveField(dimensions, part)
    return mesh_field(field, field.low, field.high, detail, label)
