# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Vessel meshes from stature, sex and athleticism.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var artery = vessel_mesh(person, FEMORAL_ARTERY)

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
from extensions.humanoid.skeleton.leg.vessels.dimensions import (
    VesselPart,
    _display_vessel_field,
    vessel_part_label,
)


def vessel_mesh(
    spec: HumanoidSpec,
    part: VesselPart,
    side: BodySide = RIGHT,
    detail: Int = 16,
) raises -> BufferGeometry:
    """Return one named vessel sized for `spec`.

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
    return vessel_from_dimensions(muscle_dimensions(spec, side), part, detail)


def vessel_from_dimensions(
    dimensions: MuscleDimensions, part: VesselPart, detail: Int = 16
) raises -> BufferGeometry:
    """Return one vessel mesh for already-computed dimensions.

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
        raise Error("A vessel part must be a named artery or vein")
    var label = vessel_part_label(part)
    check_detail(detail, label)
    var field = _display_vessel_field(dimensions, part)
    return mesh_field(field, field.low, field.high, detail, label)
