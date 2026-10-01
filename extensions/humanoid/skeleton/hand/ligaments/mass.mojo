# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a hand joint tissue or ligament from its physical solid.

Mass uses analytic volume and the part's own tissue. A paired part is
one side's. The display minimum radius is not used.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = hand_ligament_mass(person, FLEXOR_RETINACULUM)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.arm.frame import (
    ArmDimensions,
    arm_dimensions,
)
from extensions.humanoid.skeleton.hand.ligaments.dimensions import (
    HandLigament,
    hand_ligament_distance,
    hand_ligament_field,
    hand_ligament_tissue,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    classify_soft,
)
from extensions.humanoid.spec import HumanoidSpec
from math.vector3 import Vector3
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


def hand_ligament_occupancy(
    dimensions: ArmDimensions,
    part: HandLigament,
    side: BodySide,
    point: Vector3,
) raises -> SoftOccupancy:
    """Return what fills `point` in one hand joint tissue or ligament.

    Args:
        dimensions: Landmarks from `arm_dimensions`.
        part: Which part to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return classify_soft(hand_ligament_distance(dimensions, part, side, point))


def hand_ligament_mass(
    spec: HumanoidSpec, part: HandLigament
) raises -> SoftMass:
    """Return the wet-tissue mass of one hand joint tissue or ligament sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which part to sample.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `spec` or `part` is refused.
    """
    return hand_ligament_mass_from_dimensions(
        arm_dimensions(spec.stature, spec.sex, spec.genome),
        part,
        hand_ligament_tissue(part),
    )


def hand_ligament_mass_from_dimensions(
    dimensions: ArmDimensions, part: HandLigament, tissue: SoftTissue
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized hand joint tissue or ligament.

    Args:
        dimensions: Landmarks from `arm_dimensions`.
        part: Which part to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    tissue.validate()
    var volume = hand_ligament_field(dimensions, part, RIGHT).volume()
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
