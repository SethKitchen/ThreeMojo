# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass of a pelvic node group or the iliac lymphatic trunk.

Mass uses the analytic volume of the node spheres or the trunk. The
display minimum radius is not used.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = pelvis_lymph_mass(person, SACRAL_NODES)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    PelvisMuscleDimensions,
    pelvis_muscle_dimensions,
)
from extensions.humanoid.skeleton.pelvis.lymph.dimensions import (
    PelvisLymph,
    PelvisLymphField,
    pelvis_lymph_distance,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    classify_soft,
    lymph_tissue,
)
from math.vector3 import Vector3
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


def pelvis_lymph_occupancy(
    dimensions: PelvisMuscleDimensions,
    part: PelvisLymph,
    side: BodySide,
    point: Vector3,
) raises -> SoftOccupancy:
    """Return what fills `point` in one pelvic lymph solid.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        part: Which node group or trunk to sample.
        side: `RIGHT` or `LEFT`.
        point: A point in the pelvis frame, in meters.

    Returns:
        `SOFT_EMPTY` outside, `SOFT_FILL` inside.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or if `side` is not valid.
    """
    return classify_soft(pelvis_lymph_distance(dimensions, part, side, point))


def pelvis_lymph_mass(spec: HumanoidSpec, part: PelvisLymph) raises -> SoftMass:
    """Return the wet-tissue mass of one pelvic lymph solid sized for `spec`.

    The part is one side's.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which node group or trunk to sample.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `spec` or `part` is refused.
    """
    return pelvis_lymph_mass_from_dimensions(
        pelvis_muscle_dimensions(spec), part, lymph_tissue()
    )


def pelvis_lymph_mass_from_dimensions(
    dimensions: PelvisMuscleDimensions, part: PelvisLymph, tissue: SoftTissue
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized pelvic lymph solid.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        part: Which node group or trunk to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    tissue.validate()
    var volume = PelvisLymphField(dimensions, part, RIGHT).volume()
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
