# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Head nerve meshes from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var solid = head_nerve(person, VAGUS_NERVE, RIGHT)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra. A mesh holds every radius to a diagrammatic minimum, so the thinnest branches show. Mass does not.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import BodySide
from extensions.humanoid.skeleton.head.frame import (
    HeadMuscleDimensions,
    head_muscle_dimensions,
)
from extensions.humanoid.skeleton.head.nerves.dimensions import (
    HeadNerve,
    head_nerve_field,
    head_nerve_label,
)
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.spec import HumanoidSpec


def head_nerve(
    spec: HumanoidSpec, part: HeadNerve, side: BodySide, detail: Int = 16
) raises -> BufferGeometry:
    """Return one head nerve sized for `spec`.

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
    return head_nerve_from_dimensions(
        head_muscle_dimensions(spec), part, side, detail
    )


def head_nerve_from_dimensions(
    dimensions: HeadMuscleDimensions,
    part: HeadNerve,
    side: BodySide,
    detail: Int = 16,
) raises -> BufferGeometry:
    """Return one part's mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
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
    var S = dimensions.head.stature.value
    var field = head_nerve_field(dimensions, part, side).widened(0.0015 * S)
    var label = head_nerve_label(part)
    check_detail(detail, label)
    return mesh_field(field, field.low, field.high, detail, label)
