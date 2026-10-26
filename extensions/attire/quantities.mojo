# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The dimension a fabric is weighed in, which `units.si` does not name.

A cloth is sold and compared by its areal density: its mass per area.
The textile trade writes it in grams per square meter, "gsm", or in
ounces per square yard. One ounce per square yard is exactly
28.349523125 g over 0.83612736 m², about 33.906 g/m².

This is not a three.js port. See Extensions.

    var linen = ArealDensity(200, GRAM_PER_SQUARE_METER)
    var mass = linen * Area(1.5, SQUARE_METER)
"""

from units.quantity import Quantity, Unit

comptime ArealDensity = Quantity[-2, 1, 0, 0]
"""Mass per area: the weight of a cloth, or of a plate of given thickness."""
comptime ArealDensityUnit = Unit[-2, 1, 0, 0]
"""A unit of areal density."""

comptime KILOGRAM_PER_SQUARE_METER = ArealDensityUnit(1.0, "kg/m^2")
"""One kilogram per square meter."""
comptime GRAM_PER_SQUARE_METER = ArealDensityUnit(0.001, "g/m^2")
"""One gram per square meter, the textile trade's "gsm"."""
comptime OUNCE_PER_SQUARE_YARD = ArealDensityUnit(
    Float32(0.028349523125 / 0.83612736), "oz/yd^2"
)
"""One ounce per square yard, about 33.906 g/m²."""
