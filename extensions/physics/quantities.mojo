# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The dimensions the vehicle model needs that `units.si` does not name.

A torque and an energy have the same dimension, a force times a length, so
both are the one alias `Torque`. A spring rate is a force per length. A
cornering stiffness is a force per angle of slip. A damping rate is a force
per speed.
"""

from std.math import pi
from units.quantity import Quantity, Unit
from units.si import (
    AngularAccelerationUnit,
    AngularVelocityUnit,
    Energy,
    JOULE,
    NEWTON_METER,
    NEWTON_PER_METER,
    VelocityUnit,
)

# Force times length: a torque, or the kinetic energy of a body.
comptime Torque = Quantity[2, 1, -2, 0]
# Mass times speed: a linear momentum, or an impulse.
comptime Momentum = Quantity[1, 1, -1, 0]
# Force per length: a spring rate.
comptime Stiffness = Quantity[0, 1, -2, 0]
# Force per speed: a damper.
comptime DampingRate = Quantity[0, 1, -1, 0]
# Force per angle: how much side force a tire makes per angle of slip.
comptime CorneringStiffness = Quantity[1, 1, -2, -1]

comptime TorqueUnit = Unit[2, 1, -2, 0]
comptime MomentumUnit = Unit[1, 1, -1, 0]
comptime StiffnessUnit = Unit[0, 1, -2, 0]
comptime DampingRateUnit = Unit[0, 1, -1, 0]
comptime CorneringStiffnessUnit = Unit[1, 1, -2, -1]

comptime NEWTON_SECOND = MomentumUnit(1.0, "N s")
# CARLA's lengths are in centimeters, so a spring rate is in N/cm.
comptime NEWTON_PER_CENTIMETER = StiffnessUnit(100.0, "N/cm")
comptime NEWTON_SECOND_PER_METER = DampingRateUnit(1.0, "N s/m")
comptime NEWTON_PER_DEGREE = CorneringStiffnessUnit(
    Float32(180.0 / pi), "N/deg"
)

# An engine speed. One revolution is two pi radians.
comptime REVOLUTION_PER_MINUTE = AngularVelocityUnit(
    Float32(2.0 * pi / 60.0), "rpm"
)
# How fast an engine speed falls, CARLA's `rev_down_rate`.
comptime REVOLUTION_PER_MINUTE_PER_SECOND = AngularAccelerationUnit(
    Float32(2.0 * pi / 60.0), "rpm/s"
)
comptime KILOMETER_PER_HOUR = VelocityUnit(Float32(1.0 / 3.6), "km/h")
# Exact: 1609.344 m per 3600 s.
comptime MILE_PER_HOUR = VelocityUnit(0.44704, "mph")
# Length per second cubed: how fast an acceleration changes.
comptime Jerk = Quantity[1, 0, -3, 0]
comptime JerkUnit = Unit[1, 0, -3, 0]
comptime METER_PER_SECOND_CUBED = JerkUnit(1.0, "m/s^3")
