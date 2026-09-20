# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass from a nerve's physical centerline and radii.

Mass uses analytic tapered-tube volume. The display mesh can enlarge a
small radius without changing mass.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = nerve_mass(person, SCIATIC_NERVE)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import tube_chain_volume
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    MuscleDimensions,
    muscle_dimensions,
)
from extensions.humanoid.skeleton.leg.nerves.dimensions import (
    NerveField,
    NervePart,
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


def nerve_occupancy(
    dimensions: MuscleDimensions, part: NervePart, point: Vector3
) raises -> SoftOccupancy:
    """Return what fills `point` in one nerve solid.

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
    return classify_soft(nerve_distance(dimensions, part, point))


def nerve_mass(
    spec: HumanoidSpec,
    part: NervePart,
    side: BodySide = RIGHT,
) raises -> SoftMass:
    """Return the wet-tissue mass of one named nerve sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which solid to sample.
        side: `RIGHT` or `LEFT`. A right leg is the default.

    Returns:
        Analytic tube volume and wet-tissue mass.

    Raises:
        Error: If `spec`, `side` or `part` is refused.
    """
    return nerve_mass_from_dimensions(
        muscle_dimensions(spec, side), part, nerve_tissue()
    )


def nerve_mass_from_dimensions(
    dimensions: MuscleDimensions,
    part: NervePart,
    tissue: SoftTissue,
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized nerve solid.

    Args:
        dimensions: Landmarks from `muscle_dimensions`.
        part: Which solid to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic tube volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A nerve part must be a named peripheral nerve")
    tissue.validate()
    var field = NerveField(dimensions, part)
    var volume = tube_chain_volume(field.chain)
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
