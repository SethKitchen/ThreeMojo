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
    CORTICAL_FILL,
    DEFAULT_STEP,
    EMPTY,
    MARROW,
    TRABECULAR_FILL,
    BoneMass,
    BoneOccupancy,
    Tally,
    add_fill,
    check_mass_step,
    finish_mass,
    grid_cells,
    in_shaft_span,
)
from extensions.humanoid.skeleton.tissue import (
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
    check_mass_step(step, "femur")
    cortical.validate()
    trabecular.validate()

    var field = FemurField(dimensions)
    var dx = step.value
    var dy = step.value
    var dz = step.value
    var nx = grid_cells(field.high.x - field.low.x, dx)
    var ny = grid_cells(field.high.y - field.low.y, dy)
    var nz = grid_cells(field.high.z - field.low.z, dz)
    var cell = dx * dy * dz
    var tally = Tally(0, 0, 0, 0, 0)
    for iz in range(nz):  # pragma: no branch
        var z = field.low.z + (Float32(iz) + Float32(0.5)) * dz
        for iy in range(ny):  # pragma: no branch
            var y = field.low.y + (Float32(iy) + Float32(0.5)) * dy
            for ix in range(nx):  # pragma: no branch
                var x = field.low.x + (Float32(ix) + Float32(0.5)) * dx
                add_fill(
                    tally,
                    _occupancy(field, Vector3(x, y, z)),
                    cell,
                    cortical,
                    trabecular,
                )
    return finish_mass(tally)


def _occupancy(field: FemurField, point: Vector3) -> BoneOccupancy:
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
