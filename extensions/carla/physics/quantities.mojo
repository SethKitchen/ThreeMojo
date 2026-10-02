# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compatibility imports for `extensions.physics.quantities`.

Existing CARLA imports keep the same types and functions. New simulations
can import the shared module directly.
"""

from extensions.physics.quantities import (
    Torque,
    Energy,
    Momentum,
    Stiffness,
    DampingRate,
    CorneringStiffness,
    TorqueUnit,
    MomentumUnit,
    StiffnessUnit,
    DampingRateUnit,
    CorneringStiffnessUnit,
    NEWTON_METER,
    JOULE,
    NEWTON_SECOND,
    NEWTON_PER_METER,
    NEWTON_PER_CENTIMETER,
    NEWTON_SECOND_PER_METER,
    NEWTON_PER_DEGREE,
    REVOLUTION_PER_MINUTE,
    REVOLUTION_PER_MINUTE_PER_SECOND,
    KILOMETER_PER_HOUR,
    MILE_PER_HOUR,
    Jerk,
    JerkUnit,
    METER_PER_SECOND_CUBED,
)
