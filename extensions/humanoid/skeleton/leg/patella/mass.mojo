# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bone-tissue mass and Earth weight of a patella from its solid and tissues.

The patella has no marrow cavity. A thin cortical shell wraps a trabecular
interior. Porosity is applied once through apparent density.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = patella_mass(person)
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.occupancy import (
    CORTICAL_FILL,
    DEFAULT_STEP,
    EMPTY,
    TRABECULAR_FILL,
    BoneMass,
    BoneOccupancy,
    sample_bone_mass,
)
from extensions.humanoid.skeleton.tissue import (
    BoneTissue,
    cortical_tissue,
    trabecular_tissue,
)
from extensions.humanoid.skeleton.leg.patella.dimensions import (
    PatellaDimensions,
    PatellaField,
    patella_dimensions,
)
from math.vector3 import Vector3
from units.si import Length

comptime SHELL_FRACTION = Float32(0.55)


def patella_occupancy(
    dimensions: PatellaDimensions, point: Vector3
) raises -> BoneOccupancy:
    """Return what fills `point` in a sized patella.

    Args:
        dimensions: A patella already sized from stature and sex.
        point: A point in the bone's frame, in meters.

    Returns:
        `EMPTY` outside, `CORTICAL_FILL` in the shell, or
        `TRABECULAR_FILL` in the interior. There is no marrow.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    return _occupancy(PatellaField(dimensions), point)


def patella_mass(
    spec: HumanoidSpec, side: BodySide = RIGHT, step: Length = DEFAULT_STEP
) raises -> BoneMass:
    """Return the bone-tissue mass of a patella sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        side: `RIGHT` or `LEFT`. A right patella is the default.
        step: Grid cell size. 2 mm through 20 mm, 5 mm by default.

    Returns:
        Sampled volumes and the bone-tissue mass.

    Raises:
        Error: If `spec` or `side` is refused by `patella_dimensions`, or
            if `step` is out of range.
    """
    return patella_mass_from_dimensions(
        patella_dimensions(spec.stature, spec.sex, side),
        cortical_tissue(),
        trabecular_tissue(),
        step,
    )


def patella_mass_from_dimensions(
    dimensions: PatellaDimensions,
    cortical: BoneTissue,
    trabecular: BoneTissue,
    step: Length = DEFAULT_STEP,
) raises -> BoneMass:
    """Return the bone-tissue mass of an already-sized patella.

    Args:
        dimensions: Size and landmarks from `patella_dimensions`.
        cortical: Cortical tissue for the shell.
        trabecular: Trabecular tissue for the interior.
        step: Grid cell size.

    Returns:
        Sampled volumes and the bone-tissue mass.

    Raises:
        Error: If `dimensions.validate` refuses the copy, if `step` is
            out of range, or either tissue fails `validate`.
    """
    dimensions.validate()
    var field = PatellaField(dimensions)
    return sample_bone_mass[_occupancy](
        field, field.low, field.high, cortical, trabecular, step, "patella"
    )


def patella_field_occupancy(
    field: PatellaField, point: Vector3
) -> BoneOccupancy:
    """Return what fills `point` in an already-built patella field.

    Use this where one field is sampled at many points; `patella_occupancy`
    builds the field for every call.

    Args:
        field: The patella's field.
        point: A point in the bone's frame, in meters.

    Returns:
        `EMPTY` outside, else the cortical shell, trabecular bone or
        marrow the point falls in.
    """
    return _occupancy(field, point)


def _occupancy(field: PatellaField, point: Vector3) -> BoneOccupancy:
    """Return what fills `point` in `field`. There is no marrow."""
    var d = field.distance(point)
    if d >= 0:
        return EMPTY
    var thickness = SHELL_FRACTION * field.r2
    if d > -thickness:
        return CORTICAL_FILL
    return TRABECULAR_FILL
