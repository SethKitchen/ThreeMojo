# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The strength of a reinforced concrete strip of a wall, by AASHTO LRFD.

A `ConcreteStrip` is a unit width of a stem, heel or toe: its thickness,
one layer of tension bars and the cover over them.

- `flexural_resistance` is phi Mn for a rectangular stress block
  (Art. 5.7.3.2), phi = 0.90.
- `cracking_moment` is fr S with fr = 0.37 sqrt(f'c) ksi, as the 2010
  edition's minimum-reinforcement rule uses it (Art. 5.7.3.3.2).
- `shear_resistance` is phi Vc of a member without stirrups by the
  general procedure (Art. 5.8.3.4.2), phi = 0.90, with the crack-spacing
  parameter of a member without transverse reinforcement.

The shear equations are in kips and inches, as the code states them; the
functions take and return SI quantities.
"""

from std.math import isfinite, sqrt
from extensions.geotech.quantities import KSI, MomentPerLength64
from units.si import Length64, LineLoad64, Pressure64

comptime _PHI_FLEXURE = 0.90
comptime _PHI_SHEAR = 0.90
comptime _STEEL_MODULUS_KSI = 29000.0
comptime _INCH = 0.0254


@fieldwise_init
struct ConcreteStrip(ImplicitlyCopyable):
    """A unit width of a reinforced concrete slab or wall."""

    var thickness: Length64
    # The clear cover over the tension bars.
    var cover: Length64
    var bar_diameter: Length64
    # The bar area per unit width, which has the dimension of a length.
    var steel: Length64
    # f'c.
    var concrete_strength: Pressure64
    # fy.
    var steel_strength: Pressure64

    def check(self) raises:
        """Refuse a strip that cannot be analyzed.

        Raises:
            Error: If a value is not finite, a strength or the thickness is
                not positive, or the bars lie outside the section.
        """
        var values: List[Float64] = [
            self.thickness.value,
            self.cover.value,
            self.bar_diameter.value,
            self.steel.value,
            self.concrete_strength.value,
            self.steel_strength.value,
        ]
        # The list holds six values, so the loop always runs.
        for v in values:  # pragma: no branch
            if not (isfinite(v) and v >= 0):
                raise Error("A strip's values must be zero or more and finite")
        if not (
            self.thickness.value > 0
            and self.concrete_strength.value > 0
            and self.steel_strength.value > 0
        ):
            raise Error("A strip needs a thickness and strengths")
        if self.depth().value <= 0:
            raise Error("A strip's bars must lie inside it")

    def depth(self) -> Length64:
        """Return the effective depth to the bars' center.

        Returns:
            The thickness less the cover and half a bar.
        """
        return self.thickness - self.cover - self.bar_diameter.scaled(0.5)

    def block_depth(self) -> Length64:
        """Return the depth of the equivalent stress block.

        Returns:
            The depth a = As fy / (0.85 f'c b).
        """
        return Length64(
            self.steel.value
            * self.steel_strength.value
            / (0.85 * self.concrete_strength.value)
        )


def flexural_resistance(strip: ConcreteStrip) raises -> MomentPerLength64:
    """Return the factored flexural resistance, phi Mn.

    Args:
        strip: The strip.

    Returns:
        The factored resistance, phi As fy (d - a / 2), per unit width.

    Raises:
        Error: If the strip is not valid.
    """
    strip.check()
    var d = strip.depth().value
    var a = strip.block_depth().value
    return MomentPerLength64(
        _PHI_FLEXURE
        * strip.steel.value
        * strip.steel_strength.value
        * (d - a / 2)
    )


def cracking_moment(strip: ConcreteStrip) raises -> MomentPerLength64:
    """Return the cracking moment of the gross section.

    Args:
        strip: The strip.

    Returns:
        0.37 sqrt(f'c [ksi]) ksi times h^2 / 6, per unit width.

    Raises:
        Error: If the strip is not valid.
    """
    strip.check()
    var fr = Pressure64(0.37 * sqrt(strip.concrete_strength.to(KSI)), KSI)
    var h = strip.thickness.value
    return MomentPerLength64(fr.value * h * h / 6)


def shear_resistance(
    strip: ConcreteStrip, shear: LineLoad64, moment: MomentPerLength64
) raises -> LineLoad64:
    """Return the factored shear resistance of the concrete, phi Vc.

    Args:
        strip: The strip.
        shear: The factored shear on it.
        moment: The factored moment with it.

    Returns:
        The factored resistance, phi 0.0316 beta sqrt(f'c) b dv, per unit
        width.

    Raises:
        Error: If the strip is not valid or a load is not finite.
    """
    strip.check()
    if not (isfinite(shear.value) and isfinite(moment.value)):
        raise Error("A shear and moment must be finite")
    # Work per 12 in of width, in kips and inches.
    var b = 12.0
    var h = strip.thickness.value / _INCH
    var d = strip.depth().value / _INCH
    var fc = strip.concrete_strength.to(KSI)
    var fy = strip.steel_strength.to(KSI)
    var area = strip.steel.value / _INCH * b
    var a = area * fy / (0.85 * fc * b)
    var dv = max(d - a / 2, 0.9 * d, 0.72 * h)
    var to_kip = 1.0 / 4448.2216152605
    var vu = abs(shear.value) * 0.3048 * to_kip
    var mu = abs(moment.value) * 0.3048 * to_kip * 12.0
    var mu_eff = max(mu, vu * dv)
    var strain = Float64(0.006)
    if area > 0:
        strain = (mu_eff / dv + vu) / (_STEEL_MODULUS_KSI * area)
    strain = min(max(strain, -0.0004), 0.006)
    var sxe = min(max(dv * 1.38 / (0.75 + 0.63), 12.0), 80.0)
    var beta = 4.8 / (1 + 750 * strain) * 51 / (39 + sxe)
    var vc = 0.0316 * beta * sqrt(fc) * b * dv
    # Kips per foot of width back to newtons per meter.
    return LineLoad64(_PHI_SHEAR * vc / to_kip / 0.3048)
