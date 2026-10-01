# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Pelvic vessel meshes from stature and sex.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var tube = pelvis_vessel(person, EXTERNAL_ILIAC_ARTERY, RIGHT)

A mesh holds every radius to a diagrammatic minimum, so the smallest
branches show. Mass does not.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    PelvisMuscleDimensions,
    pelvis_muscle_dimensions,
)
from extensions.humanoid.skeleton.pelvis.vessels.dimensions import (
    PelvisVessel,
    PelvisVesselField,
    pelvis_vessel_label,
)


def pelvis_vessel(
    spec: HumanoidSpec, part: PelvisVessel, side: BodySide, detail: Int = 16
) raises -> BufferGeometry:
    """Return one pelvic vessel sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which vessel to mesh.
        side: `RIGHT` or `LEFT`. An unpaired vessel ignores it.
        detail: Cells along the solid, eight through sixty-four,
            sixteen by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec`, `part` or `side` is refused, if `detail` is
            out of range, or if the field produces no surface.
    """
    return pelvis_vessel_from_dimensions(
        pelvis_muscle_dimensions(spec), part, side, detail
    )


def pelvis_vessel_from_dimensions(
    dimensions: PelvisMuscleDimensions,
    part: PelvisVessel,
    side: BodySide,
    detail: Int = 16,
) raises -> BufferGeometry:
    """Return one vessel mesh for already-computed dimensions.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        part: Which vessel to mesh.
        side: `RIGHT` or `LEFT`. An unpaired vessel ignores it.
        detail: Cells along the solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `side` is not valid, if `detail` is out of
            range, or if the field produces no surface.
    """
    var S = dimensions.pelvis.stature.value
    var field = PelvisVesselField(dimensions, part, side).widened(0.0018 * S)
    var label = pelvis_vessel_label(part)
    check_detail(detail, label)
    return mesh_field(field, field.low, field.high, detail, label)
