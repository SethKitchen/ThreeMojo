# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The mechanics of a thin coating on a thick substrate.

A coating that is deposited hot and then cooled holds a residual stress.
The coating and the substrate shrink by different amounts, and the thick
substrate sets the strain. The coating is then in equal biaxial stress:

    sigma = E_c / (1 - nu_c) * (alpha_s - alpha_c) * (T_dep - T_service)

Here a positive stress is compression in the coating. Diamond expands less
than cemented carbide, so a diamond coating on a carbide tool cools into
compression. The expansion coefficients are means over the cooling range.

A stressed coating stores elastic energy. A coating can peel from an edge
when the energy a delamination releases reaches the fracture energy of the
interface. For a straight front in plane strain, Hutchinson and Suo (1992)
give the energy release rate

    G = (1 - nu_c^2) * sigma^2 * h / (2 E_c)

So the thickest coating that does not peel is

    h = 2 E_c Gamma / ((1 - nu_c^2) * sigma^2)

The interface fracture energy Gamma depends on the surface preparation.
Measure it on the real surface, for example with an indentation or a
scratch test. Do not use a handbook value for a design.
"""

from std.math import inf, isfinite
from extensions.chemistry.quantities import FractureEnergy64
from units.si import Length64, Pressure64, ThermalExpansion64
from units.temperature import Temperature64


@fieldwise_init
struct ElasticLayer(ImplicitlyCopyable):
    """The elastic and thermal properties of a coating or a substrate."""

    # Young's modulus.
    var modulus: Pressure64
    # Poisson's ratio.
    var poisson: Float64
    # The mean linear expansion coefficient over the cooling range.
    var expansion: ThermalExpansion64

    def check(self) raises:
        """Refuse properties that are not physical.

        Nothing. The call returns when the properties are physical.

        Raises:
            Error: If the modulus is not finite and positive, Poisson's
                ratio is not above -1 and below 0.5, or the expansion is
                not finite.
        """
        if not (isfinite(self.modulus.value) and self.modulus.value > 0):
            raise Error("A modulus must be finite and positive")
        if not (self.poisson > -1 and self.poisson < 0.5):
            raise Error("Poisson's ratio must be above -1 and below 0.5")
        if not isfinite(self.expansion.value):
            raise Error("An expansion coefficient must be finite")


def mismatch_stress(
    coating: ElasticLayer,
    substrate: ElasticLayer,
    deposition: Temperature64,
    service: Temperature64,
) raises -> Pressure64:
    """Return the residual stress in a coating from cooling.

    Args:
        coating: The coating.
        substrate: The substrate, much thicker than the coating.
        deposition: The temperature the coating was deposited at.
        service: The temperature it is used at.

    Returns:
        The equal biaxial stress in the coating. Positive is compression.

    Raises:
        Error: If a layer's properties or a temperature is not physical.
    """
    coating.check()
    substrate.check()
    if not (deposition.is_valid() and service.is_valid()):
        raise Error("A temperature must be finite and above absolute zero")
    var strain = (substrate.expansion.value - coating.expansion.value) * (
        deposition.kelvin - service.kelvin
    )
    return Pressure64(coating.modulus.value / (1 - coating.poisson) * strain)


def delamination_thickness(
    coating: ElasticLayer, stress: Pressure64, toughness: FractureEnergy64
) raises -> Length64:
    """Return the thickest coating that does not peel from an edge.

    Args:
        coating: The coating.
        stress: Its residual biaxial stress, of either sign.
        toughness: The fracture energy of the interface.

    Returns:
        The critical thickness. With no stress there is no limit, and the
        result is infinite.

    Raises:
        Error: If the coating's properties are not physical, the stress is
            not finite, or the toughness is not finite and positive.
    """
    coating.check()
    if not isfinite(stress.value):
        raise Error("A stress must be finite")
    if not (isfinite(toughness.value) and toughness.value > 0):
        raise Error("A fracture energy must be finite and positive")
    var s = stress.value
    if s == 0:
        return Length64(inf[DType.float64]())
    var nu = coating.poisson
    return Length64(
        2 * coating.modulus.value * toughness.value / ((1 - nu * nu) * s * s)
    )
