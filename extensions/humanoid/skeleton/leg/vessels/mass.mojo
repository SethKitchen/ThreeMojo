# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a vessel from its physical centerline and radii.

Mass uses analytic tapered-tube volume. The display mesh can enlarge a
small radius without changing mass. Water fraction is metadata.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = vessel_mass(person, FEMORAL_ARTERY)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import tube_chain_volume
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    MuscleDimensions,
    muscle_dimensions,
)
from extensions.humanoid.skeleton.leg.vessels.dimensions import (
    VesselField,
    VesselPart,
    is_artery,
    vessel_distance,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    arterial_tissue,
    classify_soft,
    venous_tissue,
)
from math.vector3 import Vector3
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


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
) raises -> SoftMass:
    """Return the wet-tissue mass of one named vessel sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which solid to sample.
        side: `RIGHT` or `LEFT`. A right leg is the default.

    Returns:
        Analytic tube volume and wet-tissue mass.

    Raises:
        Error: If `spec`, `side` or `part` is refused.
    """
    return vessel_mass_from_dimensions(
        muscle_dimensions(spec, side), part, _tissue_of(part)
    )


def vessel_mass_from_dimensions(
    dimensions: MuscleDimensions,
    part: VesselPart,
    tissue: SoftTissue,
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized vessel solid.

    Args:
        dimensions: Landmarks from `muscle_dimensions`.
        part: Which solid to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic tube volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A vessel part must be a named artery or vein")
    tissue.validate()
    var field = VesselField(dimensions, part)
    var volume = tube_chain_volume(field.chain)
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )


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
