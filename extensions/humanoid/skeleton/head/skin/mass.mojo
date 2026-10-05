# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of the neck's and the head's dermal shell.

Mass samples the dermis just inside the outer skin surface. The fat
under it is not counted.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = head_skin_mass(person)
"""

from extensions.humanoid.skeleton.head.frame import (
    HeadMuscleDimensions,
    head_muscle_dimensions,
)
from extensions.humanoid.skeleton.head.skin.dimensions import (
    HeadSkinLayerField,
)
from extensions.anatomy.soft_tissue import (
    SoftMass,
    SoftTissue,
    skin_tissue,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SOFT_STEP,
    SoftOccupancy,
    classify_soft,
    sample_soft_mass,
)
from extensions.humanoid.spec import HumanoidSpec
from math.vector3 import Vector3
from units.si import Length


def head_skin_occupancy(
    dimensions: HeadMuscleDimensions, point: Vector3
) raises -> SoftOccupancy:
    """Return what fills `point` in the head's dermal shell.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        point: A point in the pelvis frame, in meters.

    Returns:
        `SOFT_FILL` in the dermis. Deep anatomy and exterior space are
        `SOFT_EMPTY`.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    return classify_soft(HeadSkinLayerField(dimensions).distance(point))


def head_skin_mass(
    spec: HumanoidSpec, step: Length = SOFT_STEP
) raises -> SoftMass:
    """Return the wet-tissue mass of the head's dermal shell.

    Args:
        spec: Standing height, osteological sex and athleticism.
        step: Grid cell size. 2 mm through 20 mm, 2 mm by default.

    Returns:
        Sampled dermal volume and wet-tissue mass.

    Raises:
        Error: If `spec` is refused, or `step` is out of range.
    """
    return head_skin_mass_from_dimensions(
        head_muscle_dimensions(spec), skin_tissue(), step
    )


def head_skin_mass_from_dimensions(
    dimensions: HeadMuscleDimensions,
    tissue: SoftTissue,
    step: Length = SOFT_STEP,
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized dermal shell.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        tissue: Hydrated tissue. Mass uses `wet_density` once.
        step: Grid cell size.

    Returns:
        Sampled dermal volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `step` is
            out of range, or `tissue` fails `validate`.
    """
    var field = HeadSkinLayerField(dimensions)
    return sample_soft_mass(
        field, field.low, field.high, tissue, step, "head skin"
    )
