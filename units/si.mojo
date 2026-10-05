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
# Exponent order is length, mass, time, angle, temperature. The temperature
# exponent defaults to zero.
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
# How fast a turn slows: ArcballControls' `dampingFactor`.
comptime AngularAcceleration = Quantity[0, 0, -2, 1]
# Per unit of length: how fast an exponential fog thickens with depth.
comptime InverseLength = Quantity[-1, 0, 0, 0]
# Per unit of time: how fast a controller's speed grows with height.
comptime Frequency = Quantity[0, 0, -1, 0]
# Mass per volume: what a tissue density is measured in.
comptime Density = Quantity[-3, 1, 0, 0]
# Mass times acceleration: a weight, or any other force.
comptime Force = Quantity[1, 1, -2, 0]
# Force per area: an elastic modulus is a pressure.
comptime Pressure = Quantity[-1, 1, -2, 0]
# Mass times length squared: how a rigid body resists turning.
comptime MomentOfInertia = Quantity[2, 1, 0, 0]

# Mass times length squared per time squared: a work, or a heat.
comptime Energy = Quantity[2, 1, -2, 0]
# Energy per time: a heating load, or a lamp's output.
comptime Power = Quantity[2, 1, -3, 0]
# Power per area: a heat flux, or the sun on a wall.
comptime HeatFlux = Quantity[0, 1, -3, 0]
# Power per length per kelvin: how well a material conducts heat.
comptime ThermalConductivity = Quantity[1, 1, -3, 0, -1]
# Power per area per kelvin: a U-value, or a film coefficient.
comptime ThermalTransmittance = Quantity[0, 1, -3, 0, -1]
# Area times kelvin per power: an R-value, the inverse of a U-value.
comptime ThermalResistance = Quantity[0, -1, 3, 0, 1]
# Energy per mass per kelvin.
comptime SpecificHeatCapacity = Quantity[2, 0, -2, 0, -1]
# Energy per kelvin: what a zone or a wall layer stores.
comptime HeatCapacity = Quantity[2, 1, -2, 0, -1]
# Power per kelvin: a whole conductance, such as a wall's U times its area.
comptime ThermalConductance = Quantity[2, 1, -3, 0, -1]
# Per kelvin: how much a material grows as it warms.
comptime ThermalExpansion = Quantity[0, 0, 0, 0, -1]
# Force times length: a bending moment, or a torque.
comptime Moment = Quantity[2, 1, -2, 0]
# Force per length: a line load along a beam.
comptime LineLoad = Quantity[0, 1, -2, 0]
# Length to the fourth: the second moment of area of a section.
comptime SecondMomentOfArea = Quantity[4, 0, 0, 0]
# Volume per time: an air flow.
comptime VolumeFlowRate = Quantity[3, 0, -1, 0]
# Mass per time.
comptime MassFlowRate = Quantity[0, 1, -1, 0]

# The same dimensions in Float64, for engineering analysis.
comptime Scalar64 = Quantity[0, 0, 0, 0, 0, DType.float64]
comptime Length64 = Quantity[1, 0, 0, 0, 0, DType.float64]
comptime Area64 = Quantity[2, 0, 0, 0, 0, DType.float64]
comptime Volume64 = Quantity[3, 0, 0, 0, 0, DType.float64]
comptime Mass64 = Quantity[0, 1, 0, 0, 0, DType.float64]
comptime Duration64 = Quantity[0, 0, 1, 0, 0, DType.float64]
comptime Angle64 = Quantity[0, 0, 0, 1, 0, DType.float64]
comptime Velocity64 = Quantity[1, 0, -1, 0, 0, DType.float64]
comptime Acceleration64 = Quantity[1, 0, -2, 0, 0, DType.float64]
comptime Frequency64 = Quantity[0, 0, -1, 0, 0, DType.float64]
comptime Density64 = Quantity[-3, 1, 0, 0, 0, DType.float64]
comptime Force64 = Quantity[1, 1, -2, 0, 0, DType.float64]
comptime Pressure64 = Quantity[-1, 1, -2, 0, 0, DType.float64]
comptime Energy64 = Quantity[2, 1, -2, 0, 0, DType.float64]
comptime Power64 = Quantity[2, 1, -3, 0, 0, DType.float64]
comptime HeatFlux64 = Quantity[0, 1, -3, 0, 0, DType.float64]
comptime ThermalConductivity64 = Quantity[1, 1, -3, 0, -1, DType.float64]
comptime ThermalTransmittance64 = Quantity[0, 1, -3, 0, -1, DType.float64]
comptime ThermalResistance64 = Quantity[0, -1, 3, 0, 1, DType.float64]
comptime SpecificHeatCapacity64 = Quantity[2, 0, -2, 0, -1, DType.float64]
comptime HeatCapacity64 = Quantity[2, 1, -2, 0, -1, DType.float64]
comptime ThermalConductance64 = Quantity[2, 1, -3, 0, -1, DType.float64]
comptime ThermalExpansion64 = Quantity[0, 0, 0, 0, -1, DType.float64]
comptime Moment64 = Quantity[2, 1, -2, 0, 0, DType.float64]
comptime LineLoad64 = Quantity[0, 1, -2, 0, 0, DType.float64]
comptime SecondMomentOfArea64 = Quantity[4, 0, 0, 0, 0, DType.float64]
comptime VolumeFlowRate64 = Quantity[3, 0, -1, 0, 0, DType.float64]
comptime MassFlowRate64 = Quantity[0, 1, -1, 0, 0, DType.float64]

