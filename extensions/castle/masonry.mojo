# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Masonry, as Eurocode 6 (EN 1996-1-1) states its strength and stiffness.

The characteristic compressive strength of masonry follows equation (3.2),

    f_k = K f_b^0.7 f_m^0.3

where `f_b` is the normalized mean compressive strength of the units and
`f_m` that of the mortar, in N/mm^2, and `K` is a constant of the unit group
and the mortar. For clay units of group 1 laid in general purpose mortar the
recommended `K` is 0.55. A national annex can change it. The mortar is not
stronger than the unit.

The design strength is `f_k` over the partial factor of the material. The
modulus of elasticity is 1000 `f_k`, and the shear modulus is 0.4 of it. The
characteristic shear strength is

    f_vk = f_vk0 + 0.4 sigma_d,  at most 0.065 f_b,

for masonry with filled head joints, where `sigma_d` is the design
compressive stress across the joint and `f_vk0` the initial shear strength.

`historic_brick` is an assumption, and says so. No test of the masonry of
Wijnendale Castle is published. Its strengths are those of a sound
nineteenth-century solid clay brick in lime mortar, and its provenance is
`ESTIMATED`. A project that relied on the figures would test the masonry.
"""

from std.math import isfinite, pow
from extensions.castle.kinds import ESTIMATED, Provenance
from extensions.geotech.quantities import UnitWeight64
from units.si import (
    Density64,
    KILOGRAM_PER_CUBIC_METER,
    MEGAPASCAL,
    Pressure64,
)

# Standard gravity, in m/s^2, in Float64.
comptime _GRAVITY = 9.80665
# The exponents of equation (3.2) for general purpose mortar.
comptime _UNIT_EXPONENT = 0.7
comptime _MORTAR_EXPONENT = 0.3
# The modulus of elasticity over the characteristic strength, 3.7.2(2).
comptime _MODULUS_FACTOR = 1000.0
# The shear modulus over the modulus of elasticity, 3.7.3.
comptime _SHEAR_MODULUS_FACTOR = 0.4
# The friction coefficient of the shear strength, and its limit over f_b.
comptime _SHEAR_FRICTION = 0.4
comptime _SHEAR_LIMIT = 0.065


@fieldwise_init
struct Masonry(ImplicitlyCopyable):
    """A masonry of units and mortar, and where its figures came from."""

    # The normalized mean compressive strength of the units, f_b.
    var unit_strength: Pressure64
    # The compressive strength of the mortar, f_m.
    var mortar_strength: Pressure64
    # The constant K of equation (3.2).
    var k: Float64
    # The density of the masonry.
    var density: Density64
    # The partial factor of the material, gamma_M.
    var partial_factor: Float64
    # The initial shear strength, f_vk0.
    var initial_shear: Pressure64
    # How these figures were found.
    var provenance: Provenance

    def check(self) raises:
        """Refuse a masonry that cannot be analyzed.

        Raises:
            Error: If a strength is not positive and finite, the mortar is
                stronger than the unit, K or the partial factor is not
                positive and finite, the density is not positive and
                finite, the initial shear strength is negative or not
                finite, or the provenance is not valid.
        """
        if not (
            isfinite(self.unit_strength.value) and self.unit_strength.value > 0
        ):
            raise Error("A unit strength must be positive and finite")
        if not (
            isfinite(self.mortar_strength.value)
            and self.mortar_strength.value > 0
        ):
            raise Error("A mortar strength must be positive and finite")
        if self.mortar_strength.value > self.unit_strength.value:
            raise Error("The mortar must not be stronger than the unit")
        if not (isfinite(self.k) and self.k > 0):
            raise Error("The constant K must be positive and finite")
        if not (isfinite(self.density.value) and self.density.value > 0):
            raise Error("A density must be positive and finite")
        if not (isfinite(self.partial_factor) and self.partial_factor > 0):
            raise Error("A partial factor must be positive and finite")
        if not (
            isfinite(self.initial_shear.value) and self.initial_shear.value >= 0
        ):
            raise Error("An initial shear strength must be zero or more")
        if not self.provenance.is_valid():
            raise Error("A masonry's provenance must be one of the four")

    def characteristic_strength(self) raises -> Pressure64:
        """Return the characteristic compressive strength, f_k.

        Returns:
            K f_b^0.7 f_m^0.3.

        Raises:
            Error: If the masonry is not valid.
        """
        self.check()
        var unit = self.unit_strength.to(MEGAPASCAL)
        var mortar = self.mortar_strength.to(MEGAPASCAL)
        var megapascal = (
            self.k * pow(unit, _UNIT_EXPONENT) * pow(mortar, _MORTAR_EXPONENT)
        )
        return Pressure64(megapascal, MEGAPASCAL)

    def design_strength(self) raises -> Pressure64:
        """Return the design compressive strength, f_d.

        Returns:
            The characteristic strength f_k over the partial factor.

        Raises:
            Error: If the masonry is not valid.
        """
        return self.characteristic_strength().scaled(1.0 / self.partial_factor)

    def elastic_modulus(self) raises -> Pressure64:
        """Return the modulus of elasticity, E.

        Returns:
            1000 f_k.

        Raises:
            Error: If the masonry is not valid.
        """
        return self.characteristic_strength().scaled(_MODULUS_FACTOR)

    def shear_modulus(self) raises -> Pressure64:
        """Return the shear modulus, G.

        Returns:
            0.4 E.

        Raises:
            Error: If the masonry is not valid.
        """
        return self.elastic_modulus().scaled(_SHEAR_MODULUS_FACTOR)

    def shear_strength(self, stress: Pressure64) raises -> Pressure64:
        """Return the characteristic shear strength, f_vk.

        Args:
            stress: The design compressive stress across the joint,
                sigma_d. It is zero or more.

        Returns:
            The initial shear strength f_vk0 plus 0.4 sigma_d, at most
            0.065 f_b.

        Raises:
            Error: If the masonry is not valid, or the stress is negative
                or not finite.
        """
        self.check()
        if not (isfinite(stress.value) and stress.value >= 0):
            raise Error("A compressive stress must be zero or more and finite")
        var strength = self.initial_shear.value + _SHEAR_FRICTION * stress.value
        var limit = _SHEAR_LIMIT * self.unit_strength.value
        return Pressure64(min(strength, limit))

    def unit_weight(self) raises -> UnitWeight64:
        """Return the weight of the masonry for each unit of volume.

        Returns:
            The density times standard gravity.

        Raises:
            Error: If the masonry is not valid.
        """
        self.check()
        return UnitWeight64(self.density.value * _GRAVITY)


def historic_brick() -> Masonry:
    """Return the masonry assumed for Wijnendale Castle.

    A sound solid clay brick of group 1 at 20 N/mm^2 in a lime mortar of
    2.5 N/mm^2, with K of 0.55 for general purpose mortar, a density of
    1800 kg/m^3, a partial factor of 2.5 and an initial shear strength of
    0.20 N/mm^2. The characteristic strength is then about 5.9 N/mm^2.
    Every figure is an assumption, and the provenance is `ESTIMATED`.

    Returns:
        The masonry.
    """
    return Masonry(
        Pressure64(20.0, MEGAPASCAL),
        Pressure64(2.5, MEGAPASCAL),
        0.55,
        Density64(1800.0, KILOGRAM_PER_CUBIC_METER),
        2.5,
        Pressure64(0.2, MEGAPASCAL),
        ESTIMATED,
    )
