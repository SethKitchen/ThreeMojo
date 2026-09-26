# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Foot muscle meshes from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    var belly = foot_muscle(person, ABDUCTOR_HALLUCIS)

Tendon meshes use a diagrammatic minimum radius. Mass does not.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.foot.chain import (
    enlarge_tube_set,
    tube_set_bounds,
)
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    FootMuscle,
    FootMuscleDimensions,
    FootMuscleField,
    foot_muscle_dimensions,
    foot_muscle_part_label,
    is_tendon,
)
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field


def foot_muscle(
    spec: HumanoidSpec,
    part: FootMuscle,
    side: BodySide = RIGHT,
    detail: Int = 8,
) raises -> BufferGeometry:
    """Return one foot muscle or tendon sized for `spec`.

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
    return muscle_from_dimensions(
        foot_muscle_dimensions(spec, side), part, detail
    )


def muscle_from_dimensions(
    dimensions: FootMuscleDimensions, part: FootMuscle, detail: Int = 8
) raises -> BufferGeometry:
    """Return one muscle mesh for already-computed dimensions.

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
        raise Error("A foot muscle must be a named muscle or tendon")
    var label = foot_muscle_part_label(part)
    check_detail(detail, label)
    var field = FootMuscleField(dimensions, part)
    if is_tendon(part):
        var least = 0.0018 * dimensions.foot.stature.value
        field.tubes = enlarge_tube_set(field.tubes, least)
        field.k = 0.0012 * dimensions.foot.stature.value
        var box = tube_set_bounds(field.tubes, 0.004)
        field.low = box.low
        field.high = box.high
    return mesh_field(field, field.low, field.high, detail, label)
