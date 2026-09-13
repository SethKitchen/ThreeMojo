# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Named dimensions and the units that measure them.

The aliases below name the combinations of exponents worth having a word for,
so code says `Length` rather than `Quantity[1, 0, 0, 0]`. They are aliases,
not new types, so `Length * Length` produces exactly the `Area` alias and the
two are interchangeable.

Imperial conversion factors are the exact international definitions, not
approximations: a yard was defined as exactly 0.9144 m in 1959, and the foot
and inch follow from it.
"""

from units.quantity import Quantity, Unit

# --- dimensions -------------------------------------------------------------
# Exponent order is length, mass, time, angle.
comptime Scalar = Quantity[0, 0, 0, 0]
comptime Length = Quantity[1, 0, 0, 0]
comptime Area = Quantity[2, 0, 0, 0]
comptime Volume = Quantity[3, 0, 0, 0]
comptime Mass = Quantity[0, 1, 0, 0]
comptime Duration = Quantity[0, 0, 1, 0]
comptime Angle = Quantity[0, 0, 0, 1]
comptime Velocity = Quantity[1, 0, -1, 0]
comptime Acceleration = Quantity[1, 0, -2, 0]
comptime AngularVelocity = Quantity[0, 0, -1, 1]

comptime LengthUnit = Unit[1, 0, 0, 0]
comptime AreaUnit = Unit[2, 0, 0, 0]
comptime MassUnit = Unit[0, 1, 0, 0]
comptime DurationUnit = Unit[0, 0, 1, 0]
comptime AngleUnit = Unit[0, 0, 0, 1]

# --- length -----------------------------------------------------------------
comptime METRE = LengthUnit(1.0, "m")
comptime KILOMETRE = LengthUnit(1000.0, "km")
comptime CENTIMETRE = LengthUnit(0.01, "cm")
comptime MILLIMETRE = LengthUnit(0.001, "mm")

# Exact by the 1959 international agreement: 1 yd = 0.9144 m exactly.
comptime YARD = LengthUnit(0.9144, "yd")
comptime FOOT = LengthUnit(0.3048, "ft")
comptime INCH = LengthUnit(0.0254, "in")
comptime MILE = LengthUnit(1609.344, "mi")

# --- area -------------------------------------------------------------------
comptime SQUARE_METRE = AreaUnit(1.0, "m^2")
comptime SQUARE_FOOT = AreaUnit(0.09290304, "ft^2")

# --- mass -------------------------------------------------------------------
comptime KILOGRAM = MassUnit(1.0, "kg")
comptime GRAM = MassUnit(0.001, "g")
comptime POUND = MassUnit(0.45359237, "lb")

# --- time -------------------------------------------------------------------
comptime SECOND = DurationUnit(1.0, "s")
comptime MILLISECOND = DurationUnit(0.001, "ms")
comptime MINUTE = DurationUnit(60.0, "min")
comptime HOUR = DurationUnit(3600.0, "h")

# --- angle ------------------------------------------------------------------
comptime RADIAN = AngleUnit(1.0, "rad")
comptime DEGREE = AngleUnit(0.017453292519943295, "deg")
comptime TURN = AngleUnit(6.283185307179586, "turn")
