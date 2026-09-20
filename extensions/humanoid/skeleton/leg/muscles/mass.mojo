# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a muscle solid from its field and tissue.

The mesh is the outer surface. The interior is hydrated tissue. Mass is
wet density times envelope volume. Water fraction is metadata. It is not
applied again.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    var report = muscle_mass(person, RECTUS_FEMORIS)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    MuscleDimensions,
    MuscleField,
    MusclePart,
    is_tendon,
    muscle_dimensions,
    muscle_distance,
    muscle_part_label,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SOFT_STEP,
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    classify_soft,
    muscle_tissue,
    sample_soft_mass,
    tendon_tissue,
)
from math.vector3 import Vector3
from units.si import Length


def muscle_occupancy(
    dimensions: MuscleDimensions, part: MusclePart, point: Vector3
) raises -> SoftOccupancy:
    """Return what fills `point` in one muscle solid.

    Args:
        dimensions: Muscles already sized from stature, sex and athleticism.
        part: Which solid to sample.
        point: A point in the leg frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `part` is
            not named.
    """
    return classify_soft(muscle_distance(dimensions, part, point))


def muscle_mass(
    spec: HumanoidSpec,
    part: MusclePart,
    side: BodySide = RIGHT,
    step: Length = SOFT_STEP,
) raises -> SoftMass:
    """Return the wet-tissue mass of one named muscle sized for `spec`.

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
    return muscle_mass_from_dimensions(
        muscle_dimensions(spec, side), part, _tissue_of(part), step
    )


def muscle_mass_from_dimensions(
    dimensions: MuscleDimensions,
    part: MusclePart,
    tissue: SoftTissue,
    step: Length = SOFT_STEP,
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized muscle solid.

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
        raise Error("A muscle part must be a named muscle, tract or tendon")
    var label = muscle_part_label(part)
    var field = MuscleField(dimensions, part)
    return sample_soft_mass(field, field.low, field.high, tissue, step, label)


def _tissue_of(part: MusclePart) raises -> SoftTissue:
    """Return the template tissue for `part`.

    Args:
        part: A named muscle part.

    Returns:
        Muscle or tendon tissue.

    Raises:
        Error: If `part` is not named.
    """
    if is_tendon(part):
        return tendon_tissue()
    return muscle_tissue()
