# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A femur mesh from stature and sex.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var bone = femur(person)

The solid lives in `dimensions`. This file extracts the zero set with
marching tetrahedra. Connectivity comes from the field.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.skeleton.leg.femur.dimensions import (
    FemurDimensions,
    FemurField,
    femur_dimensions,
)


def femur(
    spec: HumanoidSpec, side: BodySide = RIGHT, detail: Int = 24
) raises -> BufferGeometry:
    """Return a femur sized for `spec`, standing on y, origin at mid-shaft.

    Args:
        spec: Standing height and osteological sex. The femur reads both.
        side: `RIGHT` or `LEFT`. A right femur is the default.
        detail: Cells along the bone, eight through sixty-four,
            twenty-four by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes, indexed
        by the isosurface triangles. Each normal points out of the bone.

    Raises:
        Error: If `spec.sex` or `side` is not valid, if stature is not
            finite or is outside 1.2 m through 2.5 m, if `detail` is
            out of range, or if the field produces no surface.
    """
    return femur_from_dimensions(
        femur_dimensions(spec.stature, spec.sex, side), detail
    )


def femur_from_dimensions(
    dimensions: FemurDimensions, detail: Int = 24
) raises -> BufferGeometry:
    """Return a femur mesh for already-computed dimensions.

    Args:
        dimensions: Size and landmarks from `femur_dimensions`.
        detail: Cells along the bone.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `detail` is
            less than eight or more than sixty-four, or if the field
            produces no surface.
    """
    dimensions.validate()
    check_detail(detail, "femur")
    var field = FemurField(dimensions)
    return mesh_field(field, field.low, field.high, detail, "femur")
