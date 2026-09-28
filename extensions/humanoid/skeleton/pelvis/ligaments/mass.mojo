# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a pelvic ligament or joint tissue.

Mass uses analytic volume and the part's own tissue: ligament for the
bands, hyaline cartilage for the socket's lining, and fibrocartilage
for the labrum and the interpubic disc.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = pelvis_ligament_mass(person, SACROTUBEROUS)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.pelvis.ligaments.dimensions import (
    PelvisLigament,
    PelvisLigamentField,
    pelvis_ligament_distance,
    pelvis_ligament_tissue,
)
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    PelvisMuscleDimensions,
    pelvis_muscle_dimensions,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    classify_soft,
)
from math.vector3 import Vector3
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


def pelvis_ligament_occupancy(
    dimensions: PelvisMuscleDimensions,
    part: PelvisLigament,
    side: BodySide,
    point: Vector3,
) raises -> SoftOccupancy:
    """Return what fills `point` in one pelvic ligament or joint tissue.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        part: Which part to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return classify_soft(
        pelvis_ligament_distance(dimensions, part, side, point)
    )


def pelvis_ligament_mass(
    spec: HumanoidSpec, part: PelvisLigament
) raises -> SoftMass:
    """Return the wet-tissue mass of one pelvic part sized for `spec`.

    A paired part is one side's.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which part to sample.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `spec` or `part` is refused.
    """
    return pelvis_ligament_mass_from_dimensions(
        pelvis_muscle_dimensions(spec), part, pelvis_ligament_tissue(part)
    )


def pelvis_ligament_mass_from_dimensions(
    dimensions: PelvisMuscleDimensions,
    part: PelvisLigament,
    tissue: SoftTissue,
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized pelvic part.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        part: Which part to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    tissue.validate()
    var volume = PelvisLigamentField(dimensions, part, RIGHT).volume()
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
