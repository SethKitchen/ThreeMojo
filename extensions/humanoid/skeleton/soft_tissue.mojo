# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The mass of a soft-tissue solid of the humanoid, sampled on a grid.

The tissues themselves, their wet densities and moduli, live in
`extensions.anatomy.soft_tissue`, which every anatomy shares. The original
humanoid path re-exports those same types, kinds and factories for callers
that used it before the extraction.
"""

from core.ordinal import ordinal_valid

from extensions.anatomy.soft_tissue import (
    SoftTissueKind,
    CARTILAGE,
    LIGAMENT,
    MENISCUS,
    MUSCLE,
    TENDON,
    ARTERIAL,
    VENOUS,
    LYMPH,
    NERVE,
    SKIN,
    HAIR,
    ADIPOSE,
    SoftTissue,
    SoftMass,
    cartilage_tissue,
    ligament_tissue,
    meniscus_tissue,
    adipose_tissue,
    muscle_tissue,
    tendon_tissue,
    arterial_tissue,
    venous_tissue,
    vessel_tissue,
    lymph_tissue,
    nerve_tissue,
    skin_tissue,
    hair_tissue,
)
from extensions.humanoid.skeleton.occupancy import (
    MIN_STEP,
    check_mass_step,
    grid_cells,
)
from extensions.humanoid.skeleton.field import DistanceField
from math.vector3 import Vector3
from std.math import pi
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
        return ordinal_valid(self.value, SOFT_FILL.value)


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


def six_segment_length(
    a0: Vector3,
    b0: Vector3,
    a1: Vector3,
    b1: Vector3,
    a2: Vector3,
    b2: Vector3,
    a3: Vector3,
    b3: Vector3,
    a4: Vector3,
    b4: Vector3,
    a5: Vector3,
    b5: Vector3,
) -> Float32:
    """Return the added length of six hair shafts, in meters.

    Args:
        a0: Start of the first shaft.
        b0: End of the first shaft.
        a1: Start of the second shaft.
        b1: End of the second shaft.
        a2: Start of the third shaft.
        b2: End of the third shaft.
        a3: Start of the fourth shaft.
        b3: End of the fourth shaft.
        a4: Start of the fifth shaft.
        b4: End of the fifth shaft.
        a5: Start of the sixth shaft.
        b5: End of the sixth shaft.

    Returns:
        The six center-line lengths added together.
    """
    var length = (b0 - a0).length()
    length += (b1 - a1).length()
    length += (b2 - a2).length()
    length += (b3 - a3).length()
    length += (b4 - a4).length()
    length += (b5 - a5).length()
    return length


def six_capsule_volume(radius: Float32, length: Float32) -> Float32:
    """Return the volume of six equal-radius hair capsules, in cubic meters.

    Each shaft is a cylinder along its center line plus a sphere for its
    two ends. Six shafts therefore add six spheres.

    Args:
        radius: Shaft radius, in meters.
        length: The six center-line lengths added together, in meters.

    Returns:
        Cylinder volume plus the six end spheres.
    """
    return (
        pi * radius * radius * length
        + Float32(6) * Float32(4.0 / 3.0) * pi * radius * radius * radius
    )
