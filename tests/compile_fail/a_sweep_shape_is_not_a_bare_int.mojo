# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sweep shape must be a `SweepShape`, not a bare integer."""

from extensions.carla.physics.vehicle_physics import WheelPhysicsControl


def main():
    var wheel = WheelPhysicsControl()
    wheel.sweep_shape = 1
    print(wheel.sweep_shape.is_valid())
