# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An axle type must be an `AxleType`, not a bare integer."""

from extensions.carla.physics.vehicle_physics import WheelPhysicsControl


def main():
    var wheel = WheelPhysicsControl()
    wheel.axle_type = 1
    print(wheel.axle_type.is_valid())
