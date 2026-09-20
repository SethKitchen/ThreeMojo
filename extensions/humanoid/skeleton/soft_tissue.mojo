# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Published wet density and moduli for knee cartilage, meniscus and ligament.

Cartilage numbers follow Mow, Kuei, Lai and Armstrong, *Biphasic creep
and stress relaxation of articular cartilage in compression*, J. Biomech.
Eng. 1980. Water fraction 0.75 is the middle of that paper's 60% to 85%
range. Wet density 1.12 g/cm^3 is a named adult template inside the
published 1.06 to 1.16 g/cm^3 range for hydrated articular cartilage. It
is not a cited table cell.

Meniscus water fraction 0.70 follows Fithian, Kelly and Mow, *Material
properties and structure-function relationships in the menisci*, Clin.
Orthop. Relat. Res. 1990. Wet density 1.10 g/cm^3 is a named template.

Ligament wet density 1.12 g/cm^3 and water fraction 0.65 are named adult
templates for hydrated dense connective tissue.

Water fraction is metadata. Wet density already describes the hydrated
tissue. Mass uses wet density times envelope volume. Do not scale by
one minus water fraction again.

These values are sourced or named research metadata. They are not a
constitutive model. This module does not implement biphasic or fiber
elasticity.

    var tissue = cartilage_tissue()
    var mass = tissue.wet_density * volume
"""

from extensions.humanoid.skeleton.occupancy import (
    MIN_STEP,
    check_mass_step,
    grid_cells,
)
from extensions.humanoid.skeleton.field import DistanceField
from math.vector3 import Vector3
from std.math import isfinite
from units.si import (
    STANDARD_GRAVITY,
    Acceleration,
    CUBIC_METER,
    Density,
    Force,
    GRAM_PER_CUBIC_CENTIMETER,
    KILOGRAM,
    Length,
    MEGAPASCAL,
    Mass,
    Pressure,
    Volume,
)


@fieldwise_init
struct SoftTissueKind(Equatable, ImplicitlyCopyable, Writable):
    """Which hydrated tissue a `SoftTissue` describes.

    The type stops a bare integer at compile time. A value that is not
    `CARTILAGE`, `LIGAMENT` or `MENISCUS` is still constructible, and
    the boundary that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is cartilage, ligament or meniscus."""
        if self == CARTILAGE:
            return True
        if self == LIGAMENT:
            return True
        return self == MENISCUS


# Hyaline articular cartilage of the knee.
comptime CARTILAGE = SoftTissueKind(0)
# Dense collagenous collateral ligament.
comptime LIGAMENT = SoftTissueKind(1)
# Fibrocartilage of a meniscus.
comptime MENISCUS = SoftTissueKind(2)


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


@fieldwise_init
struct SoftTissue(ImplicitlyCopyable):
    """Wet density, water fraction and a compressive modulus of one tissue.

    `wet_density` is the hydrated tissue. `water_fraction` is metadata.
    Mass must use `wet_density` and must not apply the water fraction
    again. The constructor does not refuse a bad kind. `validate` does
    that.
    """

    var kind: SoftTissueKind
    var wet_density: Density
    var water_fraction: Float32
    var elastic_modulus: Pressure
    var poisson_ratio: Float32

    def validate(self) raises:
        """Refuse a kind, density, water fraction, modulus or Poisson
        ratio that this tissue cannot hold.

        Raises:
            Error: If `kind` is not named, if a quantity is not finite
                or not positive, if water fraction is outside 0 through
                1, or if Poisson's ratio is outside 0 through 1.
        """
        if not self.kind.is_valid():
            raise Error("Soft tissue must be cartilage, ligament or meniscus")
        if not isfinite(self.wet_density.value):
            raise Error("A soft tissue density must be finite")
        if self.wet_density.value <= 0:
            raise Error("A soft tissue density must be positive")
        if not isfinite(self.water_fraction):
            raise Error("A soft tissue water fraction must be finite")
        if self.water_fraction < 0:
            raise Error("A soft tissue water fraction cannot be negative")
        if self.water_fraction > 1:
            raise Error("A soft tissue water fraction cannot exceed one")
        if not isfinite(self.elastic_modulus.value):
            raise Error("A soft tissue elastic modulus must be finite")
        if self.elastic_modulus.value <= 0:
            raise Error("A soft tissue elastic modulus must be positive")
        if not isfinite(self.poisson_ratio):
            raise Error("A soft tissue Poisson ratio must be finite")
        if self.poisson_ratio < 0:
            raise Error("A soft tissue Poisson ratio cannot be negative")
        if self.poisson_ratio > 1:
            raise Error("A soft tissue Poisson ratio cannot exceed one")


@fieldwise_init
struct SoftMass(ImplicitlyCopyable):
    """Sampled envelope volume and wet-tissue mass of one soft solid."""

    var envelope: Volume
    var mass: Mass

    def weight(self, gravity: Acceleration = STANDARD_GRAVITY) -> Force:
        """Return the Earth weight of this wet-tissue mass.

        Args:
            gravity: Acceleration of free fall. Standard gravity is the
                default.

        Returns:
            `mass * gravity`, in newtons when `gravity` is standard.
        """
        return self.mass * gravity


def cartilage_tissue() -> SoftTissue:
    """Return adult knee articular cartilage.

    Wet density is 1.12 g/cm^3. Water fraction is 0.75. Compressive
    modulus is 0.70 MPa, a named template inside the published range.
    Poisson's ratio is 0.45.

    Returns:
        The cartilage template.
    """
    return SoftTissue(
        CARTILAGE,
        Density(1.12, GRAM_PER_CUBIC_CENTIMETER),
        Float32(0.75),
        Pressure(0.70, MEGAPASCAL),
        Float32(0.45),
    )


def ligament_tissue() -> SoftTissue:
    """Return adult collateral-ligament connective tissue.

    Wet density is 1.12 g/cm^3. Water fraction is 0.65. Longitudinal
    modulus is 300 MPa, a named template. Poisson's ratio is 0.40.

    Returns:
        The ligament template.
    """
    return SoftTissue(
        LIGAMENT,
        Density(1.12, GRAM_PER_CUBIC_CENTIMETER),
        Float32(0.65),
        Pressure(300.0, MEGAPASCAL),
        Float32(0.40),
    )


def meniscus_tissue() -> SoftTissue:
    """Return adult meniscal fibrocartilage.

    Wet density is 1.10 g/cm^3. Water fraction is 0.70. Compressive
    modulus is 0.20 MPa, a named template. Poisson's ratio is 0.30.

    Returns:
        The meniscus template.
    """
    return SoftTissue(
        MENISCUS,
        Density(1.10, GRAM_PER_CUBIC_CENTIMETER),
        Float32(0.70),
        Pressure(0.20, MEGAPASCAL),
        Float32(0.30),
    )


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
