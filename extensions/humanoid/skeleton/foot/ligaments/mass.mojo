# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a foot ligament from its physical bands.

Mass uses analytic frustum volume. Water fraction is metadata. It is
not applied again.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = ligament_mass(person, DELTOID)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    FootDimensions,
    foot_dimensions,
)
from extensions.humanoid.skeleton.foot.chain import segment_volume
from extensions.humanoid.skeleton.foot.ligaments.dimensions import (
    FootLigament,
    FootLigamentField,
    ligament_distance,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    classify_soft,
    ligament_tissue,
)
from math.vector3 import Vector3
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


def ligament_occupancy(
    dimensions: FootDimensions, part: FootLigament, point: Vector3
) raises -> SoftOccupancy:
    """Return what fills `point` in one ligament.

    Args:
        dimensions: Landmarks from `foot_dimensions`.
        part: Which ligament to sample.
        point: A point in the foot frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return classify_soft(ligament_distance(dimensions, part, point))


def ligament_mass(
    spec: HumanoidSpec, part: FootLigament, side: BodySide = RIGHT
) raises -> SoftMass:
    """Return the wet-tissue mass of one ligament sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        part: Which ligament to sample.
        side: `RIGHT` or `LEFT`. A right foot is the default.

    Returns:
        Analytic envelope volume and wet-tissue mass.

    Raises:
        Error: If `spec`, `side` or `part` is refused.
    """
    return ligament_mass_from_dimensions(
        foot_dimensions(spec.stature, spec.sex, side),
        part,
        ligament_tissue(),
    )


def ligament_mass_from_dimensions(
    dimensions: FootDimensions, part: FootLigament, tissue: SoftTissue
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized ligament.

    Args:
        dimensions: Landmarks from `foot_dimensions`.
        part: Which ligament to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic envelope volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A foot ligament must be a named ligament")
    tissue.validate()
    var field = FootLigamentField(dimensions, part)
    var volume = segment_volume(field.segments)
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
