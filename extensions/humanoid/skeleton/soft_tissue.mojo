# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Published wet density and moduli for named hydrated tissues of the limb.

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

Muscle wet density 1.06 g/cm^3 follows Mendez and Keys, *Density and
composition of mammalian muscle*, Metabolism 1960, as a named adult
template. Water fraction 0.75 is a named template.

Tendon wet density 1.12 g/cm^3 and water fraction 0.62 are named adult
templates for hydrated dense tendon.

Arterial and venous wet density 1.06 g/cm^3 is a named whole-blood
template. Lymph wet density 1.01 g/cm^3 is a named near-water template.
Nerve wet density 1.04 g/cm^3 is a named adult template. Skin wet density
1.10 g/cm^3 is a named dermis template. Hair wet density 1.32 g/cm^3 is a
named keratin template.

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
    a named hydrated tissue is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named hydrated tissue."""
        if self == CARTILAGE:
            return True
        if self == LIGAMENT:
            return True
        if self == MENISCUS:
            return True
        if self == MUSCLE:
            return True
        if self == TENDON:
            return True
        if self == ARTERIAL:
            return True
        if self == VENOUS:
            return True
        if self == LYMPH:
            return True
        if self == NERVE:
            return True
        if self == SKIN:
            return True
        return self == HAIR


# Hyaline articular cartilage of the knee.
comptime CARTILAGE = SoftTissueKind(0)
# Dense collagenous collateral ligament.
comptime LIGAMENT = SoftTissueKind(1)
# Fibrocartilage of a meniscus.
comptime MENISCUS = SoftTissueKind(2)
# Skeletal muscle belly.
comptime MUSCLE = SoftTissueKind(3)
# Dense collagenous tendon or fascia.
comptime TENDON = SoftTissueKind(4)
# Arterial wall and lumen as one filled tube.
comptime ARTERIAL = SoftTissueKind(5)
# Venous wall and lumen as one filled tube.
comptime VENOUS = SoftTissueKind(6)
# Lymph and a lymph-node cortex.
comptime LYMPH = SoftTissueKind(7)
# Peripheral nerve trunk.
comptime NERVE = SoftTissueKind(8)
# Dermis and thin epidermis as one envelope.
comptime SKIN = SoftTissueKind(9)
# Keratin hair shaft.
comptime HAIR = SoftTissueKind(10)


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
            raise Error("Soft tissue must be a named hydrated tissue")
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


def muscle_tissue() -> SoftTissue:
    """Return adult skeletal muscle.

    Wet density is 1.06 g/cm^3. Water fraction is 0.75. Passive
    modulus is 0.02 MPa, a named template. Poisson's ratio is 0.45.

    Returns:
        The muscle template.
    """
    return SoftTissue(
        MUSCLE,
        Density(1.06, GRAM_PER_CUBIC_CENTIMETER),
        Float32(0.75),
        Pressure(0.02, MEGAPASCAL),
        Float32(0.45),
    )


def tendon_tissue() -> SoftTissue:
    """Return adult dense tendon.

    Wet density is 1.12 g/cm^3. Water fraction is 0.62. Longitudinal
    modulus is 500 MPa, a named template. Poisson's ratio is 0.40.

    Returns:
        The tendon template.
    """
    return SoftTissue(
        TENDON,
        Density(1.12, GRAM_PER_CUBIC_CENTIMETER),
        Float32(0.62),
        Pressure(500.0, MEGAPASCAL),
        Float32(0.40),
    )


def arterial_tissue() -> SoftTissue:
    """Return adult arterial tissue as a blood-filled tube.

    Wet density is 1.06 g/cm^3. Water fraction is 0.80. Circumferential
    modulus is 0.50 MPa, a named template. Poisson's ratio is 0.45.

    Returns:
        The arterial template.
    """
    return SoftTissue(
        ARTERIAL,
        Density(1.06, GRAM_PER_CUBIC_CENTIMETER),
        Float32(0.80),
        Pressure(0.50, MEGAPASCAL),
        Float32(0.45),
    )


def venous_tissue() -> SoftTissue:
    """Return adult venous tissue as a blood-filled tube.

    Wet density is 1.06 g/cm^3. Water fraction is 0.80. Circumferential
    modulus is 0.30 MPa, a named template. Poisson's ratio is 0.45.

    Returns:
        The venous template.
    """
    return SoftTissue(
        VENOUS,
        Density(1.06, GRAM_PER_CUBIC_CENTIMETER),
        Float32(0.80),
        Pressure(0.30, MEGAPASCAL),
        Float32(0.45),
    )


def lymph_tissue() -> SoftTissue:
    """Return adult lymph and node cortex.

    Wet density is 1.01 g/cm^3. Water fraction is 0.95. Compressive
    modulus is 0.02 MPa, a named template. Poisson's ratio is 0.45.

    Returns:
        The lymph template.
    """
    return SoftTissue(
        LYMPH,
        Density(1.01, GRAM_PER_CUBIC_CENTIMETER),
        Float32(0.95),
        Pressure(0.02, MEGAPASCAL),
        Float32(0.45),
    )


def nerve_tissue() -> SoftTissue:
    """Return adult peripheral-nerve trunk.

    Wet density is 1.04 g/cm^3. Water fraction is 0.77. Longitudinal
    modulus is 0.50 MPa, a named template. Poisson's ratio is 0.40.

    Returns:
        The nerve template.
    """
    return SoftTissue(
        NERVE,
        Density(1.04, GRAM_PER_CUBIC_CENTIMETER),
        Float32(0.77),
        Pressure(0.50, MEGAPASCAL),
        Float32(0.40),
    )


def skin_tissue() -> SoftTissue:
    """Return adult dermis with a thin epidermis.

    Wet density is 1.10 g/cm^3. Water fraction is 0.70. Compressive
    modulus is 0.20 MPa, a named template. Poisson's ratio is 0.45.

    Returns:
        The skin template.
    """
    return SoftTissue(
        SKIN,
        Density(1.10, GRAM_PER_CUBIC_CENTIMETER),
        Float32(0.70),
        Pressure(0.20, MEGAPASCAL),
        Float32(0.45),
    )


def hair_tissue() -> SoftTissue:
    """Return adult keratin hair shaft.

    Wet density is 1.32 g/cm^3. Water fraction is 0.12. Longitudinal
    modulus is 2000 MPa, a named template. Poisson's ratio is 0.35.

    Returns:
        The hair template.
    """
    return SoftTissue(
        HAIR,
        Density(1.32, GRAM_PER_CUBIC_CENTIMETER),
        Float32(0.12),
        Pressure(2000.0, MEGAPASCAL),
        Float32(0.35),
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
