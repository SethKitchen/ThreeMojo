# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Rates: Arrhenius rate constants and the shrinking-core model.

An `Arrhenius` rate constant is k = A exp(-Ea / R T), first order, in
1/s. `RateAtLeast` is a `Constraint`: it holds where k reaches a minimum,
so a kinetic bound that practice states as a temperature can come from
measured rate data instead.

`ShrinkingCore` is the model of Levenspiel ("Chemical Reaction
Engineering", chapter 25) for a gas that reacts with a solid sphere:
A(gas) + b B(solid) -> products. Three resistances act in series: the
gas film, the layer of product ash, and the reaction at the core's
surface. The time to convert a share X of the sphere is

    t = tau_film X
      + tau_ash (1 - 3 (1 - X)^(2/3) + 2 (1 - X))
      + tau_reaction (1 - (1 - X)^(1/3))

with tau_film = rho R / (3 b k_g C), tau_ash = rho R^2 / (6 b D_e C)
and tau_reaction = rho R / (b k_s C). Here rho is the solid's molar
density, R the sphere's radius, C the gas's concentration, k_g the film
coefficient, D_e the diffusivity in the ash and k_s the surface rate
constant.
"""

from std.math import exp, isfinite, log
from extensions.chemistry.quantities import (
    GAS_CONSTANT,
    MolarEnergy64,
)
from extensions.chemistry.requirement import Constraint
from loaders.js_number import js_to_fixed
from units.quantity import Unit
from units.si import (
    Duration64,
    Frequency64,
    Length64,
    Pressure64,
    Velocity64,
)
from units.quantity import Quantity
from units.temperature import Temperature64

# A diffusivity: square meters per second.
comptime Diffusivity64 = Quantity[2, 0, -1, 0, 0, DType.float64]
comptime SQUARE_METER_PER_SECOND = Unit[2, 0, -1, 0, 0, DType.float64](
    1.0, "m^2/s"
)
# Bisection steps for a conversion.
comptime _BISECTIONS = 60


@fieldwise_init
struct Concentration64(ImplicitlyCopyable, Writable):
    """An amount of substance per volume, in mol/m^3."""

    var value: Float64


def _require_positive(value: Float64, message: String) raises:
    """Refuse a value that is not finite and positive."""
    if not (isfinite(value) and value > 0):
        raise Error(message)


@fieldwise_init
struct Arrhenius(ImplicitlyCopyable):
    """A first-order rate constant: k = A exp(-Ea / R T)."""

    var pre_exponential: Frequency64
    var activation: MolarEnergy64

    def check(self) raises:
        """Refuse a rate law that is not physical.

        Nothing. The call returns when the law is physical.

        Raises:
            Error: If the pre-exponential factor is not finite and
                positive, or the activation energy is negative or not
                finite.
        """
        _require_positive(
            self.pre_exponential.value,
            "A pre-exponential factor must be finite and positive",
        )
        var e = self.activation.value
        if not (isfinite(e) and e >= 0):
            raise Error("An activation energy must be finite, not negative")

    def rate(self, temperature: Temperature64) raises -> Frequency64:
        """Return the rate constant at a temperature.

        Args:
            temperature: The temperature, above absolute zero.

        Returns:
            The rate constant k, in 1/s.

        Raises:
            Error: If the law is not physical or the temperature is not
                above absolute zero.
        """
        self.check()
        _require_positive(
            temperature.kelvin, "A temperature must be above absolute zero"
        )
        var rt = GAS_CONSTANT.value * temperature.kelvin
        return Frequency64(
            self.pre_exponential.value * exp(-self.activation.value / rt)
        )

    def temperature_for(self, rate: Frequency64) raises -> Temperature64:
        """Return the temperature where the rate constant reaches a value.

        Args:
            rate: The rate constant, below the pre-exponential factor.

        Returns:
            T = Ea / (R ln(A / k)).

        Raises:
            Error: If the law is not physical, the activation energy is
                zero, or the rate is not finite, positive and below A.
        """
        self.check()
        if self.activation.value == 0:
            raise Error("A rate with no activation energy does not vary")
        _require_positive(rate.value, "A rate must be finite and positive")
        if rate.value >= self.pre_exponential.value:
            raise Error("A rate must be below the pre-exponential factor")
        var ratio = log(self.pre_exponential.value / rate.value)
        return Temperature64(
            self.activation.value / (GAS_CONSTANT.value * ratio)
        )

    def half_life(self, temperature: Temperature64) raises -> Duration64:
        """Return the half-life of a first-order reaction.

        Args:
            temperature: The temperature.

        Returns:
            The half-life, ln 2 / k.

        Raises:
            Error: If the rate cannot be evaluated.
        """
        return Duration64(log(2.0) / self.rate(temperature).value)


struct RateAtLeast(Constraint):
    """A constraint: a rate constant reaches a minimum."""

    var law: Arrhenius
    var minimum: Frequency64

    def __init__(out self, law: Arrhenius, minimum: Frequency64) raises:
        """Make the constraint.

        Args:
            law: The rate law.
            minimum: The least rate constant.

        Raises:
            Error: If the law is not physical or the minimum is not finite
                and positive.
        """
        law.check()
        _require_positive(minimum.value, "A rate must be finite and positive")
        self.law = law
        self.minimum = minimum

    def holds(
        self, temperature: Temperature64, pressure: Pressure64
    ) raises -> Bool:
        """Return True if the rate constant reaches the minimum.

        Args:
            temperature: The temperature.
            pressure: The pressure. A first-order rate does not use it.

        Returns:
            Whether k is at least the minimum.

        Raises:
            Error: If the temperature is not above absolute zero.
        """
        return self.law.rate(temperature).value >= self.minimum.value

    def describe(
        self, temperature: Temperature64, pressure: Pressure64
    ) raises -> String:
        """Return the rate constant at a condition, for a report.

        Args:
            temperature: The temperature.
            pressure: The pressure.

        Returns:
            Text such as "k 2.000e-3 1/s of 1.000e-3 needed".

        Raises:
            Error: If the temperature is not above absolute zero.
        """
        return String(
            "k ",
            _exponent(self.law.rate(temperature).value),
            " 1/s of ",
            _exponent(self.minimum.value),
            " needed",
        )


def _exponent(value: Float64) raises -> String:
    """Return a positive number as mantissa and power of ten."""
    var power = Int(log(value) / log(10.0))
    if Float64(10) ** power > value:
        power -= 1
    var mantissa = value / Float64(10) ** power
    return String(js_to_fixed(mantissa, 3), "e", power)


struct ShrinkingCore(ImplicitlyCopyable):
    """A gas reacting with a solid sphere, by Levenspiel's model."""

    # The times to convert the whole sphere with each resistance alone.
    var film: Duration64
    var ash: Duration64
    var reaction: Duration64

    def __init__(
        out self, film: Duration64, ash: Duration64, reaction: Duration64
    ) raises:
        """Make the model from the three complete-conversion times.

        Args:
            film: The time with only the gas film resisting.
            ash: The time with only diffusion through the ash resisting.
            reaction: The time with only the surface reaction resisting.

        Raises:
            Error: If a time is negative or not finite, or all are zero.
        """
        var times: List[Float64] = [film.value, ash.value, reaction.value]
        for t in times:  # pragma: no branch
            if not (isfinite(t) and t >= 0):
                raise Error("A conversion time must be finite, not negative")
        if film.value + ash.value + reaction.value == 0:
            raise Error("A sphere needs a resistance to convert")
        self.film = film
        self.ash = ash
        self.reaction = reaction

    @staticmethod
    def from_properties(
        radius: Length64,
        solid_density: Concentration64,
        gas: Concentration64,
        stoichiometry: Float64,
        film_coefficient: Velocity64,
        ash_diffusivity: Diffusivity64,
        surface_rate: Velocity64,
    ) raises -> ShrinkingCore:
        """Return the model from the sphere's and the gas's properties.

        Args:
            radius: The sphere's radius.
            solid_density: The solid's moles per volume.
            gas: The gas's moles per volume.
            stoichiometry: Moles of solid per mole of gas, b.
            film_coefficient: The gas film's mass transfer coefficient.
            ash_diffusivity: The gas's effective diffusivity in the ash.
            surface_rate: The first-order surface rate constant.

        Returns:
            The model.

        Raises:
            Error: If a property is not finite and positive.
        """
        var values: List[Float64] = [
            radius.value,
            solid_density.value,
            gas.value,
            stoichiometry,
            film_coefficient.value,
            ash_diffusivity.value,
            surface_rate.value,
        ]
        for v in values:  # pragma: no branch
            _require_positive(v, "A sphere's property must be positive")
        var r = radius.value
        var base = solid_density.value * r / (stoichiometry * gas.value)
        return ShrinkingCore(
            Duration64(base / (3 * film_coefficient.value)),
            Duration64(base * r / (6 * ash_diffusivity.value)),
            Duration64(base / surface_rate.value),
        )

    def time_to(self, conversion: Float64) raises -> Duration64:
        """Return the time to convert a share of the sphere.

        Args:
            conversion: The share, from 0 to 1.

        Returns:
            The sum of the three resistances' times.

        Raises:
            Error: If the share is not from 0 to 1.
        """
        if not (conversion >= 0 and conversion <= 1):
            raise Error("A conversion must lie from 0 to 1")
        var left = 1 - conversion
        var ash = 1 - 3 * left ** (2.0 / 3.0) + 2 * left
        var core = 1 - left ** (1.0 / 3.0)
        return Duration64(
            self.film.value * conversion
            + self.ash.value * ash
            + self.reaction.value * core
        )

    def conversion_at(self, time: Duration64) raises -> Float64:
        """Return the share converted after a time.

        Args:
            time: The time, zero or more.

        Returns:
            The share, one once the sphere is converted.

        Raises:
            Error: If the time is negative or not finite.
        """
        if not (isfinite(time.value) and time.value >= 0):
            raise Error("A time must be finite and not negative")
        if time.value >= self.time_to(1).value:
            return 1
        var lo = Float64(0)
        var hi = Float64(1)
        for _ in range(_BISECTIONS):  # pragma: no branch
            var mid = 0.5 * (lo + hi)
            if self.time_to(mid).value < time.value:
                lo = mid
            else:
                hi = mid
        return 0.5 * (lo + hi)
