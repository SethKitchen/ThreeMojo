# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The units of flow analysis, in Float64.

A dynamic viscosity is a pressure times a time. A kinematic viscosity is
an area per time: the dynamic viscosity over the density.
"""

from units.quantity import Quantity, Unit

# Pressure times time: the dynamic viscosity μ of a fluid.
comptime DynamicViscosity64 = Quantity[-1, 1, -1, 0, 0, DType.float64]
comptime DynamicViscosityUnit64 = Unit[-1, 1, -1, 0, 0, DType.float64]
# Area per time: the kinematic viscosity ν = μ / ρ of a fluid.
comptime KinematicViscosity64 = Quantity[2, 0, -1, 0, 0, DType.float64]
comptime KinematicViscosityUnit64 = Unit[2, 0, -1, 0, 0, DType.float64]

comptime PASCAL_SECOND = DynamicViscosityUnit64(1.0, "Pa s")
# One centipoise. Water at 20 °C is close to one.
comptime CENTIPOISE = DynamicViscosityUnit64(0.001, "cP")
comptime SQUARE_METER_PER_SECOND = KinematicViscosityUnit64(1.0, "m^2/s")
# One centistokes.
comptime CENTISTOKES = KinematicViscosityUnit64(1.0e-6, "cSt")
