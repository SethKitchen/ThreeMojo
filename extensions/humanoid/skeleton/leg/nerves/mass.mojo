# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a nerve solid from its field and tissue.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = nerve_mass(person, SCIATIC_NERVE)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    MuscleDimensions,
    muscle_dimensions,
)
from extensions.humanoid.skeleton.leg.nerves.dimensions import (
    NerveField,
    NervePart,
    nerve_distance,
    nerve_part_label,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SOFT_STEP,
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    classify_soft,
    nerve_tissue,
    sample_soft_mass,
)
from math.vector3 import Vector3
from units.si import Length


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
    step: Length = SOFT_STEP,
) raises -> SoftMass:
    """Return the wet-tissue mass of one named nerve sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which solid to sample.
        side: `RIGHT` or `LEFT`. A right leg is the default.
        step: Grid cell size. 2 mm through 20 mm, 2 mm by default.

    Returns:
        Sampled envelope volume and wet-tissue mass.

    Raises:
        Error: If `spec`, `side` or `part` is refused, or `step` is out
            of range.
    """
    return nerve_mass_from_dimensions(
        muscle_dimensions(spec, side), part, nerve_tissue(), step
    )


def nerve_mass_from_dimensions(
    dimensions: MuscleDimensions,
    part: NervePart,
    tissue: SoftTissue,
    step: Length = SOFT_STEP,
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized nerve solid.

    Args:
        dimensions: Landmarks from `muscle_dimensions`.
        part: Which solid to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.
        step: Grid cell size.

    Returns:
        Sampled envelope volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, if `step` is out of range, or `tissue` fails
            `validate`.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A nerve part must be a named peripheral nerve")
    var label = nerve_part_label(part)
    var field = NerveField(dimensions, part)
    return sample_soft_mass(field, field.low, field.high, tissue, step, label)
