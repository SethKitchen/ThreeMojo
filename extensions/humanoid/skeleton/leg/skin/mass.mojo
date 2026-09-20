# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of the skin envelope from its field and tissue.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = skin_mass(person)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    MuscleDimensions,
    muscle_dimensions,
)
from extensions.humanoid.skeleton.leg.skin.dimensions import (
    SkinField,
    skin_distance,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SOFT_STEP,
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    classify_soft,
    sample_soft_mass,
    skin_tissue,
)
from math.vector3 import Vector3
from units.si import Length


def skin_occupancy(
    dimensions: MuscleDimensions, point: Vector3
) raises -> SoftOccupancy:
    """Return what fills `point` in the skin envelope.

    Args:
        dimensions: Landmarks from `muscle_dimensions`.
        point: A point in the leg frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    return classify_soft(skin_distance(dimensions, point))


def skin_mass(
    spec: HumanoidSpec, side: BodySide = RIGHT, step: Length = SOFT_STEP
) raises -> SoftMass:
    """Return the wet-tissue mass of the skin envelope sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        side: `RIGHT` or `LEFT`. A right leg is the default.
        step: Grid cell size. 2 mm through 20 mm, 2 mm by default.

    Returns:
        Sampled envelope volume and wet-tissue mass.

    Raises:
        Error: If `spec` or `side` is refused, or `step` is out of range.
    """
    return skin_mass_from_dimensions(
        muscle_dimensions(spec, side), skin_tissue(), step
    )


def skin_mass_from_dimensions(
    dimensions: MuscleDimensions,
    tissue: SoftTissue,
    step: Length = SOFT_STEP,
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized skin envelope.

    Args:
        dimensions: Landmarks from `muscle_dimensions`.
        tissue: Hydrated tissue. Mass uses `wet_density` once.
        step: Grid cell size.

    Returns:
        Sampled envelope volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `step` is
            out of range, or `tissue` fails `validate`.
    """
    dimensions.validate()
    var field = SkinField(dimensions)
    return sample_soft_mass(field, field.low, field.high, tissue, step, "skin")
