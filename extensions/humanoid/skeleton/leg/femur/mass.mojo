# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Mass and Earth weight of a femur from its solid and its tissues.

The mesh is the outer surface. The interior is not solid cortical bone.
A shaft has a marrow cavity. The head and the condyles hold trabecular
bone inside a cortical shell. This module samples the signed-distance
field on a grid and classifies each cell.

Mineral mass is apparent density times the cortical and trabecular
volume. Marrow adds envelope volume and no mineral mass. Weight on Earth
is that mass times `STANDARD_GRAVITY`.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = femur_mass(person)
    print(report.mass.to(KILOGRAM), "kg")
    print(report.weight().to(NEWTON), "N")
"""

from extensions.humanoid.side import RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import (
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
from std.math import isfinite
from units.si import (
    STANDARD_GRAVITY,
    Acceleration,
    CUBIC_METER,
    Density,
    Force,
    KILOGRAM,
    Length,
    MILLIMETER,
    Mass,
    Volume,
)


@fieldwise_init
struct BoneOccupancy(Equatable, ImplicitlyCopyable, Writable):
    """What fills one point of a femur, as a type rather than a bare int.

    The type stops a bare integer at compile time. A value that is none
    of the four named fills is still constructible, and the boundary that
    reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four named fills."""
        if self == EMPTY:
            return True
        if self == CORTICAL_FILL:
            return True
        if self == TRABECULAR_FILL:
            return True
        return self == MARROW


# Outside the solid.
comptime EMPTY = BoneOccupancy(0)
# Cortical shell, near the surface.
comptime CORTICAL_FILL = BoneOccupancy(1)
# Trabecular fill of the head, neck and condyles.
comptime TRABECULAR_FILL = BoneOccupancy(2)
# Medullary cavity of the diaphysis. No mineral mass.
comptime MARROW = BoneOccupancy(3)

# Cell size along each axis of the bounding box.
comptime MIN_STEP = Length(2.0, MILLIMETER)
comptime MAX_STEP = Length(20.0, MILLIMETER)
comptime DEFAULT_STEP = Length(5.0, MILLIMETER)
# Cortical shell as a fraction of midshaft radius, about 6 mm on a 6 ft male.
comptime SHELL_FRACTION = Float32(0.42)
# Distal and proximal fractions of the shaft that are metaphysis, not cavity.
comptime DISTAL_METAPHYSIS = Float32(0.20)
comptime PROXIMAL_METAPHYSIS = Float32(0.15)


@fieldwise_init
struct FemurMass(ImplicitlyCopyable):
    """Sampled volume and mineral mass of one femur."""

    var envelope: Volume
    var bone: Volume
    var cortical: Volume
    var trabecular: Volume
    var mass: Mass

    def weight(self, gravity: Acceleration = STANDARD_GRAVITY) -> Force:
        """Return the Earth weight of this mineral mass.

        Args:
            gravity: Acceleration of free fall. Standard gravity is the
                default.

        Returns:
            `mass * gravity`, in newtons when `gravity` is standard.
        """
        return self.mass * gravity


@fieldwise_init
struct _Tally(ImplicitlyCopyable):
    """Running envelope, mineral volumes and mass for one grid."""

    var envelope: Float32
    var cortical: Float32
    var trabecular: Float32
    var mass: Float32


def femur_occupancy(
    dimensions: FemurDimensions, point: Vector3
) -> BoneOccupancy:
    """Return what fills `point` in a sized femur.

    Args:
        dimensions: A femur already sized from stature and sex.
        point: A point in the bone's frame, in meters.

    Returns:
        `EMPTY` outside, `CORTICAL_FILL` in the shell, `MARROW` in the
        shaft cavity, or `TRABECULAR_FILL` in the cancellous ends.
    """
    return _occupancy(FemurField(dimensions), point)


def mineral_density(
    fill: BoneOccupancy, cortical: BoneTissue, trabecular: BoneTissue
) raises -> Density:
    """Return the mineral density of `fill`.

    Args:
        fill: A classified occupancy.
        cortical: Cortical tissue. Used for the shell.
        trabecular: Trabecular tissue. Used for the cancellous ends.

    Returns:
        Apparent density for a mineral fill, or zero for empty space and
        marrow.

    Raises:
        Error: If `fill` is none of the named occupancies.
    """
    if not fill.is_valid():
        raise Error(
            "A femur fill must be empty, cortical, trabecular or marrow"
        )
    if fill == CORTICAL_FILL:
        return cortical.apparent_density()
    if fill == TRABECULAR_FILL:
        return trabecular.apparent_density()
    return Density(0)


def add_fill(
    mut tally: _Tally,
    fill: BoneOccupancy,
    cell: Float32,
    cortical: BoneTissue,
    trabecular: BoneTissue,
) raises:
    """Add one cell of `fill` to `tally`.

    Args:
        tally: Running volumes and mass, edited in place.
        fill: Occupancy of the cell.
        cell: Cell volume in cubic meters.
        cortical: Cortical tissue.
        trabecular: Trabecular tissue.

    Raises:
        Error: If `fill` is none of the named occupancies.
    """
    var rho = mineral_density(fill, cortical, trabecular)
    tally.mass = tally.mass + rho.value * cell
    if fill == EMPTY:
        return
    tally.envelope = tally.envelope + cell
    if fill == CORTICAL_FILL:
        tally.cortical = tally.cortical + cell
        return
    if fill == TRABECULAR_FILL:
        tally.trabecular = tally.trabecular + cell


def femur_mass(
    spec: HumanoidSpec, side: BodySide = RIGHT, step: Length = DEFAULT_STEP
) raises -> FemurMass:
    """Return the mineral mass of a femur sized for `spec`.

    Args:
        spec: Standing height and osteological sex.
        side: `RIGHT` or `LEFT`. A right femur is the default.
        step: Grid cell size. 2 mm through 20 mm, 5 mm by default.

    Returns:
        Sampled volumes and the mineral mass.

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
) raises -> FemurMass:
    """Return the mineral mass of an already-sized femur.

    Args:
        dimensions: Size and landmarks from `femur_dimensions`.
        cortical: Cortical tissue for the shell.
        trabecular: Trabecular tissue for the cancellous ends.
        step: Grid cell size.

    Returns:
        Sampled volumes and the mineral mass.

    Raises:
        Error: If `step` is out of range, or either tissue fails
            `validate`.
    """
    if not isfinite(step.value):
        raise Error("A femur mass step must be finite")
    if step < MIN_STEP:
        raise Error("A femur mass step must be at least 2 millimeters")
    if step > MAX_STEP:
        raise Error("A femur mass step cannot exceed 20 millimeters")
    cortical.validate()
    trabecular.validate()

    var field = FemurField(dimensions)
    var dx = step.value
    var dy = step.value
    var dz = step.value
    var nx = _cells(field.high.x - field.low.x, dx)
    var ny = _cells(field.high.y - field.low.y, dy)
    var nz = _cells(field.high.z - field.low.z, dz)
    var cell = dx * dy * dz
    var tally = _Tally(0, 0, 0, 0)
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
    var bone_v = tally.cortical + tally.trabecular
    return FemurMass(
        Volume(tally.envelope, CUBIC_METER),
        Volume(bone_v, CUBIC_METER),
        Volume(tally.cortical, CUBIC_METER),
        Volume(tally.trabecular, CUBIC_METER),
        Mass(tally.mass, KILOGRAM),
    )


def _occupancy(field: FemurField, point: Vector3) -> BoneOccupancy:
    """Return what fills `point` in `field`."""
    var d = field.distance(point)
    if d >= 0:
        return EMPTY
    var thickness = SHELL_FRACTION * field.r2
    if d > -thickness:
        return CORTICAL_FILL
    if _in_diaphysis(field, point):
        return MARROW
    return TRABECULAR_FILL


def _in_diaphysis(field: FemurField, point: Vector3) -> Bool:
    """Return True if `point` sits in the mid-shaft, not a metaphysis."""
    var y0 = field.s0.y
    var y1 = field.s4.y
    var span = y1 - y0
    if point.y < y0 + DISTAL_METAPHYSIS * span:
        return False
    if point.y > y1 - PROXIMAL_METAPHYSIS * span:
        return False
    return True


def _cells(span: Float32, step: Float32) -> Int:
    """Return how many cells of size `step` fit in `span`, at least one."""
    var n = Int(span / step + Float32(0.5))
    if n < 1:
        return 1
    return n
