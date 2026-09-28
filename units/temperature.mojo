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
"""


@fieldwise_init
struct TemperatureUnit(ImplicitlyCopyable):
    """A named temperature scale: how many kelvin one step is, and where its
    zero is in kelvin."""

    var scale: Float32
    var zero: Float32
    var symbol: StaticString


comptime KELVIN = TemperatureUnit(1.0, 0.0, "K")
comptime CELSIUS = TemperatureUnit(1.0, 273.15, "degC")


struct Temperature(ImplicitlyCopyable):
    """A temperature, stored in kelvin."""

    var kelvin: Float32

    def __init__(out self, value: Float32, unit: TemperatureUnit):
        """Create a temperature from a value on a scale.

        Args:
            value: The reading.
            unit: The scale it is read on, `KELVIN` or `CELSIUS`.
        """
        self.kelvin = value * unit.scale + unit.zero

    def to(self, unit: TemperatureUnit) -> Float32:
        """Return the temperature read on a scale.

        Args:
            unit: The scale.

        Returns:
            The reading.
        """
        return (self.kelvin - unit.zero) / unit.scale
