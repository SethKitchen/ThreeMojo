# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a knee solid from its field and tissue.

The mesh is the outer surface. The interior is hydrated tissue. Mass is
wet density times envelope volume. Water fraction is metadata. It is not
applied again.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = articular_cartilage_mass(person)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
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
    knee_distance,
    knee_part_label,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SOFT_STEP,
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    cartilage_tissue,
    classify_soft,
    ligament_tissue,
    meniscus_tissue,
    sample_soft_mass,
)
from math.vector3 import Vector3
from units.si import Length


def knee_occupancy(
    dimensions: KneeDimensions, part: KneePart, point: Vector3
) raises -> SoftOccupancy:
    """Return what fills `point` in one knee solid.

    Args:
        dimensions: Knee tissues already sized from stature and sex.
        part: Which solid to sample.
        point: A point in the leg frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not a named knee part.
    """
    return classify_soft(knee_distance(dimensions, part, point))


def articular_cartilage_mass(
    spec: HumanoidSpec, side: BodySide = RIGHT, step: Length = SOFT_STEP
) raises -> SoftMass:
    """Return the wet-tissue mass of articular cartilage for `spec`.

    Args:
        spec: Standing height and osteological sex.
        side: `RIGHT` or `LEFT`. A right knee is the default.
        step: Grid cell size. 2 mm through 20 mm, 2 mm by default.

    Returns:
        Sampled envelope volume and wet-tissue mass.

    Raises:
        Error: If `spec` or `side` is refused, or `step` is out of range.
    """
    return knee_mass(spec, ARTICULAR_CARTILAGE, side, step)


def medial_meniscus_mass(
    spec: HumanoidSpec, side: BodySide = RIGHT, step: Length = SOFT_STEP
) raises -> SoftMass:
    """Return the wet-tissue mass of the medial meniscus for `spec`.

    Args:
        spec: Standing height and osteological sex.
        side: `RIGHT` or `LEFT`.
        step: Grid cell size.

    Returns:
        Sampled envelope volume and wet-tissue mass.

    Raises:
        Error: If `spec` or `side` is refused, or `step` is out of range.
    """
    return knee_mass(spec, MEDIAL_MENISCUS, side, step)


def lateral_meniscus_mass(
    spec: HumanoidSpec, side: BodySide = RIGHT, step: Length = SOFT_STEP
) raises -> SoftMass:
    """Return the wet-tissue mass of the lateral meniscus for `spec`.

    Args:
        spec: Standing height and osteological sex.
        side: `RIGHT` or `LEFT`.
        step: Grid cell size.

    Returns:
        Sampled envelope volume and wet-tissue mass.

    Raises:
        Error: If `spec` or `side` is refused, or `step` is out of range.
    """
    return knee_mass(spec, LATERAL_MENISCUS, side, step)


def medial_collateral_mass(
    spec: HumanoidSpec, side: BodySide = RIGHT, step: Length = SOFT_STEP
) raises -> SoftMass:
    """Return the wet-tissue mass of the MCL for `spec`.

    Args:
        spec: Standing height and osteological sex.
        side: `RIGHT` or `LEFT`.
        step: Grid cell size.

    Returns:
        Sampled envelope volume and wet-tissue mass.

    Raises:
        Error: If `spec` or `side` is refused, or `step` is out of range.
    """
    return knee_mass(spec, MEDIAL_COLLATERAL, side, step)


def lateral_collateral_mass(
    spec: HumanoidSpec, side: BodySide = RIGHT, step: Length = SOFT_STEP
) raises -> SoftMass:
    """Return the wet-tissue mass of the LCL for `spec`.

    Args:
        spec: Standing height and osteological sex.
        side: `RIGHT` or `LEFT`.
        step: Grid cell size.

    Returns:
        Sampled envelope volume and wet-tissue mass.

    Raises:
        Error: If `spec` or `side` is refused, or `step` is out of range.
    """
    return knee_mass(spec, LATERAL_COLLATERAL, side, step)


def knee_mass(
    spec: HumanoidSpec,
    part: KneePart,
    side: BodySide = RIGHT,
    step: Length = SOFT_STEP,
) raises -> SoftMass:
    """Return the wet-tissue mass of one knee solid sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        part: Which solid to sample.
        side: `RIGHT` or `LEFT`.
        step: Grid cell size.

    Returns:
        Sampled envelope volume and wet-tissue mass.

    Raises:
        Error: If `spec`, `side` or `part` is refused, or `step` is out
            of range.
    """
    return knee_mass_from_dimensions(
        knee_dimensions(spec.stature, spec.sex, side),
        part,
        _tissue_of(part),
        step,
    )


def knee_mass_from_dimensions(
    dimensions: KneeDimensions,
    part: KneePart,
    tissue: SoftTissue,
    step: Length = SOFT_STEP,
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized knee solid.

    Args:
        dimensions: Size and landmarks from `knee_dimensions`.
        part: Which solid to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.
        step: Grid cell size.

    Returns:
        Sampled envelope volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `step` is out of range, or `tissue` fails
            `validate`.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A knee part must be cartilage, a meniscus or a collateral")
    var label = knee_part_label(part)
    if part == ARTICULAR_CARTILAGE:
        var cartilage = CartilageField(dimensions)
        return sample_soft_mass(
            cartilage, cartilage.low, cartilage.high, tissue, step, label
        )
    if part == MEDIAL_MENISCUS:
        var medial = MeniscusField(dimensions, part)
        return sample_soft_mass(
            medial, medial.low, medial.high, tissue, step, label
        )
    if part == LATERAL_MENISCUS:
        var lateral = MeniscusField(dimensions, part)
        return sample_soft_mass(
            lateral, lateral.low, lateral.high, tissue, step, label
        )
    var ligament = CollateralField(dimensions, part)
    return sample_soft_mass(
        ligament, ligament.low, ligament.high, tissue, step, label
    )


def _tissue_of(part: KneePart) raises -> SoftTissue:
    """Return the template tissue for `part`.

    Args:
        part: A named knee part.

    Returns:
        Cartilage, meniscus or ligament tissue.

    Raises:
        Error: If `part` is not named.
    """
    if not part.is_valid():
        raise Error("A knee part must be cartilage, a meniscus or a collateral")
    if part == ARTICULAR_CARTILAGE:
        return cartilage_tissue()
    if part == MEDIAL_MENISCUS:
        return meniscus_tissue()
    if part == LATERAL_MENISCUS:
        return meniscus_tissue()
    return ligament_tissue()
