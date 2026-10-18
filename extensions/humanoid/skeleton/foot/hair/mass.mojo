# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a foot hair group from its physical shafts.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = foot_hair_mass(person, DORSAL_HAIR)

Mass uses the physical radius. The display mesh does not.
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.foot.hair.dimensions import (
    FootHair,
    require_foot_hair,
    FootHairField,
    foot_hair_distance,
)
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    FootMuscleDimensions,
    foot_muscle_dimensions,
)
from extensions.anatomy.soft_tissue import (
    analytic_soft_mass,
    SoftMass,
    SoftTissue,
    hair_tissue,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftOccupancy,
    classify_soft,
    six_capsule_volume,
    six_segment_length,
)
from math.vector3 import Vector3


def foot_hair_occupancy(
    dimensions: FootMuscleDimensions, part: FootHair, point: Vector3
) raises -> SoftOccupancy:
    """Return what fills `point` in one hair group.

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
    return classify_soft(foot_hair_distance(dimensions, part, point))


def foot_hair_mass(
    spec: HumanoidSpec,
    part: FootHair,
    side: BodySide = RIGHT,
) raises -> SoftMass:
    """Return the wet-tissue mass of one named hair group sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which solid to sample.
        side: `RIGHT` or `LEFT`. A right foot is the default.

    Returns:
        Analytic capsule volume and wet-tissue mass.

    Raises:
        Error: If `spec`, `side` or `part` is refused.
    """
    return foot_hair_mass_from_dimensions(
        foot_muscle_dimensions(spec, side), part, hair_tissue()
    )


def foot_hair_mass_from_dimensions(
    dimensions: FootMuscleDimensions,
    part: FootHair,
    tissue: SoftTissue,
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized hair group.

    Args:
        dimensions: Landmarks from `foot_muscle_dimensions`.
        part: Which solid to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic capsule volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    dimensions.validate()
    require_foot_hair(part)
    tissue.validate()
    var field = FootHairField(dimensions, part)
    var length = six_segment_length(
        field.a0,
        field.b0,
        field.a1,
        field.b1,
        field.a2,
        field.b2,
        field.a3,
        field.b3,
        field.a4,
        field.b4,
        field.a5,
        field.b5,
    )
    return analytic_soft_mass(tissue, six_capsule_volume(field.radius, length))
