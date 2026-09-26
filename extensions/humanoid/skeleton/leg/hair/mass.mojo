# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a hair group from its field and tissue.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = hair_mass(person, THIGH_HAIR)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.hair.dimensions import (
    HairField,
    HairPart,
    hair_distance,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    MuscleDimensions,
    muscle_dimensions,
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


def hair_occupancy(
    dimensions: MuscleDimensions, part: HairPart, point: Vector3
) raises -> SoftOccupancy:
    """Return what fills `point` in one hair group.

    Args:
        dimensions: Landmarks from `muscle_dimensions`.
        part: Which solid to sample.
        point: A point in the leg frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return classify_soft(hair_distance(dimensions, part, point))


def hair_mass(
    spec: HumanoidSpec,
    part: HairPart,
    side: BodySide = RIGHT,
) raises -> SoftMass:
    """Return the wet-tissue mass of one named hair group sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which solid to sample.
        side: `RIGHT` or `LEFT`. A right leg is the default.

    Returns:
        Analytic capsule volume and wet-tissue mass.

    Raises:
        Error: If `spec`, `side` or `part` is refused.
    """
    return hair_mass_from_dimensions(
        muscle_dimensions(spec, side), part, hair_tissue()
    )


def hair_mass_from_dimensions(
    dimensions: MuscleDimensions,
    part: HairPart,
    tissue: SoftTissue,
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized hair group.

    Args:
        dimensions: Landmarks from `muscle_dimensions`.
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
        raise Error("A hair part must be a named hair group")
    tissue.validate()
    var field = HairField(dimensions, part)
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
