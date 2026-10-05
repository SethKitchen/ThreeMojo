# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a hand muscle from its physical solid.

Mass uses analytic volume and the part's own tissue. A paired part is
one side's. The display minimum radius is not used.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = hand_muscle_mass(person, ADDUCTOR_POLLICIS)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.arm.frame import (
    ArmMuscleDimensions,
    arm_muscle_dimensions,
)
from extensions.humanoid.skeleton.hand.muscles.dimensions import (
    HandMuscle,
    is_hand_tendon,
    hand_muscle_distance,
    hand_muscle_field,
)
from extensions.anatomy.soft_tissue import (
    SoftMass,
    SoftTissue,
    muscle_tissue,
    tendon_tissue,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftOccupancy,
    classify_soft,
)
from extensions.humanoid.spec import HumanoidSpec
from math.vector3 import Vector3
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


def hand_muscle_occupancy(
    dimensions: ArmMuscleDimensions,
    part: HandMuscle,
    side: BodySide,
    point: Vector3,
) raises -> SoftOccupancy:
    """Return what fills `point` in one hand muscle.

    Args:
        dimensions: Landmarks from `arm_muscle_dimensions`.
        part: Which part to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return classify_soft(hand_muscle_distance(dimensions, part, side, point))


def hand_muscle_mass(spec: HumanoidSpec, part: HandMuscle) raises -> SoftMass:
    """Return the wet-tissue mass of one hand muscle sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which part to sample.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `spec` or `part` is refused.
    """
    return hand_muscle_mass_from_dimensions(
        arm_muscle_dimensions(spec), part, hand_muscle_tissue(part)
    )


def hand_muscle_tissue(part: HandMuscle) raises -> SoftTissue:
    """Return the tissue `part` is made of.

    Args:
        part: A named part.

    Returns:
        Tendon for the long tendons, muscle for the hand's own muscles.

    Raises:
        Error: If `part` is not named.
    """
    if is_hand_tendon(part):
        return tendon_tissue()
    return muscle_tissue()


def hand_muscle_mass_from_dimensions(
    dimensions: ArmMuscleDimensions, part: HandMuscle, tissue: SoftTissue
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized hand muscle.

    Args:
        dimensions: Landmarks from `arm_muscle_dimensions`.
        part: Which part to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    tissue.validate()
    var volume = hand_muscle_field(dimensions, part, RIGHT).volume()
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
