# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Transport: evaporation, diffusion into a surface, and heating.

- `evaporation_flux` is the Hertz-Knudsen-Langmuir rate at which a
  surface loses mass into a vacuum or a thin gas:
  J = alpha (p_sat - p) sqrt(M / (2 pi R T)). `vapor_pressure` finds
  p_sat from the data, and `evaporation_time` turns a flux into a time.
- `Diffusivity` is an Arrhenius diffusion coefficient, D = D0 exp(-Q/RT).
  `case_depth` and `time_to_depth` solve Fick's second law for a
  semi-infinite solid with a fixed surface concentration:
  (C - C0) / (Cs - C0) = erfc(x / (2 sqrt(D t))). This is the case
  depth of carburizing and nitriding.
- `heating_time` is the lumped-capacitance time to heat a body in a
  furnace, valid where the Biot number h L / k is below about 0.1.
"""

from std.math import erfc, exp, isfinite, log, pi, sqrt
from extensions.chemistry.kinetics import Diffusivity64
from extensions.chemistry.quantities import GAS_CONSTANT, MolarMass64
from extensions.chemistry.reaction import Reaction, product, reactant
from extensions.chemistry.thermo import Substance
from units.quantity import Quantity
from units.si import (
    Area64,
    Duration64,
    Length64,
    Mass64,
    Pressure64,
    SpecificHeatCapacity64,
    ThermalConductivity64,
    ThermalTransmittance64,
)
from extensions.chemistry.quantities import MolarEnergy64
from units.temperature import Temperature64

# A mass flux: kilograms per square meter per second.
comptime MassFlux64 = Quantity[-2, 1, -1, 0, 0, DType.float64]
# The range a vapor pressure is searched over, in pascals.
comptime _P_LOWEST = 1e-30
comptime _P_HIGHEST = 1e12
# Bisection steps for an inverse error function.
comptime _BISECTIONS = 80


def _require_positive(value: Float64, message: String) raises:
    """Refuse a value that is not finite and positive."""
    if not (isfinite(value) and value > 0):
        raise Error(message)


def vapor_pressure(
    condensed: Substance, vapor: Substance, temperature: Temperature64
) raises -> Pressure64:
    """Return the pressure of a pure vapor in balance with its condensed phase.

    Args:
        condensed: The solid or liquid.
        vapor: The same formula as a gas.
        temperature: The temperature.

    Returns:
        The vapor pressure, from 1e-30 Pa to 1e12 Pa.

    Raises:
        Error: If the two do not share a formula, the data does not reach
            the temperature, or the pressure is outside the search.
    """
    var boil = Reaction([reactant(condensed.copy()), product(vapor.copy())])
    return boil.equilibrium_pressure(
        temperature, Pressure64(_P_LOWEST), Pressure64(_P_HIGHEST)
    )


def evaporation_flux(
    vapor_pressure: Pressure64,
    ambient: Pressure64,
    molar_mass: MolarMass64,
    temperature: Temperature64,
    coefficient: Float64 = 1,
) raises -> MassFlux64:
    """Return the Hertz-Knudsen-Langmuir mass flux from a surface.

    Args:
        vapor_pressure: The equilibrium pressure of the vapor.
        ambient: The vapor's partial pressure over the surface.
        molar_mass: The vapor's molar mass.
        temperature: The surface temperature.
        coefficient: The evaporation coefficient alpha, above 0 and at
            most 1. A clean metal surface is near 1.

    Returns:
        The net mass leaving per area per time. Below zero, vapor
        condenses on the surface.

    Raises:
        Error: If a pressure is negative or not finite, the molar mass or
            the temperature is not positive, or the coefficient is out of
            range.
    """
    var pressures: List[Float64] = [vapor_pressure.value, ambient.value]
    for p in pressures:  # pragma: no branch
        if not (isfinite(p) and p >= 0):
            raise Error("A pressure must be finite and not negative")
    _require_positive(molar_mass.value, "A molar mass must be positive")
    _require_positive(temperature.kelvin, "A temperature must be positive")
    if not (coefficient > 0 and coefficient <= 1):
        raise Error("An evaporation coefficient must be above 0, at most 1")
    var root = sqrt(
        molar_mass.value / (2 * pi * GAS_CONSTANT.value * temperature.kelvin)
    )
    return MassFlux64(
        coefficient * (vapor_pressure.value - ambient.value) * root
    )


def evaporation_time(
    mass: Mass64, area: Area64, flux: MassFlux64
) raises -> Duration64:
    """Return the time to evaporate a mass at a steady flux.

    Args:
        mass: The mass to remove.
        area: The surface it leaves from.
        flux: The mass flux, above zero.

    Returns:
        The time, mass / (area flux).

    Raises:
        Error: If the mass is negative, or the area or the flux is not
            finite and positive.
    """
    if not (isfinite(mass.value) and mass.value >= 0):
        raise Error("A mass must be finite and not negative")
    _require_positive(area.value, "An area must be finite and positive")
    _require_positive(flux.value, "A flux must be finite and positive")
    return Duration64(mass.value / (area.value * flux.value))


@fieldwise_init
struct Diffusivity(ImplicitlyCopyable):
    """An Arrhenius diffusion coefficient: D = D0 exp(-Q / R T)."""

    var d0: Diffusivity64
    var activation: MolarEnergy64

    def at(self, temperature: Temperature64) raises -> Diffusivity64:
        """Return the diffusion coefficient at a temperature.

        Args:
            temperature: The temperature, above absolute zero.

        Returns:
            D, in m^2/s.

        Raises:
            Error: If D0 is not finite and positive, Q is negative or not
                finite, or the temperature is not positive.
        """
        _require_positive(self.d0.value, "D0 must be finite and positive")
        var q = self.activation.value
        if not (isfinite(q) and q >= 0):
            raise Error("An activation energy must be finite, not negative")
        _require_positive(temperature.kelvin, "A temperature must be positive")
        var rt = GAS_CONSTANT.value * temperature.kelvin
        return Diffusivity64(self.d0.value * exp(-q / rt))


def _inverse_erfc(value: Float64) -> Float64:
    """Return z with erfc(z) = value, for value in (0, 1)."""
    var lo = Float64(0)
    var hi = Float64(10)
    for _ in range(_BISECTIONS):  # pragma: no branch
        var mid = 0.5 * (lo + hi)
        if erfc(mid) > value:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def _require_ratio(ratio: Float64) raises:
    """Refuse a concentration ratio outside (0, 1)."""
    if not (ratio > 0 and ratio < 1):
        raise Error("A concentration ratio must lie between 0 and 1")


def case_depth(
    diffusivity: Diffusivity64, time: Duration64, ratio: Float64
) raises -> Length64:
    """Return the depth where a diffusing element reaches a ratio.

    Args:
        diffusivity: D at the treatment temperature.
        time: The treatment time.
        ratio: (C - C0) / (Cs - C0) at the depth, between 0 and 1.

    Returns:
        The depth x with erfc(x / (2 sqrt(D t))) = ratio.

    Raises:
        Error: If D or the time is not finite and positive, or the ratio is
            not between 0 and 1.
    """
    _require_positive(diffusivity.value, "A diffusivity must be positive")
    _require_positive(time.value, "A time must be finite and positive")
    _require_ratio(ratio)
    var z = _inverse_erfc(ratio)
    return Length64(2 * z * sqrt(diffusivity.value * time.value))


def time_to_depth(
    diffusivity: Diffusivity64, depth: Length64, ratio: Float64
) raises -> Duration64:
    """Return the time for a diffusing element to reach a ratio at a depth.

    Args:
        diffusivity: D at the treatment temperature.
        depth: The depth.
        ratio: (C - C0) / (Cs - C0) wanted at the depth.

    Returns:
        The time t = (x / (2 z))^2 / D, with erfc(z) = ratio.

    Raises:
        Error: If D or the depth is not finite and positive, or the ratio
            is not between 0 and 1.
    """
    _require_positive(diffusivity.value, "A diffusivity must be positive")
    _require_positive(depth.value, "A depth must be finite and positive")
    _require_ratio(ratio)
    var z = _inverse_erfc(ratio)
    var half = depth.value / (2 * z)
    return Duration64(half * half / diffusivity.value)


def biot(
    coefficient: ThermalTransmittance64,
    length: Length64,
    conductivity: ThermalConductivity64,
) raises -> Float64:
    """Return the Biot number of a body.

    Args:
        coefficient: The surface heat transfer coefficient h.
        length: The body's volume over its surface area.
        conductivity: The body's thermal conductivity k.

    Returns:
        The number h L / k. Below about 0.1, a lumped model is accurate.

    Raises:
        Error: If a value is not finite and positive.
    """
    _require_positive(coefficient.value, "A coefficient must be positive")
    _require_positive(length.value, "A length must be positive")
    _require_positive(conductivity.value, "A conductivity must be positive")
    return coefficient.value * length.value / conductivity.value


def heating_time(
    mass: Mass64,
    specific_heat: SpecificHeatCapacity64,
    coefficient: ThermalTransmittance64,
    area: Area64,
    start: Temperature64,
    furnace: Temperature64,
    target: Temperature64,
) raises -> Duration64:
    """Return the lumped-capacitance time to bring a body to a temperature.

    Args:
        mass: The body's mass.
        specific_heat: Its specific heat.
        coefficient: The surface heat transfer coefficient h.
        area: Its surface area.
        start: Its starting temperature.
        furnace: The furnace temperature.
        target: The temperature wanted, between the other two.

    Returns:
        The time (m c / (h A)) ln((T0 - Tf) / (Tt - Tf)).

    Raises:
        Error: If a property is not finite and positive, or the target is
            not strictly between the start and the furnace.
    """
    _require_positive(mass.value, "A mass must be finite and positive")
    _require_positive(specific_heat.value, "A specific heat must be positive")
    _require_positive(coefficient.value, "A coefficient must be positive")
    _require_positive(area.value, "An area must be finite and positive")
    var a = start.kelvin - furnace.kelvin
    var b = target.kelvin - furnace.kelvin
    # The target lies between the start and the furnace when a and b share
    # a sign and b is the smaller.
    if not (a * b > 0 and abs(b) < abs(a)):
        raise Error("A target must lie between the start and the furnace")
    var scale = (
        mass.value * specific_heat.value / (coefficient.value * area.value)
    )
    return Duration64(scale * log(a / b))
