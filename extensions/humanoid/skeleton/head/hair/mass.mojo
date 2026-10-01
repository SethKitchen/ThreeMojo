# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of one head hair group.

Mass uses the analytic volume of the hair's solid, times `HAIR_PACKING`
for the air between the shafts, and hair tissue. A paired group is one
side's.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = head_hair_mass(person, SCALP_HAIR)
"""

from extensions.humanoid.side import RIGHT
from extensions.humanoid.skeleton.head.frame import (
    HeadMuscleDimensions,
    head_muscle_dimensions,
)
from extensions.humanoid.skeleton.head.hair.dimensions import (
    HAIR_PACKING,
    HeadHair,
    head_hair_field,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftMass,
    SoftTissue,
    hair_tissue,
)
from extensions.humanoid.spec import HumanoidSpec
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


def head_hair_mass(spec: HumanoidSpec, part: HeadHair) raises -> SoftMass:
    """Return the wet-tissue mass of one head hair group.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which group to weigh.

    Returns:
        The hair's own volume and its wet-tissue mass.

    Raises:
        Error: If `spec` or `part` is refused.
    """
    return head_hair_mass_from_dimensions(
        head_muscle_dimensions(spec), part, hair_tissue()
    )


def head_hair_mass_from_dimensions(
    dimensions: HeadMuscleDimensions, part: HeadHair, tissue: SoftTissue
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized hair group.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        part: Which group to weigh.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        The hair's own volume and its wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    tissue.validate()
    var volume = (
        head_hair_field(dimensions, part, RIGHT).volume() * HAIR_PACKING
    )
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
