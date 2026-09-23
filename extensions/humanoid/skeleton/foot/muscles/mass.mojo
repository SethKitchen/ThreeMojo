# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a foot muscle from its physical tubes.

Mass uses analytic tube volume and the physical radii. A tendon mesh
can enlarge those radii. That enlargement does not change mass.
Water fraction is metadata.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    var report = foot_muscle_mass(person, ABDUCTOR_HALLUCIS)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.foot.chain import tube_set_volume
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    FootMuscle,
    FootMuscleDimensions,
    FootMuscleField,
    foot_muscle_dimensions,
    foot_muscle_distance,
    is_tendon,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    classify_soft,
    muscle_tissue,
    tendon_tissue,
)
from math.vector3 import Vector3
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


def foot_muscle_occupancy(
    dimensions: FootMuscleDimensions, part: FootMuscle, point: Vector3
) raises -> SoftOccupancy:
    """Return what fills `point` in one foot muscle.

    Args:
        dimensions: Landmarks from `foot_muscle_dimensions`.
        part: Which solid to sample.
        point: A point in the foot frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return classify_soft(foot_muscle_distance(dimensions, part, point))


def foot_muscle_mass(
    spec: HumanoidSpec,
    part: FootMuscle,
    side: BodySide = RIGHT,
) raises -> SoftMass:
    """Return the wet-tissue mass of one foot muscle sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which solid to sample.
        side: `RIGHT` or `LEFT`. A right foot is the default.

    Returns:
        Analytic envelope volume and wet-tissue mass.

    Raises:
        Error: If `spec`, `side` or `part` is refused.
    """
    var tissue = muscle_tissue()
    if is_tendon(part):
        tissue = tendon_tissue()
    return foot_muscle_mass_from_dimensions(
        foot_muscle_dimensions(spec, side), part, tissue
    )


def foot_muscle_mass_from_dimensions(
    dimensions: FootMuscleDimensions, part: FootMuscle, tissue: SoftTissue
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized foot muscle.

    Args:
        dimensions: Landmarks from `foot_muscle_dimensions`.
        part: Which solid to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic envelope volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A foot muscle must be a named muscle or tendon")
    tissue.validate()
    var field = FootMuscleField(dimensions, part)
    var volume = tube_set_volume(field.tubes)
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
