# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Materials data with sources: expansion curves, melting points, eutectics.

An `ExpansionCurve` is a linear expansion coefficient given at a list of
temperatures and linear between them. `strain` integrates it exactly,
which a mean coefficient cannot do where the coefficient changes much
over the range, as diamond's does.

`melting_point` gives the melting point of an element and
`eutectic_temperature` the lowest melting point of a binary metal system,
each with its source. They are the stated bounds that engineering
requirements need, such as the eutectic a retort must stay below.

The melting points are from the CRC Handbook of Chemistry and Physics.
The eutectics are from the ASM phase diagrams: Fe-Ti from Murray (1981),
Fe-C (as cementite) and Al-Si from the standard diagrams.
"""

from std.math import isfinite
from extensions.chemistry.elements import (
    ALUMINUM,
    BISMUTH,
    CARBON,
    COBALT,
    COPPER,
    Element,
    GOLD,
    IRON,
    MAGNESIUM,
    MOLYBDENUM,
    NICKEL,
    PLATINUM,
    SILICON,
    SILVER,
    TANTALUM,
    TITANIUM,
    TUNGSTEN,
    ZINC,
)
from units.si import ThermalExpansion64
from units.temperature import CELSIUS, Temperature64


struct ExpansionCurve(Copyable, Movable):
    """A linear expansion coefficient, linear between tabulated points."""

    # Kelvin, ascending.
    var temperatures: List[Float64]
    # Per kelvin, one per temperature.
    var coefficients: List[Float64]

    def __init__(
        out self,
        var temperatures: List[Temperature64],
        var coefficients: List[ThermalExpansion64],
    ) raises:
        """Make a curve from its points.

        Args:
            temperatures: Two or more temperatures, ascending.
            coefficients: The coefficient at each.

        Raises:
            Error: If there are fewer than two points, the lists differ, a
                value is not finite, or the temperatures do not ascend.
        """
        if len(temperatures) < 2:
            raise Error("An expansion curve needs two points")
        if len(temperatures) != len(coefficients):
            raise Error("Give one coefficient per temperature")
        self.temperatures = List[Float64]()
        self.coefficients = List[Float64]()
        for i in range(len(temperatures)):  # pragma: no branch
            var t = temperatures[i].kelvin
            var a = coefficients[i].value
            if not (temperatures[i].is_valid() and isfinite(a)):
                raise Error("An expansion point must be finite")
            if i > 0 and t <= self.temperatures[i - 1]:
                raise Error("An expansion curve's temperatures must ascend")
            self.temperatures.append(t)
            self.coefficients.append(a)

    def at(self, temperature: Temperature64) raises -> ThermalExpansion64:
        """Return the coefficient at a temperature.

        Args:
            temperature: A temperature in the curve's range.

        Returns:
            The coefficient, linear between the points.

        Raises:
            Error: If the temperature is outside the curve.
        """
        var t = temperature.kelvin
        var n = len(self.temperatures)
        if not (t >= self.temperatures[0] and t <= self.temperatures[n - 1]):
            raise Error("A temperature is outside the expansion curve")
        # The segment that holds t: the first whose upper end reaches it,
        # or the last.
        var k = 1
        while k < n - 1 and t > self.temperatures[k]:
            k += 1
        var t0 = self.temperatures[k - 1]
        var f = (t - t0) / (self.temperatures[k] - t0)
        var a0 = self.coefficients[k - 1]
        return ThermalExpansion64(a0 + f * (self.coefficients[k] - a0))

    def strain(
        self, start: Temperature64, end: Temperature64
    ) raises -> Float64:
        """Return the thermal strain from one temperature to another.

        Args:
            start: The first temperature.
            end: The second. Below the first, the strain is negative.

        Returns:
            The integral of the coefficient from start to end.

        Raises:
            Error: If a temperature is outside the curve.
        """
        var a = start.kelvin
        var b = end.kelvin
        var sign = Float64(1)
        if b < a:
            a = end.kelvin
            b = start.kelvin
            sign = -1
        # Check both ends lie on the curve.
        _ = self.at(Temperature64(a))
        _ = self.at(Temperature64(b))
        var total = Float64(0)
        # Sum the trapezoids over the pieces between a and b.
        var points = List[Float64]()
        points.append(a)
        for t in self.temperatures:  # pragma: no branch
            if t > a and t < b:
                points.append(t)
        points.append(b)
        for i in range(1, len(points)):  # pragma: no branch
            var lo = Temperature64(points[i - 1])
            var hi = Temperature64(points[i])
            total += (
                0.5
                * (self.at(lo).value + self.at(hi).value)
                * (hi.kelvin - lo.kelvin)
            )
        return sign * total

    def mean(
        self, start: Temperature64, end: Temperature64
    ) raises -> ThermalExpansion64:
        """Return the mean coefficient between two temperatures.

        Args:
            start: The first temperature.
            end: The second, different from the first.

        Returns:
            The strain over the temperature change.

        Raises:
            Error: If a temperature is outside the curve or they are
                equal.
        """
        var d = end.kelvin - start.kelvin
        if d == 0:
            raise Error("A mean needs two different temperatures")
        return ThermalExpansion64(self.strain(start, end) / d)


def _elements() -> List[Element]:
    """Return the elements with a melting point in the table."""
    return [
        TUNGSTEN,
        TANTALUM,
        MOLYBDENUM,
        TITANIUM,
        IRON,
        COBALT,
        NICKEL,
        PLATINUM,
        COPPER,
        GOLD,
        SILVER,
        ALUMINUM,
        MAGNESIUM,
        ZINC,
        BISMUTH,
        SILICON,
    ]


def _melting_celsius() -> List[Float64]:
    """Return the melting points in degrees Celsius, CRC Handbook."""
    return [
        3422.0,
        3017.0,
        2623.0,
        1668.0,
        1538.0,
        1495.0,
        1455.0,
        1768.2,
        1084.62,
        1064.18,
        961.78,
        660.32,
        650.0,
        419.53,
        271.4,
        1414.0,
    ]


def melting_point(element: Element) raises -> Temperature64:
    """Return an element's melting point at one atmosphere.

    Args:
        element: One of W, Ta, Mo, Ti, Fe, Co, Ni, Pt, Cu, Au, Ag, Al, Mg,
            Zn, Bi and Si.

    Returns:
        The melting point, from the CRC Handbook.

    Raises:
        Error: If the table does not hold the element.
    """
    var elements = _elements()
    var values = _melting_celsius()
    for i in range(len(elements)):  # pragma: no branch
        if elements[i] == element:
            return Temperature64(values[i], CELSIUS)
    raise Error(String("The table has no melting point for ", element.symbol()))


def eutectic_temperature(a: Element, b: Element) raises -> Temperature64:
    """Return the eutectic temperature of a binary system.

    Args:
        a: One element.
        b: The other, in either order.

    Returns:
        Fe-Ti 1085 degC (Murray, 1981), Fe-C 1147 degC (with cementite)
        or Al-Si 577 degC.

    Raises:
        Error: If the table does not hold the pair.
    """
    var firsts: List[Element] = [IRON, IRON, ALUMINUM]
    var seconds: List[Element] = [TITANIUM, CARBON, SILICON]
    var values: List[Float64] = [1085.0, 1147.0, 577.0]
    for i in range(3):
        var same = firsts[i] == a and seconds[i] == b
        var swapped = firsts[i] == b and seconds[i] == a
        if same or swapped:
            return Temperature64(values[i], CELSIUS)
    raise Error(
        String("The table has no eutectic for ", a.symbol(), "-", b.symbol())
    )
