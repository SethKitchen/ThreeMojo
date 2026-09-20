# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a vessel solid from its field and tissue.

The mesh is the outer surface. The interior is a blood-filled tube. Mass
is wet density times envelope volume. Water fraction is metadata.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = vessel_mass(person, FEMORAL_ARTERY)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    MuscleDimensions,
    muscle_dimensions,
)
from extensions.humanoid.skeleton.leg.vessels.dimensions import (
    VesselField,
    VesselPart,
    is_artery,
    vessel_distance,
    vessel_part_label,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SOFT_STEP,
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    arterial_tissue,
    classify_soft,
    sample_soft_mass,
    venous_tissue,
)
from math.vector3 import Vector3
from units.si import Length


def vessel_occupancy(
    dimensions: MuscleDimensions, part: VesselPart, point: Vector3
) raises -> SoftOccupancy:
    """Return what fills `point` in one vessel solid.

    Args:
        dimensions: Landmarks from `muscle_dimensions`.
        part: Which solid to sample.
        point: A point in the leg frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return classify_soft(vessel_distance(dimensions, part, point))


def vessel_mass(
    spec: HumanoidSpec,
    part: VesselPart,
    side: BodySide = RIGHT,
    step: Length = SOFT_STEP,
) raises -> SoftMass:
    """Return the wet-tissue mass of one named vessel sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which solid to sample.
        side: `RIGHT` or `LEFT`. A right leg is the default.
        step: Grid cell size. 2 mm through 20 mm, 2 mm by default.

    Returns:
        Sampled envelope volume and wet-tissue mass.

    Raises:
        Error: If `spec`, `side` or `part` is refused, or `step` is out
            of range.
    """
    return vessel_mass_from_dimensions(
        muscle_dimensions(spec, side), part, _tissue_of(part), step
    )


def vessel_mass_from_dimensions(
    dimensions: MuscleDimensions,
    part: VesselPart,
    tissue: SoftTissue,
    step: Length = SOFT_STEP,
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized vessel solid.

    Args:
        dimensions: Landmarks from `muscle_dimensions`.
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
        raise Error("A vessel part must be a named artery or vein")
    var label = vessel_part_label(part)
    var field = VesselField(dimensions, part)
    return sample_soft_mass(field, field.low, field.high, tissue, step, label)


def _tissue_of(part: VesselPart) raises -> SoftTissue:
    """Return the template tissue for `part`.

    Args:
        part: A named vessel.

    Returns:
        Arterial or venous tissue.

    Raises:
        Error: If `part` is not named.
    """
    if is_artery(part):
        return arterial_tissue()
    return venous_tissue()
