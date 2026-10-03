# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of one arm hair group from its physical shafts.

Mass uses analytic volume and hair tissue. The display radius is not
used.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = arm_hair_mass(person, FOREARM_HAIR)
"""

from extensions.humanoid.side import RIGHT
from extensions.humanoid.skeleton.arm.frame import (
    ArmMuscleDimensions,
    arm_muscle_dimensions,
)
from extensions.humanoid.skeleton.arm.hair.dimensions import (
    ArmHair,
    arm_hair_field,
)
from extensions.anatomy.soft_tissue import (
    SoftMass,
    SoftTissue,
    hair_tissue,
)
from extensions.humanoid.spec import HumanoidSpec
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


def arm_hair_mass(spec: HumanoidSpec, part: ArmHair) raises -> SoftMass:
    """Return the wet-tissue mass of one arm hair group.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which group to weigh.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `spec` or `part` is refused.
    """
    return arm_hair_mass_from_dimensions(
        arm_muscle_dimensions(spec), part, hair_tissue()
    )


def arm_hair_mass_from_dimensions(
    dimensions: ArmMuscleDimensions, part: ArmHair, tissue: SoftTissue
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized hair group.

    Args:
        dimensions: Landmarks from `arm_muscle_dimensions`.
        part: Which group to weigh.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    tissue.validate()
    var volume = arm_hair_field(dimensions, part, RIGHT).volume()
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
