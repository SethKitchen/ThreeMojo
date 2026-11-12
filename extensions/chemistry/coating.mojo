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

More of the mechanics:

- `curve_mismatch_stress` uses expansion curves instead of means.
- `stoney_stress` is the stress a measured substrate curvature gives
  (Stoney, 1909): sigma = E_s h_s^2 kappa / (6 (1 - nu_s) h_f).
  `stack_curvature` is the inverse for a stack of thin layers: each layer
  adds its stress times its thickness.
- `straight_buckle_stress` and `circular_buckle_stress` are the
  compressive stresses at which a delaminated strip or disc of coating
  buckles off the surface (Hutchinson and Suo, 1992): (pi^2 / 12) and
  1.2235 times E / (1 - nu^2) (h / b)^2, with b the half-width or the
  radius.
- `thermal_shock_difference` is Kingery's first thermal shock parameter,
  sigma_f (1 - nu) / (E alpha): the sudden temperature change that cracks
  a brittle surface.
"""

from std.math import inf, isfinite, pi
from extensions.chemistry.materials import ExpansionCurve
from extensions.chemistry.quantities import FractureEnergy64
from units.si import InverseLength64, Length64, Pressure64, ThermalExpansion64
from units.temperature import Temperature64, TemperatureDifference64


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


def curve_mismatch_stress(
    coating: ElasticLayer,
    coating_curve: ExpansionCurve,
    substrate_curve: ExpansionCurve,
    deposition: Temperature64,
    service: Temperature64,
) raises -> Pressure64:
    """Return the residual stress from cooling, with expansion curves.

    Args:
        coating: The coating's elastic properties. Its mean expansion is
            not used.
        coating_curve: The coating's expansion coefficient over the range.
        substrate_curve: The substrate's.
        deposition: The temperature the coating was deposited at.
        service: The temperature it is used at.

    Returns:
        The equal biaxial stress in the coating. Positive is compression.

    Raises:
        Error: If the coating's properties are not physical or a
            temperature is outside a curve.
    """
    coating.check()
    var mismatch = substrate_curve.strain(
        service, deposition
    ) - coating_curve.strain(service, deposition)
    return Pressure64(coating.modulus.value / (1 - coating.poisson) * mismatch)


def _require_length(length: Length64, what: String) raises:
    """Refuse a length that is not finite and positive."""
    if not (isfinite(length.value) and length.value > 0):
        raise Error(what + " must be finite and positive")


def stoney_stress(
    substrate: ElasticLayer,
    substrate_thickness: Length64,
    coating_thickness: Length64,
    curvature: InverseLength64,
) raises -> Pressure64:
    """Return a thin coating's stress from its substrate's curvature.

    Args:
        substrate: The substrate's elastic properties.
        substrate_thickness: The substrate's thickness.
        coating_thickness: The coating's thickness, much less.
        curvature: The change in curvature the coating causes. Positive
            curves the coating side concave, from a tensile coating.

    Returns:
        The coating's stress. Positive is tension here, as the measured
        curvature gives it.

    Raises:
        Error: If the substrate's properties or a thickness is not
            physical, or the curvature is not finite.
    """
    substrate.check()
    _require_length(substrate_thickness, "A substrate thickness")
    _require_length(coating_thickness, "A coating thickness")
    if not isfinite(curvature.value):
        raise Error("A curvature must be finite")
    var h = substrate_thickness.value
    return Pressure64(
        substrate.modulus.value
        * h
        * h
        * curvature.value
        / (6 * (1 - substrate.poisson) * coating_thickness.value)
    )


def stack_curvature(
    stresses: List[Pressure64],
    thicknesses: List[Length64],
    substrate: ElasticLayer,
    substrate_thickness: Length64,
) raises -> InverseLength64:
    """Return the curvature a stack of thin layers gives a substrate.

    Args:
        stresses: Each layer's stress, positive in tension.
        thicknesses: Each layer's thickness.
        substrate: The substrate's elastic properties.
        substrate_thickness: The substrate's thickness.

    Returns:
        The curvature, 6 (1 - nu_s) sum(sigma h) / (E_s h_s^2).

    Raises:
        Error: If the lists differ in length, a stress is not finite, a
            thickness is not positive, or the substrate is not physical.
    """
    if len(stresses) != len(thicknesses):
        raise Error("Give one thickness per stress")
    substrate.check()
    _require_length(substrate_thickness, "A substrate thickness")
    var force = Float64(0)
    for i in range(len(stresses)):
        if not isfinite(stresses[i].value):
            raise Error("A stress must be finite")
        _require_length(thicknesses[i], "A layer thickness")
        force += stresses[i].value * thicknesses[i].value
    var h = substrate_thickness.value
    return InverseLength64(
        6 * (1 - substrate.poisson) * force / (substrate.modulus.value * h * h)
    )


def _buckle(
    factor: Float64, coating: ElasticLayer, thickness: Length64, size: Length64
) raises -> Pressure64:
    """Return factor E / (1 - nu^2) (h / b)^2."""
    coating.check()
    _require_length(thickness, "A coating thickness")
    _require_length(size, "A delamination size")
    var r = thickness.value / size.value
    var nu = coating.poisson
    return Pressure64(factor * coating.modulus.value / (1 - nu * nu) * r * r)


def straight_buckle_stress(
    coating: ElasticLayer, thickness: Length64, half_width: Length64
) raises -> Pressure64:
    """Return the compression at which a delaminated strip buckles.

    Args:
        coating: The coating.
        thickness: Its thickness.
        half_width: Half the width of the delaminated strip.

    Returns:
        The critical compressive stress, (pi^2 / 12) E / (1 - nu^2)
        (h / b)^2.

    Raises:
        Error: If the coating's properties or a length is not physical.
    """
    return _buckle(pi * pi / 12, coating, thickness, half_width)


def circular_buckle_stress(
    coating: ElasticLayer, thickness: Length64, radius: Length64
) raises -> Pressure64:
    """Return the compression at which a delaminated disc buckles.

    Args:
        coating: The coating.
        thickness: Its thickness.
        radius: The disc's radius.

    Returns:
        The critical compressive stress, 1.2235 E / (1 - nu^2) (h / R)^2.

    Raises:
        Error: If the coating's properties or a length is not physical.
    """
    return _buckle(1.2235, coating, thickness, radius)


def thermal_shock_difference(
    layer: ElasticLayer, strength: Pressure64
) raises -> TemperatureDifference64:
    """Return the sudden temperature change that cracks a brittle surface.

    Args:
        layer: The material, with a positive expansion coefficient.
        strength: Its fracture strength.

    Returns:
        Kingery's first parameter, sigma_f (1 - nu) / (E alpha).

    Raises:
        Error: If the properties are not physical, the expansion is not
            positive, or the strength is not finite and positive.
    """
    layer.check()
    if not (layer.expansion.value > 0):
        raise Error("A thermal shock needs a positive expansion coefficient")
    if not (isfinite(strength.value) and strength.value > 0):
        raise Error("A strength must be finite and positive")
    return TemperatureDifference64(
        strength.value
        * (1 - layer.poisson)
        / (layer.modulus.value * layer.expansion.value)
    )
