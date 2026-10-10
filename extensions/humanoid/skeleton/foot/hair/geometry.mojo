# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Hair meshes from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var shafts = foot_hair_mesh(person, DORSAL_HAIR)

The solids live in `dimensions`. This file extracts the zero set with
marching tetrahedra. Connectivity comes from the field. The drawn
radius is diagrammatic. Mass uses the physical radius.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.foot.hair.dimensions import (
    FootHair,
    FootHairField,
    foot_hair_part_label,
)
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    FootMuscleDimensions,
    foot_muscle_dimensions,
)
from extensions.humanoid.skeleton.hair_shafts import mesh_hair_shafts
from extensions.humanoid.skeleton.isosurface import check_detail


def foot_hair_mesh(
    spec: HumanoidSpec,
    part: FootHair,
    side: BodySide = RIGHT,
    detail: Int = 8,
) raises -> BufferGeometry:
    """Return one named hair group sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which solid to mesh.
        side: `RIGHT` or `LEFT`. A right foot is the default.
        detail: Cells along the solid, eight through sixty-four,
            eight by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec`, `side` or `part` is refused, if `detail` is
            out of range, or if the field produces no surface.
    """
    return hair_from_dimensions(
        foot_muscle_dimensions(spec, side), part, detail
    )


def hair_from_dimensions(
    dimensions: FootMuscleDimensions, part: FootHair, detail: Int = 8
) raises -> BufferGeometry:
    """Return one hair mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `foot_muscle_dimensions`.
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
        raise Error("A foot hair part must be a named hair group")
    var label = foot_hair_part_label(part)
    check_detail(detail, label)
    var field = FootHairField(dimensions, part)
    var radius = 0.0015 * dimensions.foot.stature.value
    return mesh_hair_shafts(
        [field.a0, field.a1, field.a2, field.a3, field.a4, field.a5],
        [field.b0, field.b1, field.b2, field.b3, field.b4, field.b5],
        radius,
        detail,
        label,
    )
