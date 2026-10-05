# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Building materials: physical properties and a look, side by side.

A structural solver reads the density, the elastic modulus, Poisson's
ratio and the strength. A thermal solver reads the conductivity, the
specific heat and the density. A renderer reads the base color, the
roughness and the metalness. All of them read one `BuildingMaterial`, so
a concrete slab is the same concrete in every view.

The library functions give typical values for common materials. They are
not design values: a project must use the values of its own products and
codes. The thermal values follow the tables of ISO 10456 and the ASHRAE
Handbook of Fundamentals. The elastic values are typical of the
materials in Eurocodes 2, 3 and 5.
"""

from std.math import isfinite
from units.si import (
    Density64,
    GIGAPASCAL,
    JOULE_PER_KILOGRAM_KELVIN,
    KILOGRAM_PER_CUBIC_METER,
    MEGAPASCAL,
    PER_KELVIN,
    Pressure64,
    SpecificHeatCapacity64,
    ThermalConductivity64,
    ThermalExpansion64,
    WATT_PER_METER_KELVIN,
)


@fieldwise_init
struct Look(ImplicitlyCopyable):
    """How a material looks: a physically based base color and finish."""

    # The sRGB base color, each channel from zero to one.
    var red: Float32
    var green: Float32
    var blue: Float32
    # From zero, a mirror, to one, fully rough.
    var roughness: Float32
    # Zero for a dielectric, one for a metal.
    var metalness: Float32
    # Zero for opaque, up to one for clear glass.
    var transmission: Float32


struct BuildingMaterial(Copyable, Movable):
    """A material's name, physical properties and look."""

    var name: String
    var density: Density64
    var elastic_modulus: Pressure64
    var poisson_ratio: Float64
    # The characteristic strength: yield for a metal, compressive for
    # concrete and masonry, bending for timber. Zero when not structural.
    var strength: Pressure64
    var conductivity: ThermalConductivity64
    var specific_heat: SpecificHeatCapacity64
    var thermal_expansion: ThermalExpansion64
    var look: Look

    def __init__(
        out self,
        var name: String,
        density: Density64,
        elastic_modulus: Pressure64,
        poisson_ratio: Float64,
        strength: Pressure64,
        conductivity: ThermalConductivity64,
        specific_heat: SpecificHeatCapacity64,
        thermal_expansion: ThermalExpansion64,
        look: Look,
    ):
        """Create a material. Call `check` before use.

        Args:
            name: A name for people and for exchange files.
            density: The mass per volume.
            elastic_modulus: Young's modulus.
            poisson_ratio: Poisson's ratio, from zero to under one half.
            strength: The characteristic strength, or zero.
            conductivity: The thermal conductivity.
            specific_heat: The specific heat capacity.
            thermal_expansion: The linear coefficient of thermal expansion.
            look: How it renders.
        """
        self.name = name^
        self.density = density
        self.elastic_modulus = elastic_modulus
        self.poisson_ratio = poisson_ratio
        self.strength = strength
        self.conductivity = conductivity
        self.specific_heat = specific_heat
        self.thermal_expansion = thermal_expansion
        self.look = look

    def check(self) raises:
        """Refuse a material that no physical material can be.

        Raises:
            Error: If the density, modulus, conductivity or specific heat
                is not positive and finite, Poisson's ratio is not from
                zero to under one half, the strength or the expansion is
                negative or not finite, or a look channel is outside zero
                to one.
        """
        var positives = [
            self.density.value,
            self.elastic_modulus.value,
            self.conductivity.value,
            self.specific_heat.value,
        ]
        for i in range(len(positives)):  # pragma: no branch
            if not (positives[i] > 0 and isfinite(positives[i])):
                raise Error(
                    "A material's density, modulus, conductivity and"
                    " specific heat must be positive and finite"
                )
        if not (self.poisson_ratio >= 0 and self.poisson_ratio < 0.5):
            raise Error("Poisson's ratio must be from zero to under one half")
        var non_negative = [self.strength.value, self.thermal_expansion.value]
        for i in range(len(non_negative)):  # pragma: no branch
            if not (non_negative[i] >= 0 and isfinite(non_negative[i])):
                raise Error(
                    "A material's strength and expansion must be zero or"
                    " more and finite"
                )
        var channels = [
            self.look.red,
            self.look.green,
            self.look.blue,
            self.look.roughness,
            self.look.metalness,
            self.look.transmission,
        ]
        for i in range(len(channels)):  # pragma: no branch
            if not (channels[i] >= 0 and channels[i] <= 1):
                raise Error("A look channel must be from zero to one")

    def shear_modulus(self) -> Pressure64:
        """Return the shear modulus of an isotropic material.

        Returns:
            E / (2 (1 + nu)).
        """
        return self.elastic_modulus.scaled(1 / (2 * (1 + self.poisson_ratio)))


