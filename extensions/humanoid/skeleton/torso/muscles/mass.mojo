# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a torso muscle from its physical solid.

Mass uses analytic volume and the part's own tissue. A paired part is
one side's. The display minimum radius is not used.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = torso_muscle_mass(person, ERECTOR_SPINAE)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.soft_tissue import (
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    classify_soft,
    muscle_tissue,
)
from extensions.humanoid.skeleton.torso.muscles.dimensions import (
    TorsoMuscleDimensions,
    torso_muscle_dimensions,
)
from extensions.humanoid.skeleton.torso.muscles.dimensions import (
    TorsoMuscle,
    torso_muscle_distance,
    torso_muscle_field,
)
from math.vector3 import Vector3
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


def torso_muscle_occupancy(
    dimensions: TorsoMuscleDimensions,
    part: TorsoMuscle,
    side: BodySide,
    point: Vector3,
) raises -> SoftOccupancy:
    """Return what fills `point` in one torso muscle.

    Args:
        dimensions: Landmarks from `torso_muscle_dimensions`.
        part: Which part to sample.
        side: `RIGHT` or `LEFT`. The diaphragm ignores it.
        point: A point in the pelvis frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return classify_soft(torso_muscle_distance(dimensions, part, side, point))


def torso_muscle_mass(spec: HumanoidSpec, part: TorsoMuscle) raises -> SoftMass:
    """Return the wet-tissue mass of one torso muscle sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which part to sample.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `spec` or `part` is refused.
    """
    return torso_muscle_mass_from_dimensions(
        torso_muscle_dimensions(spec), part, muscle_tissue()
    )


def torso_muscle_mass_from_dimensions(
    dimensions: TorsoMuscleDimensions, part: TorsoMuscle, tissue: SoftTissue
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized torso muscle.

    Args:
        dimensions: Landmarks from `torso_muscle_dimensions`.
        part: Which part to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    tissue.validate()
    var volume = torso_muscle_field(dimensions, part, RIGHT).volume()
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