comptime LengthUnit = Unit[1, 0, 0, 0]
comptime AreaUnit = Unit[2, 0, 0, 0]
comptime VolumeUnit = Unit[3, 0, 0, 0]
comptime MassUnit = Unit[0, 1, 0, 0]
comptime DurationUnit = Unit[0, 0, 1, 0]
comptime AngleUnit = Unit[0, 0, 0, 1]
comptime InverseLengthUnit = Unit[-1, 0, 0, 0]
comptime VelocityUnit = Unit[1, 0, -1, 0]
comptime AccelerationUnit = Unit[1, 0, -2, 0]
comptime AngularVelocityUnit = Unit[0, 0, -1, 1]
comptime AngularAccelerationUnit = Unit[0, 0, -2, 1]
comptime FrequencyUnit = Unit[0, 0, -1, 0]
comptime DensityUnit = Unit[-3, 1, 0, 0]
comptime ForceUnit = Unit[1, 1, -2, 0]
comptime PressureUnit = Unit[-1, 1, -2, 0]
comptime MomentOfInertiaUnit = Unit[2, 1, 0, 0]
comptime EnergyUnit = Unit[2, 1, -2, 0]
comptime PowerUnit = Unit[2, 1, -3, 0]
comptime HeatFluxUnit = Unit[0, 1, -3, 0]
comptime ThermalConductivityUnit = Unit[1, 1, -3, 0, -1]
comptime ThermalTransmittanceUnit = Unit[0, 1, -3, 0, -1]
comptime ThermalResistanceUnit = Unit[0, -1, 3, 0, 1]
comptime SpecificHeatCapacityUnit = Unit[2, 0, -2, 0, -1]
comptime HeatCapacityUnit = Unit[2, 1, -2, 0, -1]
comptime ThermalConductanceUnit = Unit[2, 1, -3, 0, -1]
comptime ThermalExpansionUnit = Unit[0, 0, 0, 0, -1]
comptime MomentUnit = Unit[2, 1, -2, 0]
comptime LineLoadUnit = Unit[0, 1, -2, 0]
comptime SecondMomentOfAreaUnit = Unit[4, 0, 0, 0]
comptime VolumeFlowRateUnit = Unit[3, 0, -1, 0]
comptime MassFlowRateUnit = Unit[0, 1, -1, 0]

# --- length -----------------------------------------------------------------
comptime METER = LengthUnit(1.0, "m")
comptime KILOMETER = LengthUnit(1000.0, "km")
comptime CENTIMETER = LengthUnit(0.01, "cm")
comptime MILLIMETER = LengthUnit(0.001, "mm")
# What a thin film is measured in: a light wave is a few hundred of them.
comptime NANOMETER = LengthUnit(1e-9, "nm")
# The one unit of inverse length: what a fog density is measured in.
comptime PER_METER = InverseLengthUnit(1.0, "1/m")

# Exact by the 1959 international agreement: 1 yd = 0.9144 m exactly.
comptime YARD = LengthUnit(0.9144, "yd")
comptime FOOT = LengthUnit(0.3048, "ft")
comptime INCH = LengthUnit(0.0254, "in")
comptime MILE = LengthUnit(1609.344, "mi")

# --- area -------------------------------------------------------------------
comptime SQUARE_METER = AreaUnit(1.0, "m^2")
comptime SQUARE_FOOT = AreaUnit(0.09290304, "ft^2")

# --- volume -----------------------------------------------------------------
comptime CUBIC_METER = VolumeUnit(1.0, "m^3")
comptime CUBIC_CENTIMETER = VolumeUnit(1.0e-6, "cm^3")

# --- mass -------------------------------------------------------------------
comptime KILOGRAM = MassUnit(1.0, "kg")
comptime GRAM = MassUnit(0.001, "g")
comptime POUND = MassUnit(0.45359237, "lb")

# --- density ----------------------------------------------------------------
# 1 g/cm^3 is exactly 1000 kg/m^3.
comptime KILOGRAM_PER_CUBIC_METER = DensityUnit(1.0, "kg/m^3")
comptime GRAM_PER_CUBIC_CENTIMETER = DensityUnit(1000.0, "g/cm^3")

