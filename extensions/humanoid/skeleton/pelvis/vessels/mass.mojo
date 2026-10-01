# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a pelvic vessel from its physical tube.

Mass uses the analytic frustum volume of the physical radii, filled
with the vessel's wall and blood as one hydrated tissue. The display
minimum radius is not used.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = pelvis_vessel_mass(person, COMMON_ILIAC_ARTERY)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import tube_chain_volume
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    PelvisMuscleDimensions,
    pelvis_muscle_dimensions,
)
from extensions.humanoid.skeleton.pelvis.vessels.dimensions import (
    PelvisVessel,
    PelvisVesselField,
    is_pelvic_artery,
    pelvis_vessel_distance,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    classify_soft,
    vessel_tissue,
)
from math.vector3 import Vector3
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


def pelvis_vessel_occupancy(
    dimensions: PelvisMuscleDimensions,
    part: PelvisVessel,
    side: BodySide,
    point: Vector3,
) raises -> SoftOccupancy:
    """Return what fills `point` in one pelvic vessel.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        part: Which vessel to sample.
        side: `RIGHT` or `LEFT`. An unpaired vessel ignores it.
        point: A point in the pelvis frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return classify_soft(pelvis_vessel_distance(dimensions, part, side, point))


def pelvis_vessel_mass(
    spec: HumanoidSpec, part: PelvisVessel
) raises -> SoftMass:
    """Return the wet-tissue mass of one pelvic vessel sized for `spec`.

    A paired vessel is one side's.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which vessel to sample.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `spec` or `part` is refused.
    """
    var tissue = vessel_tissue(is_pelvic_artery(part))
    return pelvis_vessel_mass_from_dimensions(
        pelvis_muscle_dimensions(spec), part, tissue
    )


def pelvis_vessel_mass_from_dimensions(
    dimensions: PelvisMuscleDimensions, part: PelvisVessel, tissue: SoftTissue
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized pelvic vessel.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        part: Which vessel to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    tissue.validate()
    var volume = tube_chain_volume(
        PelvisVesselField(dimensions, part, RIGHT).chain
    )
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
