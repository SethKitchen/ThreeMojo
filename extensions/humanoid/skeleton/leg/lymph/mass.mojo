# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wet-tissue mass from physical lymph-node and collector dimensions.

Mass uses analytic sphere and tapered-tube volume. Collector display
radius does not change mass.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = lymph_mass(person, INGUINAL_NODES)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import tube_chain_volume
from extensions.humanoid.skeleton.leg.lymph.dimensions import (
    LymphField,
    LymphPart,
    lymph_distance,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    MuscleDimensions,
    muscle_dimensions,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SoftMass,
    SoftOccupancy,
    SoftTissue,
    classify_soft,
    lymph_tissue,
)
from math.vector3 import Vector3
from std.math import pi
from units.si import CUBIC_METER, KILOGRAM, Mass, Volume


def lymph_occupancy(
    dimensions: MuscleDimensions, part: LymphPart, point: Vector3
) raises -> SoftOccupancy:
    """Return what fills `point` in one lymph solid.

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
    return classify_soft(lymph_distance(dimensions, part, point))


def lymph_mass(
    spec: HumanoidSpec,
    part: LymphPart,
    side: BodySide = RIGHT,
) raises -> SoftMass:
    """Return the wet-tissue mass of one named lymph solid sized for `spec`.

    Args:
        spec: Standing height, osteological sex and athleticism.
        part: Which solid to sample.
        side: `RIGHT` or `LEFT`. A right leg is the default.

    Returns:
        Analytic node or collector volume and wet-tissue mass.

    Raises:
        Error: If `spec`, `side` or `part` is refused.
    """
    return lymph_mass_from_dimensions(
        muscle_dimensions(spec, side), part, lymph_tissue()
    )


def lymph_mass_from_dimensions(
    dimensions: MuscleDimensions,
    part: LymphPart,
    tissue: SoftTissue,
) raises -> SoftMass:
    """Return the wet-tissue mass of an already-sized lymph solid.

    Args:
        dimensions: Landmarks from `muscle_dimensions`.
        part: Which solid to sample.
        tissue: Hydrated tissue. Mass uses `wet_density` once.

    Returns:
        Analytic node or collector volume and wet-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `part` is
            not named, or `tissue` fails `validate`.
    """
    dimensions.validate()
    if not part.is_valid():
        raise Error("A lymph part must be a named node group or trunk")
    tissue.validate()
    var field = LymphField(dimensions, part)
    var volume: Float32
    if field.nodes:
        volume = (
            Float32(4.0 / 3.0)
            * pi
            * (
                field.n0 * field.n0 * field.n0
                + field.n1 * field.n1 * field.n1
                + field.n2 * field.n2 * field.n2
                + field.n3 * field.n3 * field.n3
                + field.n4 * field.n4 * field.n4
            )
        )
    else:
        volume = tube_chain_volume(field.chain)
        if field.chain_count >= 2:
            volume += tube_chain_volume(field.chain2)
        if field.chain_count >= 3:
            volume += tube_chain_volume(field.chain3)
        if field.chain_count >= 4:
            volume += tube_chain_volume(field.chain4)
    return SoftMass(
        Volume(volume, CUBIC_METER),
        Mass(tissue.wet_density.value * volume, KILOGRAM),
    )
