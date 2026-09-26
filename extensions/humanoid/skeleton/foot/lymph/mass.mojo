# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a foot lymphatic trunk from its physical radius.

Mass uses analytic tube volume. Display radius does not change mass.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = foot_lymph_mass(person, DORSAL_LYMPHATICS)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    FootDimensions,
    foot_dimensions,
)
from extensions.humanoid.skeleton.foot.chain import tube_set_volume
from extensions.humanoid.skeleton.foot.lymph.dimensions import (
    FootLymph,
    FootLymphField,
    lymph_distance,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    classify_soft,
    lymph_tissue,
)
from math.vector3 import Vector3
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


def foot_lymph_occupancy(
    dimensions: FootDimensions, part: FootLymph, point: Vector3
) raises -> SoftOccupancy:
    """Return what fills `point` in one lymphatic trunk.

    Args:
        dimensions: Landmarks from `foot_dimensions`.
        part: Which trunk to sample.
        point: A point in the foot frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return classify_soft(lymph_distance(dimensions, part, point))


def foot_lymph_mass(
    spec: HumanoidSpec, part: FootLymph, side: BodySide = RIGHT
) raises -> SoftMass:
    """Return the wet-tissue mass of one lymphatic trunk sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        part: Which trunk to sample.
        side: `RIGHT` or `LEFT`. A right foot is the default.

    Returns:
        Analytic envelope volume and wet-tissue mass.

    Raises:
        Error: If `spec`, `side` or `part` is refused.
    """
    return foot_lymph_mass_from_dimensions(
        foot_dimensions(spec.stature, spec.sex, side), part, lymph_tissue()
    )


def foot_lymph_mass_from_dimensions(
    dimensions: FootDimensions, part: FootLymph, tissue: SoftTissue
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized lymphatic trunk.

    Args:
        dimensions: Landmarks from `foot_dimensions`.
        part: Which trunk to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic envelope volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A foot lymph part must be a named trunk")
    tissue.validate()
    var field = FootLymphField(dimensions, part)
    var volume = tube_set_volume(field.tubes)
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
