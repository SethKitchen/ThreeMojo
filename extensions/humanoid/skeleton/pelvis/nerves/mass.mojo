# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a pelvic nerve from its physical tube.

Mass uses the analytic frustum volume of the physical radii. The
display minimum radius is not used.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = pelvis_nerve_mass(person, SACRAL_PLEXUS)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import tube_chain_volume
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    PelvisMuscleDimensions,
    pelvis_muscle_dimensions,
)
from extensions.humanoid.skeleton.pelvis.nerves.dimensions import (
    PelvisNerve,
    PelvisNerveField,
    pelvis_nerve_distance,
)
from extensions.anatomy.soft_tissue import (
    SoftMass,
    SoftTissue,
    nerve_tissue,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftOccupancy,
    classify_soft,
)
from math.vector3 import Vector3
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


def pelvis_nerve_occupancy(
    dimensions: PelvisMuscleDimensions,
    part: PelvisNerve,
    side: BodySide,
    point: Vector3,
) raises -> SoftOccupancy:
    """Return what fills `point` in one pelvic nerve.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        part: Which nerve to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return classify_soft(pelvis_nerve_distance(dimensions, part, side, point))


def pelvis_nerve_mass(spec: HumanoidSpec, part: PelvisNerve) raises -> SoftMass:
    """Return the wet-tissue mass of one pelvic nerve sized for `spec`.

    The nerve is one side's.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which nerve to sample.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `spec` or `part` is refused.
    """
    return pelvis_nerve_mass_from_dimensions(
        pelvis_muscle_dimensions(spec), part, nerve_tissue()
    )


def pelvis_nerve_mass_from_dimensions(
    dimensions: PelvisMuscleDimensions, part: PelvisNerve, tissue: SoftTissue
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized pelvic nerve.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        part: Which nerve to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    tissue.validate()
    var volume = tube_chain_volume(
        PelvisNerveField(dimensions, part, RIGHT).chain
    )
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
