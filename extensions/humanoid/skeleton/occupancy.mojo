# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tissue occupancy and grid-sampled bone-tissue mass.

Regional volumes include pore space. Apparent density is tissue density
times one minus porosity. Bone-tissue mass is apparent density times
regional volume. Porosity is applied once. `solid_tissue` is the tissue
volume after that factor. The report does not estimate a mineral-only
mass or a whole-bone mass with marrow.

Weight on Earth is bone-tissue mass times `STANDARD_GRAVITY`. The number
is a grid-sampled estimate under the chosen tissues. It is not a proven
upper bound.
"""

from extensions.anatomy.tissue import BoneTissue
from extensions.humanoid.skeleton.field import DistanceField
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

# Cell size along each axis of the bounding box.
comptime MIN_STEP = Length(2.0, MILLIMETER)
comptime MAX_STEP = Length(20.0, MILLIMETER)
comptime DEFAULT_STEP = Length(5.0, MILLIMETER)


@fieldwise_init
struct BoneOccupancy(Equatable, ImplicitlyCopyable, Writable):
    """What fills one point of a bone, as a type rather than a bare int.

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
# Trabecular fill of the cancellous ends or the patellar interior.
comptime TRABECULAR_FILL = BoneOccupancy(2)
# Medullary cavity of a long-bone diaphysis. No bone-tissue mass.
comptime MARROW = BoneOccupancy(3)


@fieldwise_init
struct BoneMass(ImplicitlyCopyable):
    """Sampled regional volumes and bone-tissue mass of one bone."""

    var envelope: Volume
    var cortical_region: Volume
    var trabecular_region: Volume
    var solid_tissue: Volume
    var mass: Mass

    def weight(self, gravity: Acceleration = STANDARD_GRAVITY) -> Force:
        """Return the Earth weight of this bone-tissue mass.

        Args:
            gravity: Acceleration of free fall. Standard gravity is the
                default.

        Returns:
            `mass * gravity`, in newtons when `gravity` is standard.
        """
        return self.mass * gravity


@fieldwise_init
struct Tally(ImplicitlyCopyable):
    """Running envelope, regional volumes, solid tissue and mass for one grid.
    """

    var envelope: Float32
    var cortical: Float32
    var trabecular: Float32
    var solid: Float32
    var mass: Float32


def apparent_density_of(
    fill: BoneOccupancy, cortical: BoneTissue, trabecular: BoneTissue
) raises -> Density:
    """Return the apparent tissue density of `fill`.

    Apparent density already includes porosity. Do not scale the result
    by one minus porosity again.

    Args:
        fill: A classified occupancy.
        cortical: Cortical tissue. Used for the shell.
        trabecular: Trabecular tissue. Used for the cancellous fill.

    Returns:
        Apparent density for a tissue fill, or zero for empty space and
        marrow.

    Raises:
        Error: If `fill` is none of the named occupancies.
    """
    if not fill.is_valid():
        raise Error("A bone fill must be empty, cortical, trabecular or marrow")
    if fill == CORTICAL_FILL:
        return cortical.apparent_density()
    if fill == TRABECULAR_FILL:
        return trabecular.apparent_density()
    return Density(0)


