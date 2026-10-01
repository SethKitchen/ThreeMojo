# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a pelvic muscle from its elliptical chains.

Mass uses analytic frustum volume, the same on either side. Water
fraction is metadata. It is not applied again.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    var report = pelvis_muscle_mass(person, ILIACUS)
"""

from extensions.humanoid.side import BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.side import RIGHT
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    PelvisMuscle,
    PelvisMuscleDimensions,
    PelvisMuscleField,
    chain_set_volume,
    pelvis_muscle_dimensions,
    pelvis_muscle_distance,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    classify_soft,
    muscle_tissue,
)
from math.vector3 import Vector3
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


def pelvis_muscle_occupancy(
    dimensions: PelvisMuscleDimensions,
    part: PelvisMuscle,
    side: BodySide,
    point: Vector3,
) raises -> SoftOccupancy:
    """Return what fills `point` in one pelvic muscle.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        part: Which muscle to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return classify_soft(pelvis_muscle_distance(dimensions, part, side, point))


def pelvis_muscle_mass(
    spec: HumanoidSpec, part: PelvisMuscle
) raises -> SoftMass:
    """Return the wet-tissue mass of one pelvic muscle sized for `spec`.

    The muscle is one side's. The other side's is the same.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which muscle to sample.

    Returns:
        Analytic envelope volume and wet-tissue mass.

    Raises:
        Error: If `spec` or `part` is refused.
    """
    return pelvis_muscle_mass_from_dimensions(
        pelvis_muscle_dimensions(spec), part, muscle_tissue()
    )


def pelvis_muscle_mass_from_dimensions(
    dimensions: PelvisMuscleDimensions, part: PelvisMuscle, tissue: SoftTissue
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized pelvic muscle.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        part: Which muscle to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic envelope volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    tissue.validate()
    var field = PelvisMuscleField(dimensions, part, RIGHT)
    var volume = chain_set_volume(field.chains)
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
