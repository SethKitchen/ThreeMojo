# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A thermodynamic temperature, measured from absolute zero.

A `Temperature` is not a `Quantity`. A `Quantity` scales: two lengths add
and a length times a length is an area. A temperature on the Celsius scale
starts at a different zero, so a conversion adds an offset as well as a
scale. It converts, and nothing more.

The value is kept in kelvin. `CELSIUS` is a scale and an offset applied on
the way in and out, as `FOOT` is a scale on a `Length`.

    var bulb = Temperature(3200, KELVIN)
    print(bulb.to(CELSIUS))       # 2926.85

Two temperatures differ by a `TemperatureDifference`, which is a
`Quantity` with a temperature exponent of one. A difference scales and
combines with other quantities: a conductivity times a difference over a
length is a heat flux. A temperature plus a difference is a temperature.

    var inside = Temperature(20, CELSIUS)
    var outside = Temperature(-5, CELSIUS)
    var drop = inside - outside   # 25 K

`Temperature` stores a `Float32`. `Temperature64` stores a `Float64`. Both
are `TemperatureOf`, with its `dtype` parameter set.
"""

from units.quantity import Quantity, Unit

# A temperature difference: one kelvin is one degree Celsius of difference.
comptime TemperatureDifference = Quantity[0, 0, 0, 0, 1]
comptime TemperatureDifference64 = Quantity[0, 0, 0, 0, 1, DType.float64]
comptime TemperatureDifferenceUnit = Unit[0, 0, 0, 0, 1]
comptime KELVIN_DIFFERENCE = TemperatureDifferenceUnit(1.0, "K")


@fieldwise_init
struct TemperatureUnit(ImplicitlyCopyable):
    """A named temperature scale: how many kelvin one step is, and where its
    zero is in kelvin."""

    var scale: Float64
    var zero: Float64
    var symbol: StaticString


comptime KELVIN = TemperatureUnit(1.0, 0.0, "K")
comptime CELSIUS = TemperatureUnit(1.0, 273.15, "degC")


@fieldwise_init
struct TemperatureOf[dtype: DType](ImplicitlyCopyable):
    """A temperature, stored in kelvin, in a chosen float type.

    Name it through `Temperature` or `Temperature64`.
    """

    var kelvin: Scalar[Self.dtype]

    def __init__(out self, value: Scalar[Self.dtype], unit: TemperatureUnit):
        """Create a temperature from a value on a scale.

        Args:
            value: The reading.
            unit: The scale it is read on, `KELVIN` or `CELSIUS`.
        """
        self.kelvin = value * Scalar[Self.dtype](unit.scale) + Scalar[
            Self.dtype
        ](unit.zero)

    def to(self, unit: TemperatureUnit) -> Scalar[Self.dtype]:
        """Return the temperature read on a scale.

        Args:
            unit: The scale.

        Returns:
            The reading.
        """
        return (self.kelvin - Scalar[Self.dtype](unit.zero)) / Scalar[
            Self.dtype
        ](unit.scale)

    def __sub__(self, other: Self) -> Quantity[0, 0, 0, 0, 1, Self.dtype]:
        """Return how much warmer this temperature is than another.

        Args:
            other: The temperature to compare with.

        Returns:
            The difference, negative when `other` is warmer.
        """
        return Quantity[0, 0, 0, 0, 1, Self.dtype](self.kelvin - other.kelvin)

    def __add__(self, difference: Quantity[0, 0, 0, 0, 1, Self.dtype]) -> Self:
        """Return this temperature raised by a difference.

        Args:
            difference: How much warmer to make it.

        Returns:
            The raised temperature.
        """
        return Self(self.kelvin + difference.value)

    def __lt__(self, other: Self) -> Bool:
        """Return True if this temperature is the colder.

        Args:
            other: The temperature to compare with.

        Returns:
            Whether this temperature is below `other`.
        """
        return self.kelvin < other.kelvin

    def is_valid(self) -> Bool:
        """Return True if this is a physical temperature.

        Returns:
            Whether the kelvin value is finite and not below absolute zero.
        """
        return self.kelvin >= 0 and self.kelvin < Scalar[Self.dtype].MAX


comptime Temperature = TemperatureOf[DType.float32]
comptime Temperature64 = TemperatureOf[DType.float64]
