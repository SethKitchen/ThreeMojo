# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a torso joint tissue or ligament from its physical solid.

Mass uses analytic volume and the part's own tissue. A paired part is
one side's. The display minimum radius is not used.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = torso_ligament_mass(person, COSTAL_CARTILAGES)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.soft_tissue import (
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    classify_soft,
)
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    TorsoDimensions,
    torso_dimensions,
)
from extensions.humanoid.skeleton.torso.ligaments.dimensions import (
    TorsoLigament,
    torso_ligament_distance,
    torso_ligament_field,
    torso_ligament_tissue,
)
from math.vector3 import Vector3
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


def torso_ligament_occupancy(
    dimensions: TorsoDimensions,
    part: TorsoLigament,
    side: BodySide,
    point: Vector3,
) raises -> SoftOccupancy:
    """Return what fills `point` in one torso joint tissue or ligament.

    Args:
        dimensions: Landmarks from `torso_dimensions`.
        part: Which part to sample.
        side: `RIGHT` or `LEFT`. A midline part ignores it.
        point: A point in the pelvis frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return classify_soft(torso_ligament_distance(dimensions, part, side, point))


def torso_ligament_mass(
    spec: HumanoidSpec, part: TorsoLigament
) raises -> SoftMass:
    """Return the wet-tissue mass of one torso joint tissue or ligament sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which part to sample.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `spec` or `part` is refused.
    """
    return torso_ligament_mass_from_dimensions(
        torso_dimensions(spec.stature, spec.sex, spec.genome),
        part,
        torso_ligament_tissue(part),
    )


def torso_ligament_mass_from_dimensions(
    dimensions: TorsoDimensions, part: TorsoLigament, tissue: SoftTissue
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized torso joint tissue or ligament.

    Args:
        dimensions: Landmarks from `torso_dimensions`.
        part: Which part to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    tissue.validate()
    var volume = torso_ligament_field(dimensions, part, RIGHT).volume()
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
