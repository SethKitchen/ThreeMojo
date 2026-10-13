# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject raw input at the pid duration quantity boundary."""

from extensions.carla.physics.vehicle_control import PID
from units.si import (
    Length64,
    Length,
    Duration,
    Duration64,
    Velocity,
    Velocity64,
)


def main() raises:
    var pid = PID(1, 0, 0)
    _ = pid.run(0, Float32(1))
