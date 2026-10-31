# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The US customary units of design work, in Float64.

The codes state their equations in pounds, kips, inches and feet. These
units let a design check take and return SI quantities while it reads
its inputs in the units of the code. The factors follow from the exact
international pound force, 4.4482216152605 N, and foot, 0.3048 m.

The pound per square foot, the kip and the other units of
`extensions.geotech.quantities` are not repeated here.
"""

from units.quantity import Unit

comptime ForceUnit64 = Unit[1, 1, -2, 0, 0, DType.float64]
comptime MomentUnit64 = Unit[2, 1, -2, 0, 0, DType.float64]
comptime PressureUnit64 = Unit[-1, 1, -2, 0, 0, DType.float64]
comptime AreaUnit64 = Unit[2, 0, 0, 0, 0, DType.float64]
comptime VolumeUnit64 = Unit[3, 0, 0, 0, 0, DType.float64]
comptime InertiaUnit64 = Unit[4, 0, 0, 0, 0, DType.float64]
comptime VelocityUnit64 = Unit[1, 0, -1, 0, 0, DType.float64]
comptime LineLoadUnit64 = Unit[0, 1, -2, 0, 0, DType.float64]

# The pound force.
comptime POUND64 = ForceUnit64(4.4482216152605, "lb")
# The pound per square inch.
comptime PSI = PressureUnit64(6894.757293168361, "psi")
# The kip inch, 4448.2216152605 N times 0.0254 m.
comptime KIP_INCH = MomentUnit64(112.98482902761668, "kip in")
# The kip foot, 4448.2216152605 N times 0.3048 m.
comptime KIP_FOOT = MomentUnit64(1355.8179483314004, "kip ft")
# The pound foot.
comptime POUND_FOOT = MomentUnit64(1.3558179483314004, "lb ft")
# The square inch.
comptime SQUARE_INCH = AreaUnit64(0.00064516, "in^2")
# The square foot.
comptime SQUARE_FOOT64 = AreaUnit64(0.09290304, "ft^2")
# The cubic inch, for a section modulus.
comptime CUBIC_INCH = VolumeUnit64(1.6387064e-5, "in^3")
# The inch to the fourth, for a second moment of area.
comptime INCH_TO_THE_FOURTH = InertiaUnit64(4.162314256e-7, "in^4")
# The mile per hour, for a wind speed.
comptime MILE_PER_HOUR = VelocityUnit64(0.44704, "mph")
# The pound per inch, for a line load in the units of a deflection formula.
comptime POUND_PER_INCH = LineLoadUnit64(175.12683524647636, "lb/in")
