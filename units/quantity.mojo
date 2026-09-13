# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Numbers that carry their units, checked at compile time.

A `Quantity` is a single `Float32` tagged with the exponents of the base
dimensions it is measured in. Those exponents are compile-time parameters, so
the arithmetic on them happens in the type system and nothing survives to
runtime: a `Quantity` is the same size as the float inside it, and adding two
lengths compiles to a float add.

    var height = Length(1.0, METRE)
    print(height.to(FOOT))        # 3.2808399

    var area = height * Length(2.0, METRE)   # Area, exponent 2
    var bad  = height + Duration(1.0)        # does not compile

Values are stored in canonical units — metres, kilograms, seconds, radians —
so a `Quantity` never remembers which unit it was written in. `FOOT` is a
scale factor applied on the way in and out, not a property of the value. That
makes every comparison and sum trivially correct and means feet and metres can
be mixed freely in one expression.

Angle is treated as a base dimension here, which strict SI does not do: a
radian is properly dimensionless. Carrying it anyway is what makes passing
degrees to a function expecting radians a compile error, and that mistake is
common enough in graphics code to be worth the deviation.
"""

from std.math import sqrt as float_sqrt


@fieldwise_init
struct Unit[length: Int, mass: Int, time: Int, angle: Int](ImplicitlyCopyable):
    """A named scale factor on one particular dimension.

    `scale` is how many canonical units one of these is worth, so `FOOT` holds
    0.3048. The dimension exponents are part of the type, which is what stops
    a length being converted to seconds.
    """

    var scale: Float32
    var symbol: StaticString


@fieldwise_init
struct Quantity[length: Int, mass: Int, time: Int, angle: Int](
    Absable, ImplicitlyCopyable
):
    """A value measured in the dimension given by the exponents."""

    var value: Float32

    def __init__(
        out self,
        value: Float32,
        unit: Unit[Self.length, Self.mass, Self.time, Self.angle],
    ):
        """Create a quantity from a value expressed in `unit`.

        The unit's dimensions must match this quantity's, which the type
        system enforces at the call site.
        """
        self.value = value * unit.scale

    def to(
        self, unit: Unit[Self.length, Self.mass, Self.time, Self.angle]
    ) -> Float32:
        """Return this quantity's magnitude expressed in `unit`."""
        return self.value / unit.scale

    # --- arithmetic that preserves the dimension --------------------------

    def __add__(self, other: Self) -> Self:
        """Add two quantities of the same dimension."""
        return Self(self.value + other.value)

    def __sub__(self, other: Self) -> Self:
        """Subtract two quantities of the same dimension."""
        return Self(self.value - other.value)

    def __neg__(self) -> Self:
        """Return this quantity negated."""
        return Self(-self.value)

    def __abs__(self) -> Self:
        """Return this quantity's magnitude, discarding its sign."""
        if self.value < 0:
            return Self(-self.value)
        return Self(self.value)

    def scaled(self, factor: Float32) -> Self:
        """Return this quantity multiplied by a plain number.

        Scaling by a bare float cannot change the dimension, so this is kept
        separate from multiplying by another quantity.
        """
        return Self(self.value * factor)

    # --- arithmetic that changes the dimension ----------------------------

    def __mul__[
        l2: Int, m2: Int, t2: Int, a2: Int
    ](self, other: Quantity[l2, m2, t2, a2]) -> Quantity[
        Self.length + l2, Self.mass + m2, Self.time + t2, Self.angle + a2
    ]:
        """Multiply two quantities, adding their dimension exponents."""
        return Quantity[
            Self.length + l2, Self.mass + m2, Self.time + t2, Self.angle + a2
        ](self.value * other.value)

    def __truediv__[
        l2: Int, m2: Int, t2: Int, a2: Int
    ](self, other: Quantity[l2, m2, t2, a2]) -> Quantity[
        Self.length - l2, Self.mass - m2, Self.time - t2, Self.angle - a2
    ]:
        """Divide two quantities, subtracting their dimension exponents."""
        return Quantity[
            Self.length - l2, Self.mass - m2, Self.time - t2, Self.angle - a2
        ](self.value / other.value)

    def sqrt(
        self,
    ) -> Quantity[
        Self.length // 2, Self.mass // 2, Self.time // 2, Self.angle // 2
    ]:
        """Return the square root, halving every dimension exponent.

        Only defined when every exponent is even, since a dimension raised to
        a fractional power is not expressible here. An area gives a length; a
        volume is rejected at compile time.
        """
        comptime assert (
            Self.length % 2 == 0
        ), "sqrt needs an even length exponent"
        comptime assert Self.mass % 2 == 0, "sqrt needs an even mass exponent"
        comptime assert Self.time % 2 == 0, "sqrt needs an even time exponent"
        comptime assert Self.angle % 2 == 0, "sqrt needs an even angle exponent"
        return Quantity[
            Self.length // 2, Self.mass // 2, Self.time // 2, Self.angle // 2
        ](float_sqrt(self.value))

    # --- comparison -------------------------------------------------------

    def __eq__(self, other: Self) -> Bool:
        """Return True if both quantities hold the same magnitude."""
        return self.value == other.value

    def __ne__(self, other: Self) -> Bool:
        """Return True if the quantities differ."""
        return self.value != other.value

    def __lt__(self, other: Self) -> Bool:
        """Return True if this quantity is the smaller."""
        return self.value < other.value

    def __le__(self, other: Self) -> Bool:
        """Return True if this quantity is no larger."""
        return self.value <= other.value

    def __gt__(self, other: Self) -> Bool:
        """Return True if this quantity is the larger."""
        return self.value > other.value

    def __ge__(self, other: Self) -> Bool:
        """Return True if this quantity is no smaller."""
        return self.value >= other.value
