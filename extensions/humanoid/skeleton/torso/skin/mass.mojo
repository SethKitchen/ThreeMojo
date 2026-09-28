# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of the dermal shell around the torso.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = torso_skin_mass(person)
"""

from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.torso.muscles.dimensions import (
    TorsoMuscleDimensions,
    torso_muscle_dimensions,
)
from extensions.humanoid.skeleton.torso.skin.dimensions import (
    TorsoSkinLayerField,
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


def torso_skin_occupancy(
    dimensions: TorsoMuscleDimensions, point: Vector3
) raises -> SoftOccupancy:
    """Return what fills `point` in the torso's dermal shell.

    Args:
        dimensions: Landmarks from `torso_muscle_dimensions`.
        point: A point in the pelvis frame, in meters.

    Returns:
        `SOFT_FILL` in the dermis. Deep anatomy and exterior space are
        `SOFT_EMPTY`.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    return classify_soft(TorsoSkinLayerField(dimensions).distance(point))


def torso_skin_mass(
    spec: HumanoidSpec, step: Length = SOFT_STEP
) raises -> SoftMass:
    """Return the wet-tissue mass of the torso's dermal shell.

    Args:
        spec: Standing height, osteological sex and athleticism.
        step: Grid cell size. 2 mm through 20 mm, 2 mm by default.

    Returns:
        Sampled dermal volume and wet-tissue mass.

    Raises:
        Error: If `spec` is refused, or `step` is out of range.
    """
    return torso_skin_mass_from_dimensions(
        torso_muscle_dimensions(spec), skin_tissue(), step
    )


def torso_skin_mass_from_dimensions(
    dimensions: TorsoMuscleDimensions,
    tissue: SoftTissue,
    step: Length = SOFT_STEP,
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized dermal shell.

    Args:
        dimensions: Landmarks from `torso_muscle_dimensions`.
        tissue: Hydrated tissue. Mass uses `wet_density` once.
        step: Grid cell size.

    Returns:
        Sampled dermal volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `step` is
            out of range, or `tissue` fails `validate`.
    """
    var field = TorsoSkinLayerField(dimensions)
    return sample_soft_mass(
        field, field.low, field.high, tissue, step, "torso skin"
    )
