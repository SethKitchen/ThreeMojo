# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a foot nerve from its physical centerline.

Mass uses analytic tube volume. Display radius does not change mass.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = foot_nerve_mass(person, TIBIAL_NERVE)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    FootDimensions,
    foot_dimensions,
)
from extensions.humanoid.skeleton.foot.chain import tube_set_volume
from extensions.humanoid.skeleton.foot.nerves.dimensions import (
    FootNerve,
    FootNerveField,
    nerve_distance,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    classify_soft,
    nerve_tissue,
)
from math.vector3 import Vector3
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


def foot_nerve_occupancy(
    dimensions: FootDimensions, part: FootNerve, point: Vector3
) raises -> SoftOccupancy:
    """Return what fills `point` in one foot nerve.

    Args:
        dimensions: Landmarks from `foot_dimensions`.
        part: Which nerve to sample.
        point: A point in the foot frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return classify_soft(nerve_distance(dimensions, part, point))


def foot_nerve_mass(
    spec: HumanoidSpec, part: FootNerve, side: BodySide = RIGHT
) raises -> SoftMass:
    """Return the wet-tissue mass of one foot nerve sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        part: Which nerve to sample.
        side: `RIGHT` or `LEFT`. A right foot is the default.

    Returns:
        Analytic envelope volume and wet-tissue mass.

    Raises:
        Error: If `spec`, `side` or `part` is refused.
    """
    return foot_nerve_mass_from_dimensions(
        foot_dimensions(spec.stature, spec.sex, side), part, nerve_tissue()
    )


def foot_nerve_mass_from_dimensions(
    dimensions: FootDimensions, part: FootNerve, tissue: SoftTissue
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized foot nerve.

    Args:
        dimensions: Landmarks from `foot_dimensions`.
        part: Which nerve to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic envelope volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A foot nerve must be a named nerve")
    tissue.validate()
    var field = FootNerveField(dimensions, part)
    var volume = tube_set_volume(field.tubes)
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