def _material(
    name: String,
    density: Float64,
    modulus_gpa: Float64,
    poisson: Float64,
    strength_mpa: Float64,
    conductivity: Float64,
    specific_heat: Float64,
    expansion: Float64,
    look: Look,
) -> BuildingMaterial:
    """Return a library material from plain SI numbers."""
    return BuildingMaterial(
        name,
        Density64(density, KILOGRAM_PER_CUBIC_METER),
        Pressure64(modulus_gpa, GIGAPASCAL),
        poisson,
        Pressure64(strength_mpa, MEGAPASCAL),
        ThermalConductivity64(conductivity, WATT_PER_METER_KELVIN),
        SpecificHeatCapacity64(specific_heat, JOULE_PER_KILOGRAM_KELVIN),
        ThermalExpansion64(expansion, PER_KELVIN),
        look,
    )


def concrete() -> BuildingMaterial:
    """Return reinforced normal-weight concrete.

    Returns:
        2400 kg/m³, 30 GPa, a compressive strength of 30 MPa and a
        conductivity of 2.3 W/(m K).
    """
    return _material(
        "concrete",
        2400,
        30,
        0.2,
        30,
        2.3,
        1000,
        10e-6,
        Look(0.62, 0.61, 0.58, 0.9, 0, 0),
    )


def steel() -> BuildingMaterial:
    """Return structural steel.

    Returns:
        7850 kg/m³, 200 GPa, a yield strength of 345 MPa and a
        conductivity of 50 W/(m K).
    """
    return _material(
        "steel",
        7850,
        200,
        0.3,
        345,
        50,
        450,
        12e-6,
        Look(0.56, 0.57, 0.58, 0.45, 1, 0),
    )


def timber() -> BuildingMaterial:
    """Return glued laminated softwood timber, along the grain.

    Returns:
        500 kg/m³, 11 GPa, a bending strength of 24 MPa and a
        conductivity of 0.13 W/(m K).
    """
    return _material(
        "timber",
        500,
        11,
        0.3,
        24,
        0.13,
        1600,
        5e-6,
        Look(0.66, 0.49, 0.31, 0.7, 0, 0),
    )


def brick() -> BuildingMaterial:
    """Return fired clay brick masonry.

    Returns:
        1800 kg/m³, 10 GPa, a compressive strength of 10 MPa and a
        conductivity of 0.77 W/(m K).
    """
    return _material(
        "brick",
        1800,
        10,
        0.2,
        10,
        0.77,
        840,
        6e-6,
        Look(0.6, 0.29, 0.2, 0.85, 0, 0),
    )


def gypsum_board() -> BuildingMaterial:
    """Return gypsum plasterboard.

    Returns:
        800 kg/m³ and a conductivity of 0.25 W/(m K). It is not
        structural.
    """
    return _material(
        "gypsum board",
        800,
        2,
        0.25,
        0,
        0.25,
        1000,
        16e-6,
        Look(0.92, 0.91, 0.88, 0.95, 0, 0),
    )


def mineral_wool() -> BuildingMaterial:
    """Return mineral wool insulation.

    Returns:
        30 kg/m³ and a conductivity of 0.035 W/(m K). It is not
        structural.
    """
    return _material(
        "mineral wool",
        30,
        0.0005,
        0,
        0,
        0.035,
        1030,
        0,
        Look(0.87, 0.78, 0.45, 1, 0, 0),
    )


def glass() -> BuildingMaterial:
    """Return soda-lime float glass.

    Returns:
        2500 kg/m³, 70 GPa and a conductivity of 1.0 W/(m K).
    """
    return _material(
        "glass",
        2500,
        70,
        0.22,
        0,
        1.0,
        750,
        9e-6,
        Look(0.82, 0.9, 0.92, 0.05, 0, 0.9),
    )


def aluminum() -> BuildingMaterial:
    """Return an aluminum alloy for frames and cladding.

    Returns:
        2700 kg/m³, 70 GPa, a yield strength of 160 MPa and a
        conductivity of 160 W/(m K).
    """
    return _material(
        "aluminum",
        2700,
        70,
        0.33,
        160,
        160,
        900,
        23e-6,
        Look(0.77, 0.78, 0.8, 0.35, 1, 0),
    )
