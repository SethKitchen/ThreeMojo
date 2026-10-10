# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bone-tissue mass and Earth weight of a femur from its solid and tissues.

The mesh is the outer surface. The interior is not solid cortical bone.
A shaft has a marrow cavity. The head and the condyles hold trabecular
bone inside a cortical shell. This module samples the signed-distance
field on a grid and classifies each cell.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = femur_mass(person)
    print(report.mass.to(KILOGRAM), "kg")
    print(report.weight().to(NEWTON), "N")
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.occupancy import (
    DEFAULT_STEP,
    BoneMass,
    BoneOccupancy,
    sample_bone_mass,
    shaft_occupancy,
)
from extensions.anatomy.tissue import (
    BoneTissue,
    cortical_tissue,
    trabecular_tissue,
)
from extensions.humanoid.skeleton.leg.femur.dimensions import (
    FemurDimensions,
    FemurField,
    femur_dimensions,
)
from math.vector3 import Vector3
from units.si import Length

# Cortical shell as a fraction of mean midshaft radius, about 6 mm on a 6 ft male.
comptime SHELL_FRACTION = Float32(0.42)
# Distal and proximal fractions of the shaft that are metaphysis, not cavity.
comptime DISTAL_METAPHYSIS = Float32(0.20)
comptime PROXIMAL_METAPHYSIS = Float32(0.15)


def femur_occupancy(
    dimensions: FemurDimensions, point: Vector3
) raises -> BoneOccupancy:
    """Return what fills `point` in a sized femur.

    Args:
        dimensions: A femur already sized from stature and sex.
        point: A point in the bone's frame, in meters.

    Returns:
        `EMPTY` outside, `CORTICAL_FILL` in the shell, `MARROW` in the
        shaft cavity, or `TRABECULAR_FILL` in the cancellous ends.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    return _occupancy(FemurField(dimensions), point)


def femur_mass(
    spec: HumanoidSpec, side: BodySide = RIGHT, step: Length = DEFAULT_STEP
) raises -> BoneMass:
    """Return the bone-tissue mass of a femur sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        side: `RIGHT` or `LEFT`. A right femur is the default.
        step: Grid cell size. 2 mm through 20 mm, 5 mm by default.

    Returns:
        Sampled volumes and the bone-tissue mass.

    Raises:
        Error: If `spec` or `side` is refused by `femur_dimensions`, or
            if `step` is out of range.
    """
    return femur_mass_from_dimensions(
        femur_dimensions(spec.stature, spec.sex, side),
        cortical_tissue(),
        trabecular_tissue(),
        step,
    )


def femur_mass_from_dimensions(
    dimensions: FemurDimensions,
    cortical: BoneTissue,
    trabecular: BoneTissue,
    step: Length = DEFAULT_STEP,
) raises -> BoneMass:
    """Return the bone-tissue mass of an already-sized femur.

    Args:
        dimensions: Size and landmarks from `femur_dimensions`.
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
    var field = FemurField(dimensions)
    return sample_bone_mass[_occupancy](
        field, field.low, field.high, cortical, trabecular, step, "femur"
    )


def femur_field_occupancy(field: FemurField, point: Vector3) -> BoneOccupancy:
    """Return what fills `point` in an already-built femur field.

    Use this where one field is sampled at many points; `femur_occupancy`
    builds the field for every call.

    Args:
        field: The femur's field.
        point: A point in the bone's frame, in meters.

    Returns:
        `EMPTY` outside, else the cortical shell, trabecular bone or
        marrow the point falls in.
    """
    return _occupancy(field, point)


def _occupancy(field: FemurField, point: Vector3) -> BoneOccupancy:
    """Return what fills `point` in `field`."""
    return shaft_occupancy(
        field.distance(point),
        field.r2,
        point.y,
        field.s0.y,
        field.s4.y,
        SHELL_FRACTION,
        DISTAL_METAPHYSIS,
        PROXIMAL_METAPHYSIS,
    )
