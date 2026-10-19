# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Masonry: its weight, its strength and its stiffness.

The strength follows EN 1996-1-1 (Eurocode 6), clause 3.6.1.2, equation 3.1:
fk = K fb^0.7 fm^0.3, where fb is the normalized compressive strength of the
units and fm is the compressive strength of the mortar, both in MPa. The
elastic modulus is 1000 fk, clause 3.7.2. The design strength is fk divided
by a partial factor. The library values are typical values. They are not
design values for a surveyed wall.
"""

from extensions.geotech.quantities import UnitWeight64
from math.finite import require_positive_finite
from std.math import pow
from units.si import (
    Acceleration64,
    Density64,
    MEGAPASCAL,
    Pressure64,
)
from units.si import KILOGRAM_PER_CUBIC_METER

# Standard gravity, the conventional value of the 3rd CGPM (1901).
comptime GRAVITY = Acceleration64(9.80665)


@fieldwise_init
struct Masonry(Copyable, Movable):
    """A masonry and the numbers that structural checks read."""

    # What the masonry is.
    var name: String
    # The mass of a cubic meter of finished masonry, mortar included.
    var density: Density64
    # The characteristic compressive strength, fk.
    var compressive: Pressure64
    # The secant elastic modulus.
    var modulus: Pressure64
    # The friction coefficient of a bed joint, the tangent of its angle.
    var friction: Float64

    def check(self) raises:
        """Refuse a masonry that has a number no real masonry has.

        Nothing. The call returns when every number is positive and finite.

        Raises:
            Error: If the density, strength, modulus or friction is not
                positive and finite.
        """
        require_positive_finite(
            self.density.value, "A masonry density must be positive"
        )
        require_positive_finite(
            self.compressive.value, "A masonry strength must be positive"
        )
        require_positive_finite(
            self.modulus.value, "A masonry modulus must be positive"
        )
        require_positive_finite(
            self.friction, "A masonry friction must be positive"
        )

    def unit_weight(self) -> UnitWeight64:
        """Return the weight of a cubic meter.

        Returns:
            The density times standard gravity.
        """
        return self.density * GRAVITY

    def design_strength(self, partial: Float64) raises -> Pressure64:
        """Return the design compressive strength, fk over a partial factor.

        Args:
            partial: The partial factor on the material, 1 or more.

        Returns:
            The design strength.

        Raises:
            Error: If the partial factor is less than 1 or not finite.
        """
        if not (partial >= 1.0 and partial < 1.0e9):
            raise Error("A partial factor must be 1 or more")
        return self.compressive.scaled(1.0 / partial)


def characteristic_strength(
    unit: Pressure64, mortar: Pressure64, k: Float64
) raises -> Pressure64:
    """Return the characteristic compressive strength of masonry.

    EN 1996-1-1, equation 3.1: fk = K fb^0.7 fm^0.3. K is 0.55 for clay
    units of group 1 in general purpose mortar, Table 3.3.

    Args:
        unit: The normalized compressive strength of the units, fb.
        mortar: The compressive strength of the mortar, fm.
        k: The constant K of the unit and mortar types.

    Returns:
        The strength fk.

    Raises:
        Error: If a strength or K is not positive and finite.
    """
    require_positive_finite(unit.value, "A unit strength must be positive")
    require_positive_finite(mortar.value, "A mortar strength must be positive")
    require_positive_finite(k, "The constant K must be positive")
    var fb = unit.to(MEGAPASCAL)
    var fm = mortar.to(MEGAPASCAL)
    return Pressure64(k * pow(fb, 0.7) * pow(fm, 0.3), MEGAPASCAL)


def clay_brick_masonry() raises -> Masonry:
    """Return handmade clay brick laid in lime mortar, as a 19th-century
    castle wall has it.

    Returns:
        1800 kg/m3, units of 15 MPa, mortar of 2.5 MPa, K of 0.55 and a bed
        joint friction of 0.6. The strength is about 4.8 MPa.

    Raises:
        Error: Never in practice. The fixed numbers are valid.
    """
    var fk = characteristic_strength(
        Pressure64(15.0, MEGAPASCAL), Pressure64(2.5, MEGAPASCAL), 0.55
    )
    return Masonry(
        "clay brick in lime mortar",
        Density64(1800.0, KILOGRAM_PER_CUBIC_METER),
        fk,
        fk.scaled(1000.0),
        0.6,
    )


def dressed_limestone() raises -> Masonry:
    """Return dressed limestone, as the string courses and copings have it.

    Returns:
        2300 kg/m3, units of 40 MPa, mortar of 5 MPa, K of 0.45 and a bed
        joint friction of 0.65.

    Raises:
        Error: Never in practice. The fixed numbers are valid.
    """
    var fk = characteristic_strength(
        Pressure64(40.0, MEGAPASCAL), Pressure64(5.0, MEGAPASCAL), 0.45
    )
    return Masonry(
        "dressed limestone",
        Density64(2300.0, KILOGRAM_PER_CUBIC_METER),
        fk,
        fk.scaled(1000.0),
        0.65,
    )
