# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of the dermal shell around one arm.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = arm_skin_mass(person)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.skeleton.arm.frame import (
    ArmMuscleDimensions,
    arm_muscle_dimensions,
)
from extensions.humanoid.skeleton.arm.skin.dimensions import (
    ArmSkinLayerField,
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
from extensions.humanoid.spec import HumanoidSpec
from math.vector3 import Vector3
from units.si import Length


def arm_skin_occupancy(
    dimensions: ArmMuscleDimensions, side: BodySide, point: Vector3
) raises -> SoftOccupancy:
    """Return what fills `point` in one arm's dermal shell.

    Args:
        dimensions: Landmarks from `arm_muscle_dimensions`.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        `SOFT_FILL` in the dermis. Deep anatomy and exterior space are
        `SOFT_EMPTY`.

    Raises:
        Error: If `dimensions.validate` refuses the copy, or `side` is
            not valid.
    """
    return classify_soft(ArmSkinLayerField(dimensions, side).distance(point))


def arm_skin_mass(
    spec: HumanoidSpec, step: Length = SOFT_STEP
) raises -> SoftMass:
    """Return the wet-tissue mass of one arm's dermal shell.

    Args:
        spec: Standing height, osteological sex and athleticism.
        step: Grid cell size. 2 mm through 20 mm, 2 mm by default.

    Returns:
        Sampled dermal volume and wet-tissue mass.

    Raises:
        Error: If `spec` is refused, or `step` is out of range.
    """
    return arm_skin_mass_from_dimensions(
        arm_muscle_dimensions(spec), skin_tissue(), step
    )


def arm_skin_mass_from_dimensions(
    dimensions: ArmMuscleDimensions,
    tissue: SoftTissue,
    step: Length = SOFT_STEP,
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized dermal shell.

    A right arm's; the left is its mirror image.

    Args:
        dimensions: Landmarks from `arm_muscle_dimensions`.
        tissue: Hydrated tissue. Mass uses `wet_density` once.
        step: Grid cell size.

    Returns:
        Sampled dermal volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `step` is
            out of range, or `tissue` fails `validate`.
    """
    var field = ArmSkinLayerField(dimensions, RIGHT)
    return sample_soft_mass(
        field, field.low, field.high, tissue, step, "arm skin"
    )