# --- acceleration -----------------------------------------------------------
# Exact conventional standard gravity, 3rd CGPM (1901).
comptime STANDARD_GRAVITY = Acceleration(9.80665)

# --- force ------------------------------------------------------------------
comptime NEWTON = ForceUnit(1.0, "N")
# Exact: 0.45359237 kg * 9.80665 m/s^2.
comptime POUND_FORCE = ForceUnit(4.4482216152605, "lbf")

# --- pressure ---------------------------------------------------------------
comptime PASCAL = PressureUnit(1.0, "Pa")
comptime MEGAPASCAL = PressureUnit(1.0e6, "MPa")
comptime GIGAPASCAL = PressureUnit(1.0e9, "GPa")

# --- moment of inertia --------------------------------------------------------
comptime KILOGRAM_SQUARE_METER = MomentOfInertiaUnit(1.0, "kg m^2")

# --- time -------------------------------------------------------------------
comptime SECOND = DurationUnit(1.0, "s")
comptime MILLISECOND = DurationUnit(0.001, "ms")
comptime MINUTE = DurationUnit(60.0, "min")
comptime HOUR = DurationUnit(3600.0, "h")

# --- angle ------------------------------------------------------------------
comptime RADIAN = AngleUnit(1.0, "rad")
comptime DEGREE = AngleUnit(0.017453292519943295, "deg")
comptime TURN = AngleUnit(6.283185307179586, "turn")

# --- speed ------------------------------------------------------------------
comptime METER_PER_SECOND = VelocityUnit(1.0, "m/s")
comptime METER_PER_SECOND_SQUARED = AccelerationUnit(1.0, "m/s^2")
comptime RADIAN_PER_SECOND = AngularVelocityUnit(1.0, "rad/s")
comptime DEGREE_PER_SECOND = AngularVelocityUnit(0.017453292519943295, "deg/s")
comptime PER_SECOND = FrequencyUnit(1.0, "1/s")
comptime RADIAN_PER_SECOND_SQUARED = AngularAccelerationUnit(1.0, "rad/s^2")

# --- energy and power -------------------------------------------------------
comptime JOULE = EnergyUnit(1.0, "J")
comptime KILOWATT_HOUR = EnergyUnit(3.6e6, "kWh")
comptime WATT = PowerUnit(1.0, "W")
comptime KILOWATT = PowerUnit(1000.0, "kW")
comptime WATT_PER_SQUARE_METER = HeatFluxUnit(1.0, "W/m^2")

# --- heat transfer ----------------------------------------------------------
comptime WATT_PER_METER_KELVIN = ThermalConductivityUnit(1.0, "W/(m K)")
comptime WATT_PER_SQUARE_METER_KELVIN = ThermalTransmittanceUnit(
    1.0, "W/(m^2 K)"
)
comptime SQUARE_METER_KELVIN_PER_WATT = ThermalResistanceUnit(1.0, "m^2 K/W")
comptime JOULE_PER_KILOGRAM_KELVIN = SpecificHeatCapacityUnit(1.0, "J/(kg K)")
comptime JOULE_PER_KELVIN = HeatCapacityUnit(1.0, "J/K")
comptime WATT_PER_KELVIN = ThermalConductanceUnit(1.0, "W/K")
comptime PER_KELVIN = ThermalExpansionUnit(1.0, "1/K")

# --- structure --------------------------------------------------------------
comptime NEWTON_METER = MomentUnit(1.0, "N m")
comptime KILONEWTON_METER = MomentUnit(1000.0, "kN m")
comptime KILONEWTON = ForceUnit(1000.0, "kN")
comptime NEWTON_PER_METER = LineLoadUnit(1.0, "N/m")
comptime KILONEWTON_PER_METER = LineLoadUnit(1000.0, "kN/m")
comptime KILOPASCAL = PressureUnit(1000.0, "kPa")
comptime METER_TO_THE_FOURTH = SecondMomentOfAreaUnit(1.0, "m^4")

# --- flow -------------------------------------------------------------------
comptime CUBIC_METER_PER_SECOND = VolumeFlowRateUnit(1.0, "m^3/s")
comptime KILOGRAM_PER_SECOND = MassFlowRateUnit(1.0, "kg/s")

# --- exact factors for Float64 quantities -------------------------------------
# A unit's factor is a Float32 by default, which suits GPU code. These keep
# every digit of a factor that a Float32 rounds, for Float64 engineering
# input.
comptime FOOT64 = Unit[1, 0, 0, 0, 0, DType.float64](0.3048, "ft")
comptime INCH64 = Unit[1, 0, 0, 0, 0, DType.float64](0.0254, "in")
comptime DEGREE64 = Unit[0, 0, 0, 1, 0, DType.float64](
    0.017453292519943295, "deg"
)
