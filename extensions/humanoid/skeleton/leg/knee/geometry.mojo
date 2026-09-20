# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Knee soft-tissue meshes from stature and sex.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var cartilage = articular_cartilage(person)

The solids live in `dimensions`. This file extracts the zero set with
marching tetrahedra. Connectivity comes from the field.
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.isosurface import check_detail, mesh_field
from extensions.humanoid.skeleton.leg.knee.dimensions import (
    ARTICULAR_CARTILAGE,
    LATERAL_COLLATERAL,
    LATERAL_MENISCUS,
    MEDIAL_COLLATERAL,
    MEDIAL_MENISCUS,
    CartilageField,
    CollateralField,
    KneeDimensions,
    KneePart,
    MeniscusField,
    knee_dimensions,
    knee_part_label,
)


def articular_cartilage(
    spec: HumanoidSpec, side: BodySide = RIGHT, detail: Int = 24
) raises -> BufferGeometry:
    """Return articular cartilage sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        side: `RIGHT` or `LEFT`. A right knee is the default.
        detail: Cells along the solid, eight through sixty-four,
            twenty-four by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec` or `side` is refused, if `detail` is out of
            range, or if the field produces no surface.
    """
    return knee_mesh(spec, ARTICULAR_CARTILAGE, side, detail)


def medial_meniscus(
    spec: HumanoidSpec, side: BodySide = RIGHT, detail: Int = 24
) raises -> BufferGeometry:
    """Return a medial meniscus sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        side: `RIGHT` or `LEFT`. A right knee is the default.
        detail: Cells along the solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec` or `side` is refused, if `detail` is out of
            range, or if the field produces no surface.
    """
    return knee_mesh(spec, MEDIAL_MENISCUS, side, detail)


def lateral_meniscus(
    spec: HumanoidSpec, side: BodySide = RIGHT, detail: Int = 24
) raises -> BufferGeometry:
    """Return a lateral meniscus sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        side: `RIGHT` or `LEFT`. A right knee is the default.
        detail: Cells along the solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec` or `side` is refused, if `detail` is out of
            range, or if the field produces no surface.
    """
    return knee_mesh(spec, LATERAL_MENISCUS, side, detail)


def medial_collateral(
    spec: HumanoidSpec, side: BodySide = RIGHT, detail: Int = 24
) raises -> BufferGeometry:
    """Return an MCL sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        side: `RIGHT` or `LEFT`. A right knee is the default.
        detail: Cells along the solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec` or `side` is refused, if `detail` is out of
            range, or if the field produces no surface.
    """
    return knee_mesh(spec, MEDIAL_COLLATERAL, side, detail)


def lateral_collateral(
    spec: HumanoidSpec, side: BodySide = RIGHT, detail: Int = 24
) raises -> BufferGeometry:
    """Return an LCL sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        side: `RIGHT` or `LEFT`. A right knee is the default.
        detail: Cells along the solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec` or `side` is refused, if `detail` is out of
            range, or if the field produces no surface.
    """
    return knee_mesh(spec, LATERAL_COLLATERAL, side, detail)


def knee_mesh(
    spec: HumanoidSpec,
    part: KneePart,
    side: BodySide = RIGHT,
    detail: Int = 24,
) raises -> BufferGeometry:
    """Return one knee tissue sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        part: Which solid to mesh.
        side: `RIGHT` or `LEFT`. A right knee is the default.
        detail: Cells along the solid.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `spec`, `side` or `part` is refused, if `detail` is
            out of range, or if the field produces no surface.
    """
    return knee_from_dimensions(
        knee_dimensions(spec.stature, spec.sex, side), part, detail
    )


def knee_from_dimensions(
    dimensions: KneeDimensions, part: KneePart, detail: Int = 24
) raises -> BufferGeometry:
    """Return one knee tissue mesh for already-computed dimensions.

    Args:
        dimensions: Size and landmarks from `knee_dimensions`.
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
        raise Error("A knee part must be cartilage, a meniscus or a collateral")
    var label = knee_part_label(part)
    check_detail(detail, label)
    if part == ARTICULAR_CARTILAGE:
        var cartilage = CartilageField(dimensions)
        return mesh_field(
            cartilage, cartilage.low, cartilage.high, detail, label
        )
    if part == MEDIAL_MENISCUS:
        var medial = MeniscusField(dimensions, part)
        return mesh_field(medial, medial.low, medial.high, detail, label)
    if part == LATERAL_MENISCUS:
        var lateral = MeniscusField(dimensions, part)
        return mesh_field(lateral, lateral.low, lateral.high, detail, label)
    var ligament = CollateralField(dimensions, part)
    return mesh_field(ligament, ligament.low, ligament.high, detail, label)
