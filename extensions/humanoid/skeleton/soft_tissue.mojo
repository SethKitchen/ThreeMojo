# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The mass of a soft-tissue solid of the humanoid, sampled on a grid.

The tissues themselves, their wet densities and moduli, live in
`extensions.anatomy.soft_tissue`, which every anatomy shares.
"""

from extensions.anatomy.soft_tissue import SoftMass, SoftTissue
from extensions.humanoid.skeleton.occupancy import (
    MIN_STEP,
    check_mass_step,
    grid_cells,
)
from extensions.humanoid.skeleton.field import DistanceField
from math.vector3 import Vector3
from units.si import (
    CUBIC_METER,
    Density,
    KILOGRAM,
    Length,
    Mass,
    Volume,
)


@fieldwise_init
struct SoftOccupancy(Equatable, ImplicitlyCopyable, Writable):
    """What fills one point of a soft-tissue solid.

    The type stops a bare integer at compile time. A value that is not
    `SOFT_EMPTY` or `SOFT_FILL` is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is empty or filled soft tissue."""
        return self == SOFT_EMPTY or self == SOFT_FILL


# Outside the solid.
comptime SOFT_EMPTY = SoftOccupancy(0)
# Inside the hydrated tissue.
comptime SOFT_FILL = SoftOccupancy(1)


def filled_density(fill: SoftOccupancy, tissue: SoftTissue) raises -> Density:
    """Return the wet density of `fill`.

    Args:
        fill: A classified occupancy.
        tissue: Hydrated tissue used when `fill` is `SOFT_FILL`.

    Returns:
        `tissue.wet_density` for a fill, or zero for empty space.

    Raises:
        Error: If `fill` is none of the named occupancies, or `tissue`
            fails `validate`.
    """
    if not fill.is_valid():
        raise Error("A soft fill must be empty or filled")
    tissue.validate()
    if fill == SOFT_FILL:
        return tissue.wet_density
    return Density(0)


def classify_soft(distance: Float32) -> SoftOccupancy:
    """Return empty outside a solid, filled inside.

    Args:
        distance: Signed distance in meters. Negative is inside.

    Returns:
        `SOFT_EMPTY` when `distance` is not negative, else `SOFT_FILL`.
    """
    if distance >= 0:
        return SOFT_EMPTY
    return SOFT_FILL


def sample_soft_mass[
    F: DistanceField
](
    field: F,
    low: Vector3,
    high: Vector3,
    tissue: SoftTissue,
    step: Length,
    name: String,
) raises -> SoftMass:
    """Sample `field` on a grid and return wet-tissue mass.

    Args:
        field: An implicit solid.
        low: Minimum corner of the sample box, in meters.
        high: Maximum corner of the sample box, in meters.
        tissue: Hydrated tissue. Mass uses `wet_density` once.
        step: Grid cell size.
        name: Name used in the error text.

    Returns:
        Envelope volume and wet-tissue mass.

    Raises:
        Error: If `step` is out of range or `tissue` fails `validate`.
    """
    check_mass_step(step, name)
    tissue.validate()
    var dx = step.value
    var dy = step.value
    var dz = step.value
    var nx = grid_cells(high.x - low.x, dx)
    var ny = grid_cells(high.y - low.y, dy)
    var nz = grid_cells(high.z - low.z, dz)
    var cell = dx * dy * dz
    var envelope = Float32(0)
    var mass = Float32(0)
    var rho = tissue.wet_density.value
    for iz in range(nz):  # pragma: no branch
        var z = low.z + (Float32(iz) + Float32(0.5)) * dz
        for iy in range(ny):  # pragma: no branch
            var y = low.y + (Float32(iy) + Float32(0.5)) * dy
            for ix in range(nx):  # pragma: no branch
                var x = low.x + (Float32(ix) + Float32(0.5)) * dx
                var fill = classify_soft(field.distance(Vector3(x, y, z)))
                if fill == SOFT_EMPTY:
                    continue
                envelope = envelope + cell
                mass = mass + rho * cell
    return SoftMass(
        Volume(envelope, CUBIC_METER),
        Mass(mass, KILOGRAM),
    )


# Re-export the bone mass step floor so knee mass can default to 2 mm.
comptime SOFT_STEP = MIN_STEP