def add_fill(
    mut tally: Tally,
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
    var rho = apparent_density_of(fill, cortical, trabecular)
    tally.mass = tally.mass + rho.value * cell
    if fill == EMPTY:
        return
    tally.envelope = tally.envelope + cell
    if fill == CORTICAL_FILL:
        tally.cortical = tally.cortical + cell
        tally.solid = tally.solid + cell * (Float32(1) - cortical.porosity)
        return
    if fill == TRABECULAR_FILL:
        tally.trabecular = tally.trabecular + cell
        tally.solid = tally.solid + cell * (Float32(1) - trabecular.porosity)


def check_mass_step(step: Length, bone: String) raises:
    """Refuse a grid step a mass sampler cannot use.

    Args:
        step: Grid cell size.
        bone: Name used in the error text.

    Raises:
        Error: If `step` is not finite or is outside 2 mm through 20 mm.
    """
    if not isfinite(step.value):
        raise Error("A " + bone + " mass step must be finite")
    if step < MIN_STEP:
        raise Error("A " + bone + " mass step must be at least 2 millimeters")
    if step > MAX_STEP:
        raise Error("A " + bone + " mass step cannot exceed 20 millimeters")


def finish_mass(tally: Tally) -> BoneMass:
    """Return a mass report from an accumulated tally.

    Args:
        tally: Sampled volumes and mass in SI base units.

    Returns:
        The labeled mass report.
    """
    return BoneMass(
        Volume(tally.envelope, CUBIC_METER),
        Volume(tally.cortical, CUBIC_METER),
        Volume(tally.trabecular, CUBIC_METER),
        Volume(tally.solid, CUBIC_METER),
        Mass(tally.mass, KILOGRAM),
    )


def grid_cells(span: Float32, step: Float32) -> Int:
    """Return how many cells of size `step` fit in `span`, at least one."""
    var n = Int(span / step + Float32(0.5))
    if n < 1:
        return 1
    return n


def in_shaft_span(
    y: Float32, y0: Float32, y1: Float32, distal: Float32, proximal: Float32
) -> Bool:
    """Return True if `y` sits in the mid-shaft, not a metaphysis.

    Args:
        y: Sample height, in meters.
        y0: Distal shaft station.
        y1: Proximal shaft station.
        distal: Distal metaphysis as a fraction of the shaft span.
        proximal: Proximal metaphysis as a fraction of the shaft span.

    Returns:
        True when `y` is between the metaphyseal bands.
    """
    var span = y1 - y0
    if y < y0 + distal * span:
        return False
    if y > y1 - proximal * span:
        return False
    return True


def shaft_occupancy(
    distance: Float32,
    radius: Float32,
    y: Float32,
    shaft_low: Float32,
    shaft_high: Float32,
    shell_fraction: Float32,
    distal: Float32,
    proximal: Float32,
) -> BoneOccupancy:
    """Return the tissue at one sample of a long bone.

    Args:
        distance: Signed distance to the bone surface, in meters.
        radius: Mid-shaft radius used to scale the cortical shell.
        y: Sample height, in meters.
        shaft_low: Distal shaft station.
        shaft_high: Proximal shaft station.
        shell_fraction: Cortical thickness as a fraction of `radius`.
        distal: Distal metaphysis as a fraction of the shaft span.
        proximal: Proximal metaphysis as a fraction of the shaft span.

    Returns:
        `EMPTY` outside, else the cortical shell, marrow, or trabecular
        bone.
    """
    if distance >= 0:
        return EMPTY
    var thickness = shell_fraction * radius
    if distance > -thickness:
        return CORTICAL_FILL
    if in_shaft_span(y, shaft_low, shaft_high, distal, proximal):
        return MARROW
    return TRABECULAR_FILL


def sample_bone_mass[
    F: DistanceField, //, classify: def(F, Vector3) thin -> BoneOccupancy
](
    field: F,
    low: Vector3,
    high: Vector3,
    cortical: BoneTissue,
    trabecular: BoneTissue,
    step: Length,
    name: String,
) raises -> BoneMass:
    """Integrate one bone's occupancy policy in a fixed grid order.

    Parameters:
        F: The bone-specific distance field.
        classify: The bone-specific shell, marrow and end-region policy.

    Args:
        field: A field built from validated dimensions.
        low: Minimum sample-box corner, in meters.
        high: Maximum sample-box corner, in meters.
        cortical: The cortical tissue.
        trabecular: The trabecular tissue.
        step: Grid cell size.
        name: The bone name used in errors.

    Returns:
        Regional volumes, solid tissue volume and bone-tissue mass.

    Raises:
        Error: If the step, tissues, bounds or occupancy are invalid.
    """
    check_mass_step(step, name)
    cortical.validate()
    trabecular.validate()
    for axis in range(3):  # pragma: no branch
        var lo = low.get_component(axis)
        var hi = high.get_component(axis)
        if not isfinite(lo) or not isfinite(hi) or hi < lo:
            raise Error("A bone mass sample box must be finite and ordered")
        var span = hi - lo
        # Refuse overflow before grid_cells converts its rounded count.
        if not isfinite(span) or span / step.value + Float32(0.5) >= Float32(
            Int.MAX
        ):
            raise Error("A bone mass sample span is too large")
    var dx = step.value
    var dy = step.value
    var dz = step.value
    var nx = grid_cells(high.x - low.x, dx)
    var ny = grid_cells(high.y - low.y, dy)
    var nz = grid_cells(high.z - low.z, dz)
    var cell = dx * dy * dz
    var tally = Tally(0, 0, 0, 0, 0)
    for iz in range(nz):  # pragma: no branch
        var z = low.z + (Float32(iz) + Float32(0.5)) * dz
        for iy in range(ny):  # pragma: no branch
            var y = low.y + (Float32(iy) + Float32(0.5)) * dy
            for ix in range(nx):  # pragma: no branch
                var x = low.x + (Float32(ix) + Float32(0.5)) * dx
                add_fill(
                    tally,
                    classify(field, Vector3(x, y, z)),
                    cell,
                    cortical,
                    trabecular,
                )
    return finish_mass(tally)
