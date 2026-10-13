# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The units of geotechnical work, in Float64.

A unit weight is a force per volume. Soil and water are given by their
unit weight, not by their density, because the codes state them so.

A wall is analyzed per unit length along it. So a force per length of
wall is a `LineLoad64`, and a moment per length of wall has the dimension
of a force, `MomentPerLength64`.

The US customary factors follow from the exact international pound force,
4.4482216152605 N, and foot, 0.3048 m.
"""

from units.quantity import Quantity, Unit

# Force per volume: the unit weight of a soil, of water or of concrete.
comptime UnitWeight64 = Quantity[-2, 1, -2, 0, 0, DType.float64]
comptime UnitWeightUnit64 = Unit[-2, 1, -2, 0, 0, DType.float64]
# Force times length per length: a moment on a unit length of wall.
comptime MomentPerLength64 = Quantity[1, 1, -2, 0, 0, DType.float64]
comptime MomentPerLengthUnit64 = Unit[1, 1, -2, 0, 0, DType.float64]
comptime ForceUnit64 = Unit[1, 1, -2, 0, 0, DType.float64]
comptime PressureUnit64 = Unit[-1, 1, -2, 0, 0, DType.float64]
comptime LineLoadUnit64 = Unit[0, 1, -2, 0, 0, DType.float64]
comptime LengthUnit64 = Unit[1, 0, 0, 0, 0, DType.float64]
comptime AngleUnit64 = Unit[0, 0, 0, 1, 0, DType.float64]

comptime NEWTON_PER_CUBIC_METER = UnitWeightUnit64(1.0, "N/m^3")
comptime KILONEWTON_PER_CUBIC_METER = UnitWeightUnit64(1000.0, "kN/m^3")
# One pound force per cubic foot.
comptime PCF = UnitWeightUnit64(157.08746384624618, "pcf")
# One kip per cubic foot.
comptime KCF = UnitWeightUnit64(157087.46384624616, "kcf")

# One thousand pounds force.
comptime KIP = ForceUnit64(4448.2216152605, "kip")
comptime NEWTON64 = ForceUnit64(1.0, "N")
comptime KIP_FOOT_PER_FOOT = MomentPerLengthUnit64(4448.2216152605, "kip ft/ft")
comptime NEWTON_METER_PER_METER = MomentPerLengthUnit64(1.0, "N m/m")

comptime PASCAL64 = PressureUnit64(1.0, "Pa")
comptime KILOPASCAL64 = PressureUnit64(1000.0, "kPa")
# One kip per square foot.
comptime KSF = PressureUnit64(47880.258980335835, "ksf")
# One pound force per square foot.
comptime PSF = PressureUnit64(47.88025898033584, "psf")
# One kip per square inch.
comptime KSI = PressureUnit64(6894757.293168361, "ksi")

comptime NEWTON_PER_METER64 = LineLoadUnit64(1.0, "N/m")
# One kip per foot.
comptime KLF = LineLoadUnit64(14593.902937206363, "klf")
# One pound force per foot.
comptime PLF = LineLoadUnit64(14.593902937206362, "plf")

comptime METER64 = LengthUnit64(1.0, "m")
comptime RADIAN64 = AngleUnit64(1.0, "rad")

# The unit weight of fresh water that US practice uses, 62.4 pcf.
comptime WATER_62_4_PCF = UnitWeight64(9802.257744005761)
# The unit weight of fresh water at 1000 kg/m^3 and standard gravity.
comptime WATER_SI = UnitWeight64(9806.65)
