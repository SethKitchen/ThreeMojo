# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bone-tissue mass and Earth weight of a tibia from its solid and tissues.

The mesh is the outer surface. The interior is not solid cortical bone.
A shaft has a marrow cavity. The plateau and the malleolus hold trabecular
bone inside a cortical shell.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = tibia_mass(person)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.occupancy import (
    CORTICAL_FILL,
    DEFAULT_STEP,
    EMPTY,
    MARROW,
    TRABECULAR_FILL,
    BoneMass,
    BoneOccupancy,
    sample_bone_mass,
    in_shaft_span,
)
from extensions.anatomy.tissue import (
    BoneTissue,
    cortical_tissue,
    trabecular_tissue,
)
from extensions.humanoid.skeleton.leg.tibia.dimensions import (
    TibiaDimensions,
    TibiaField,
    tibia_dimensions,
)
from math.vector3 import Vector3
from units.si import Length

comptime SHELL_FRACTION = Float32(0.42)
comptime DISTAL_METAPHYSIS = Float32(0.22)
comptime PROXIMAL_METAPHYSIS = Float32(0.18)


def tibia_occupancy(
    dimensions: TibiaDimensions, point: Vector3
) raises -> BoneOccupancy:
    """Return what fills `point` in a sized tibia.

    Args:
        dimensions: A tibia already sized from stature and sex.
        point: A point in the bone's frame, in meters.

    Returns:
        `EMPTY` outside, `CORTICAL_FILL` in the shell, `MARROW` in the
        shaft cavity, or `TRABECULAR_FILL` in the cancellous ends.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    return _occupancy(TibiaField(dimensions), point)


def tibia_mass(
    spec: HumanoidSpec, side: BodySide = RIGHT, step: Length = DEFAULT_STEP
) raises -> BoneMass:
    """Return the bone-tissue mass of a tibia sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        side: `RIGHT` or `LEFT`. A right tibia is the default.
        step: Grid cell size. 2 mm through 20 mm, 5 mm by default.

    Returns:
        Sampled volumes and the bone-tissue mass.

    Raises:
        Error: If `spec` or `side` is refused by `tibia_dimensions`, or
            if `step` is out of range.
    """
    return tibia_mass_from_dimensions(
        tibia_dimensions(spec.stature, spec.sex, side),
        cortical_tissue(),
        trabecular_tissue(),
        step,
    )


def tibia_mass_from_dimensions(
    dimensions: TibiaDimensions,
    cortical: BoneTissue,
    trabecular: BoneTissue,
    step: Length = DEFAULT_STEP,
) raises -> BoneMass:
    """Return the bone-tissue mass of an already-sized tibia.

    Args:
        dimensions: Size and landmarks from `tibia_dimensions`.
        cortical: Cortical tissue for the shell.
        trabecular: Trabecular tissue for the cancellous ends.
        step: Grid cell size.

    Returns:
        Sampled volumes and the bone-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `step` is
            out of range, or either tissue fails `validate`.
    """
    dimensions.validate()
    var field = TibiaField(dimensions)
    return sample_bone_mass[_occupancy](
        field, field.low, field.high, cortical, trabecular, step, "tibia"
    )


def tibia_field_occupancy(field: TibiaField, point: Vector3) -> BoneOccupancy:
    """Return what fills `point` in an already-built tibia field.

    Use this where one field is sampled at many points; `tibia_occupancy`
    builds the field for every call.

    Args:
        field: The tibia's field.
        point: A point in the bone's frame, in meters.

    Returns:
        `EMPTY` outside, else the cortical shell, trabecular bone or
        marrow the point falls in.
    """
    return _occupancy(field, point)


def _occupancy(field: TibiaField, point: Vector3) -> BoneOccupancy:
    """Return what fills `point` in `field`."""
    var d = field.distance(point)
    if d >= 0:
        return EMPTY
    var thickness = SHELL_FRACTION * field.r2
    if d > -thickness:
        return CORTICAL_FILL
    if in_shaft_span(
        point.y, field.s0.y, field.s4.y, DISTAL_METAPHYSIS, PROXIMAL_METAPHYSIS
    ):
        return MARROW
    return TRABECULAR_FILL
