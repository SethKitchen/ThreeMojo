# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Published wet density and moduli for named hydrated tissues.

These are mammalian soft tissues. The humanoid and the animals both
read them; a species-specific value overrides one where a source gives
it.

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

from std.math import isfinite
from units.si import (
    STANDARD_GRAVITY,
    Acceleration,
    Density,
    Force,
    GRAM_PER_CUBIC_CENTIMETER,
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
        if self == HAIR:
            return True
        return self == ADIPOSE


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
# Subcutaneous and intermuscular fat.
comptime ADIPOSE = SoftTissueKind(11)


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


def adipose_tissue() -> SoftTissue:
    """Return adult adipose tissue: subcutaneous and intermuscular fat.

    Wet density is 0.92 g/cm^3, a common adult value; lipid alone is
    about 0.90 and the cells' water brings the tissue up. Water fraction
    is 0.15. Compressive modulus is 0.002 MPa, a soft named template.
    Poisson's ratio is 0.49: fat is nearly incompressible.

    Returns:
        The adipose template.
    """
    return SoftTissue(
        ADIPOSE,
        Density(0.92, GRAM_PER_CUBIC_CENTIMETER),
        Float32(0.15),
        Pressure(0.002, MEGAPASCAL),
        Float32(0.49),
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


def vessel_tissue(arterial: Bool) -> SoftTissue:
    """Return the tissue selected by a validated vessel classification.

    Args:
        arterial: True for an artery, False for a vein. The caller must
            validate its region-specific vessel before classifying it.

    Returns:
        The arterial or venous template.
    """
    if arterial:
        return arterial_tissue()
    return venous_tissue()


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
