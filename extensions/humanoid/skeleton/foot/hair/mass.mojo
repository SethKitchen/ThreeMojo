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
    FootHairField,
    foot_hair_distance,
)
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    FootMuscleDimensions,
    foot_muscle_dimensions,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    classify_soft,
    hair_tissue,
)
from math.vector3 import Vector3
from std.math import pi
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


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
    if not part.is_valid():
        raise Error("A foot hair part must be a named hair group")
    tissue.validate()
    var field = FootHairField(dimensions, part)
    var length = (field.b0 - field.a0).length()
    length += (field.b1 - field.a1).length()
    length += (field.b2 - field.a2).length()
    length += (field.b3 - field.a3).length()
    length += (field.b4 - field.a4).length()
    length += (field.b5 - field.a5).length()
    var radius = field.radius
    var volume = (
        pi * radius * radius * length
        + Float32(6) * Float32(4.0 / 3.0) * pi * radius * radius * radius
    )
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
