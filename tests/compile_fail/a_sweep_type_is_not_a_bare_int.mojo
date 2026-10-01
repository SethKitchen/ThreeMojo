# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sweep type must be a `SweepType`, not a bare integer."""

from extensions.carla.physics.vehicle_physics import WheelPhysicsControl


def main():
    var wheel = WheelPhysicsControl()
    wheel.sweep_type = 1
    print(wheel.sweep_type.is_valid())
