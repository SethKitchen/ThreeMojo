# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reactions and their driving force.

A `Term` is a substance in a reaction, with its stoichiometric coefficient:
negative for a reactant and positive for a product. `reactant` and
`product` set the sign. A gas term also has a mole fraction of the total
pressure. A condensed term's fraction is its activity: one for a pure
phase, and less for a component of a solution.

The Gibbs energy change at a temperature T and a pressure P is the sum of
coefficient times chemical potential:

    gas:        mu = G(T) + R T ln(x P / p0)
    condensed:  mu = G(T) + V (P - p0) + R T ln(a)

G is the standard molar Gibbs energy at p0, one bar. The gas is ideal. A
condensed phase does not compress, and `a` is its activity. A negative change means the
reaction proceeds. A positive change means it is held back and the reverse
proceeds.

    var r = Reaction([
        reactant(calcite()),
        product(lime()),
        product(carbon_dioxide()),
    ])
    r.equilibrium_temperature(Temperature64(900), Temperature64(1199),
                              Pressure64(1, ATMOSPHERE))   # 1167 K
"""

from std.math import exp, isfinite, log
from extensions.chemistry.elements import ElementCount, formula_index
from extensions.chemistry.quantities import (
    GAS_CONSTANT,
    MolarEnergy64,
    STANDARD_PRESSURE,
)
from extensions.chemistry.thermo import Substance
from units.si import Pressure64
from units.temperature import Temperature64

# Element sums closer to zero than this balance.
comptime _BALANCE = 1e-9
# Bisection steps for an equilibrium temperature: far below 1e-9 K.
comptime _BISECTIONS = 60


struct Term(Copyable, Movable):
    """A substance in a reaction, with its coefficient."""

    var substance: Substance
    # Negative for a reactant, positive for a product.
    var coefficient: Float64
    # A gas's mole fraction of the total pressure, or a condensed phase's
    # activity: one when it is pure.
    var fraction: Float64

    def __init__(
        out self,
        var substance: Substance,
        coefficient: Float64,
        fraction: Float64,
    ):
        """Make a term. `Reaction` checks it.

        Args:
            substance: The substance.
            coefficient: Negative for a reactant, positive for a product.
            fraction: A gas's mole fraction, or a condensed activity.
        """
        self.substance = substance^
        self.coefficient = coefficient
        self.fraction = fraction


def reactant(
    var substance: Substance, coefficient: Float64 = 1, fraction: Float64 = 1
) -> Term:
    """Return a term that a reaction uses up.

    Args:
        substance: The substance.
        coefficient: How many moles, positive.
        fraction: A gas's mole fraction of the total pressure, or a
            condensed phase's activity.

    Returns:
        The term, with a negative coefficient.
    """
    return Term(substance^, -coefficient, fraction)


def product(
    var substance: Substance, coefficient: Float64 = 1, fraction: Float64 = 1
) -> Term:
    """Return a term that a reaction makes.

    Args:
        substance: The substance.
        coefficient: How many moles, positive.
        fraction: A gas's mole fraction of the total pressure, or a
            condensed phase's activity.

    Returns:
        The term, with a positive coefficient.
    """
    return Term(substance^, coefficient, fraction)


def _require_conditions(
    temperature: Temperature64, pressure: Pressure64
) raises:
    """Refuse a temperature or a pressure that is not physical."""
    if not temperature.is_valid():
        raise Error("A temperature must be finite and above absolute zero")
    if not (isfinite(pressure.value) and pressure.value > 0):
        raise Error("A pressure must be finite and positive")


struct Reaction(Copyable, Movable, Writable):
    """A balanced chemical reaction."""

    var terms: List[Term]

    def __init__(out self, var terms: List[Term]) raises:
        """Make a reaction from its terms.

        Args:
            terms: The reactants and the products, in the order to write
                them.

        Raises:
            Error: If there is no reactant or no product, a coefficient is
                zero or not finite, a fraction is not in (0, 1], or the
                elements do not balance.
        """
        var reactants = 0
        var products = 0
        var elements = List[ElementCount]()
        var sums = List[Float64]()
        for term in terms:
            if not isfinite(term.coefficient):
                raise Error("A coefficient must be finite")
            if term.coefficient == 0:
                raise Error("A coefficient must not be zero")
            if not (term.fraction > 0 and term.fraction <= 1):
                raise Error("A mole fraction must be above 0 and at most 1")
            if term.coefficient < 0:
                reactants += 1
            else:
                products += 1
            # Every substance has a phase and every formula an element.
            ref formula = term.substance.phases[0].formula
            for c in formula.counts:  # pragma: no branch
                var at = formula_index(elements, c.element)
                if at < 0:
                    elements.append(c)
                    sums.append(term.coefficient * Float64(c.count))
                else:
                    sums[at] += term.coefficient * Float64(c.count)
        if reactants == 0:
            raise Error("A reaction needs a reactant")
        if products == 0:
            raise Error("A reaction needs a product")
        # A reaction with a term has an element.
        for s in sums:  # pragma: no branch
            if abs(s) > _BALANCE:
                raise Error("A reaction must balance every element")
        self.terms = terms^

    def covers(self, temperature: Temperature64) -> Bool:
        """Return True if every substance's data reaches a temperature.

        Args:
            temperature: The temperature.

        Returns:
            Whether the change can be computed there.
        """
        # A reaction has two terms at least.
        for term in self.terms:  # pragma: no branch
            if not term.substance.covers(temperature):
                return False
        return True

    def delta_g(
        self, temperature: Temperature64, pressure: Pressure64
    ) raises -> MolarEnergy64:
        """Return the Gibbs energy change per mole of reaction.

        Args:
            temperature: The temperature.
            pressure: The total pressure.

        Returns:
            The change. Below zero, the reaction proceeds.

        Raises:
            Error: If the temperature or the pressure is not physical, or
                a substance's data does not reach the temperature.
        """
        _require_conditions(temperature, pressure)
        var rt = GAS_CONSTANT.value * temperature.kelvin
        var total = Float64(0)
        # A reaction has two terms at least.
        for term in self.terms:  # pragma: no branch
            var mu = term.substance.gibbs(temperature).value
            if term.substance.is_gas():
                mu += rt * log(
                    term.fraction * pressure.value / STANDARD_PRESSURE.value
                )
            else:
                var v = term.substance.molar_volume_at(temperature).value
                mu += v * (pressure.value - STANDARD_PRESSURE.value)
                mu += rt * log(term.fraction)
            total += term.coefficient * mu
        return MolarEnergy64(total)

    def delta_h(self, temperature: Temperature64) raises -> MolarEnergy64:
        """Return the enthalpy change per mole of reaction at one bar.

        Args:
            temperature: The temperature.

        Returns:
            The heat taken up. Below zero, the reaction gives off heat.

        Raises:
            Error: If the temperature is not physical or a substance's
                data does not reach it.
        """
        _require_conditions(temperature, STANDARD_PRESSURE)
        var total = Float64(0)
        # A reaction has two terms at least.
        for term in self.terms:  # pragma: no branch
            total += (
                term.coefficient * term.substance.enthalpy(temperature).value
            )
        return MolarEnergy64(total)

    def equilibrium_temperature(
        self, low: Temperature64, high: Temperature64, pressure: Pressure64
    ) raises -> Temperature64:
        """Return the temperature where the change crosses zero.

        Args:
            low: The low end of the search.
            high: The high end of the search.
            pressure: The total pressure.

        Returns:
            The crossing, to far better than a millikelvin.

        Raises:
            Error: If an end is not physical, the data does not reach an
                end, or the change has the same sign at both ends.
        """
        var lo = low.kelvin
        var hi = high.kelvin
        var g_lo = self.delta_g(low, pressure).value
        var g_hi = self.delta_g(high, pressure).value
        if (g_lo < 0) == (g_hi < 0):
            raise Error("The change has one sign over the search range")
        for _ in range(_BISECTIONS):  # pragma: no branch
            var mid = 0.5 * (lo + hi)
            var g = self.delta_g(Temperature64(mid), pressure).value
            if (g < 0) == (g_lo < 0):
                lo = mid
            else:
                hi = mid
        return Temperature64(0.5 * (lo + hi))

    def equilibrium_pressure(
        self, temperature: Temperature64, low: Pressure64, high: Pressure64
    ) raises -> Pressure64:
        """Return the total pressure where the change crosses zero.

        The search halves the range on a logarithmic scale, so it can span
        many decades. For an evaporation with a pure vapor, the result is
        the vapor pressure. For a decomposition that gives off one gas, it
        is the decomposition pressure.

        Args:
            temperature: The temperature.
            low: The low end of the search.
            high: The high end of the search.

        Returns:
            The crossing, to far better than a part in a million.

        Raises:
            Error: If the temperature or an end is not physical, the data
                does not reach the temperature, or the change has the same
                sign at both ends.
        """
        var g_lo = self.delta_g(temperature, low).value
        var g_hi = self.delta_g(temperature, high).value
        if (g_lo < 0) == (g_hi < 0):
            raise Error("The change has one sign over the search range")
        var lo = log(low.value)
        var hi = log(high.value)
        for _ in range(_BISECTIONS):  # pragma: no branch
            var mid = 0.5 * (lo + hi)
            var g = self.delta_g(temperature, Pressure64(exp(mid))).value
            if (g < 0) == (g_lo < 0):
                lo = mid
            else:
                hi = mid
        return Pressure64(exp(0.5 * (lo + hi)))

    def mass_ratio(self, of: Substance, per: Substance) raises -> Float64:
        """Return the mass of one substance per mass of another.

        Args:
            of: The substance to weigh, such as a reagent.
            per: The substance it is per, such as the product.

        Returns:
            Kilograms of `of` per kilogram of `per`.

        Raises:
            Error: If either substance is not in the reaction.
        """
        var a = self._term_of(of)
        var b = self._term_of(per)
        var mass_a = abs(self.terms[a].coefficient) * of.molar_mass().value
        var mass_b = abs(self.terms[b].coefficient) * per.molar_mass().value
        return mass_a / mass_b

    def _term_of(self, substance: Substance) raises -> Int:
        """Return the index of the term with a substance's formula."""
        ref formula = substance.phases[0].formula
        # A reaction has two terms at least.
        for i in range(len(self.terms)):  # pragma: no branch
            ref other = self.terms[i].substance
            var same = other.phases[0].formula.same(formula)
            if same and other.is_gas() == substance.is_gas():
                return i
        raise Error("The substance is not in the reaction")

    def write_to(self, mut writer: Some[Writer]):
        """Write the reaction, such as `TiCl4(g) + 2 Mg -> Ti + 2 MgCl2`.

        Args:
            writer: Where to write.
        """
        var separator = String("")
        for term in self.terms:  # pragma: no branch
            if term.coefficient < 0:
                writer.write(separator)
                _write_term(writer, term)
                separator = " + "
        separator = " -> "
        for term in self.terms:  # pragma: no branch
            if term.coefficient > 0:
                writer.write(separator)
                _write_term(writer, term)
                separator = " + "


def _write_term(mut writer: Some[Writer], term: Term):
    """Write one term: its coefficient, unless one, and its name."""
    var n = abs(term.coefficient)
    if n != 1:
        if n == Float64(Int(n)):
            writer.write(Int(n), " ")
        else:
            writer.write(n, " ")
    writer.write(term.substance.name)
