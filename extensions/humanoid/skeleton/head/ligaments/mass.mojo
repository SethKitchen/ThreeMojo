# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a head joint tissue or cartilage from its physical solid.

Mass uses analytic volume and the part's own tissue. A paired part is
one side's. The display minimum radius is not used.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = head_ligament_mass(person, LARYNX)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.soft_tissue import (
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    classify_soft,
)
from extensions.humanoid.skeleton.head.frame import (
    HeadDimensions,
    head_dimensions,
)
from extensions.humanoid.skeleton.head.ligaments.dimensions import (
    HeadLigament,
    head_ligament_distance,
    head_ligament_field,
    head_ligament_tissue,
)
from math.vector3 import Vector3
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


def head_ligament_occupancy(
    dimensions: HeadDimensions,
    part: HeadLigament,
    side: BodySide,
    point: Vector3,
) raises -> SoftOccupancy:
    """Return what fills `point` in one head joint tissue or cartilage.

    Args:
        dimensions: Landmarks from `head_dimensions`.
        part: Which part to sample.
        side: `RIGHT` or `LEFT`. A midline part ignores it.
        point: A point in the pelvis frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return classify_soft(head_ligament_distance(dimensions, part, side, point))


def head_ligament_mass(
    spec: HumanoidSpec, part: HeadLigament
) raises -> SoftMass:
    """Return the wet-tissue mass of one head joint tissue or cartilage sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which part to sample.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `spec` or `part` is refused.
    """
    return head_ligament_mass_from_dimensions(
        head_dimensions(spec.stature, spec.sex, spec.genome),
        part,
        head_ligament_tissue(part),
    )


def head_ligament_mass_from_dimensions(
    dimensions: HeadDimensions, part: HeadLigament, tissue: SoftTissue
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized head joint tissue or cartilage.

    Args:
        dimensions: Landmarks from `head_dimensions`.
        part: Which part to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    tissue.validate()
    var volume = head_ligament_field(dimensions, part, RIGHT).volume()
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
