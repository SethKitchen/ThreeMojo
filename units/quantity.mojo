# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Numbers that carry their units, checked at compile time.

A `Quantity` is a single float tagged with the exponents of the base
dimensions it is measured in. Those exponents are compile-time parameters, so
the arithmetic on them happens in the type system and nothing survives to
runtime: a `Quantity` is the same size as the float inside it, and adding two
lengths compiles to a float add.

    var height = Length(1.0, METER)
    print(height.to(FOOT))        # 3.2808399

    var area = height * Length(2.0, METER)   # Area, exponent 2
    var bad  = height + Duration(1.0)        # does not compile

Values are stored in canonical units — meters, kilograms, seconds, radians —
so a `Quantity` never remembers which unit it was written in. `FOOT` is a
scale factor applied on the way in and out, not a property of the value. That
makes every comparison and sum trivially correct and means feet and meters can
be mixed freely in one expression.

The fifth exponent is the temperature difference, in kelvin. It defaults to
zero, so `Quantity[1, 0, 0, 0]` is still a length. A thermal conductivity is
`Quantity[1, 1, -3, 0, -1]`: watts per meter per kelvin. An absolute
temperature is not a `Quantity`; see `units.temperature`.

The float is a `Float32` unless the `dtype` parameter says otherwise. Graphics
code keeps the default. Engineering code, where a stiffness matrix loses
digits in `Float32`, names `DType.float64`; `units.si` has a `64` alias for
each dimension, such as `Length64`. Two quantities combine only when their
`dtype` matches. `cast` changes it explicitly. A unit has a `dtype` too, a
`Float32` by default, and converts quantities of either float type.

Angle is treated as a base dimension here, which strict SI does not do: a
radian is properly dimensionless. Carrying it anyway is what makes passing
degrees to a function expecting radians a compile error, and that mistake is
common enough in graphics code to be worth the deviation.
"""

from std.math import sqrt as float_sqrt


@fieldwise_init
struct Unit[
    length: Int,
    mass: Int,
    time: Int,
    angle: Int,
    temperature: Int = 0,
    dtype: DType = DType.float32,
](ImplicitlyCopyable):
    """A named scale factor on one particular dimension.

    `scale` is how many canonical units one of these is worth, so `FOOT` holds
    0.3048. The dimension exponents are part of the type, which is what stops
    a length being converted to seconds.

    The scale is a `Float32` unless `dtype` says otherwise, so a unit is
    safe in GPU code, which has no `Float64`. A unit of either float type
    converts a quantity of either float type. Declare a `Float64` unit
    where a `Float64` quantity must keep every digit of an inexact factor,
    such as the foot's 0.3048.
    """

    var scale: Scalar[Self.dtype]
    var symbol: StaticString


@fieldwise_init
struct Quantity[
    length: Int,
    mass: Int,
    time: Int,
    angle: Int,
    temperature: Int = 0,
    dtype: DType = DType.float32,
](Absable, ImplicitlyCopyable):
    """A value measured in the dimension given by the exponents."""

    var value: Scalar[Self.dtype]

    def __init__[
        unit_dtype: DType
    ](
        out self,
        value: Scalar[Self.dtype],
        unit: Unit[
            Self.length,
            Self.mass,
            Self.time,
            Self.angle,
            Self.temperature,
            unit_dtype,
        ],
    ):
        """Create a quantity from a value expressed in `unit`.

        The unit's dimensions must match this quantity's, which the type
        system enforces at the call site.

        Parameters:
            unit_dtype: The unit's float type.

        Args:
            value: The magnitude in `unit`.
            unit: The unit the magnitude is written in.
        """
        self.value = value * unit.scale.cast[Self.dtype]()

    def to[
        unit_dtype: DType
    ](
        self,
        unit: Unit[
            Self.length,
            Self.mass,
            Self.time,
            Self.angle,
            Self.temperature,
            unit_dtype,
        ],
    ) -> Scalar[Self.dtype]:
        """Return this quantity's magnitude expressed in `unit`.

        Parameters:
            unit_dtype: The unit's float type.

        Args:
            unit: The unit to read the magnitude in.

        Returns:
            The magnitude in `unit`.
        """
        return self.value / unit.scale.cast[Self.dtype]()

    def cast[
        target: DType
    ](self) -> Quantity[
        Self.length,
        Self.mass,
        Self.time,
        Self.angle,
        Self.temperature,
        target,
    ]:
        """Return this quantity stored in another float type.

        Parameters:
            target: The float type to store the magnitude in.

        Returns:
            The same quantity, rounded to `target` if it is narrower.
        """
        return Quantity[
            Self.length,
            Self.mass,
            Self.time,
            Self.angle,
            Self.temperature,
            target,
        ](self.value.cast[target]())

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
        return Self(abs(self.value))

    def scaled(self, factor: Scalar[Self.dtype]) -> Self:
        """Return this quantity multiplied by a plain number.

        Scaling by a bare float cannot change the dimension, so this is kept
        separate from multiplying by another quantity.
        """
        return Self(self.value * factor)

    # --- arithmetic that changes the dimension ----------------------------

    def __mul__[
        l2: Int, m2: Int, t2: Int, a2: Int, k2: Int
    ](self, other: Quantity[l2, m2, t2, a2, k2, Self.dtype]) -> Quantity[
        Self.length + l2,
        Self.mass + m2,
        Self.time + t2,
        Self.angle + a2,
        Self.temperature + k2,
        Self.dtype,
    ]:
        """Multiply two quantities, adding their dimension exponents."""
        return Quantity[
            Self.length + l2,
            Self.mass + m2,
            Self.time + t2,
            Self.angle + a2,
            Self.temperature + k2,
            Self.dtype,
        ](self.value * other.value)

    def __truediv__[
        l2: Int, m2: Int, t2: Int, a2: Int, k2: Int
    ](self, other: Quantity[l2, m2, t2, a2, k2, Self.dtype]) -> Quantity[
        Self.length - l2,
        Self.mass - m2,
        Self.time - t2,
        Self.angle - a2,
        Self.temperature - k2,
        Self.dtype,
    ]:
        """Divide two quantities, subtracting their dimension exponents."""
        return Quantity[
            Self.length - l2,
            Self.mass - m2,
            Self.time - t2,
            Self.angle - a2,
            Self.temperature - k2,
            Self.dtype,
        ](self.value / other.value)

    def sqrt(
        self,
    ) -> Quantity[
        Self.length // 2,
        Self.mass // 2,
        Self.time // 2,
        Self.angle // 2,
        Self.temperature // 2,
        Self.dtype,
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
        comptime assert (
            Self.temperature % 2 == 0
        ), "sqrt needs an even temperature exponent"
        return Quantity[
            Self.length // 2,
            Self.mass // 2,
            Self.time // 2,
            Self.angle // 2,
            Self.temperature // 2,
            Self.dtype,
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
