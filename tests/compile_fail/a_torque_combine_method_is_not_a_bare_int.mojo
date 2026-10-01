# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A torque combine method must be a `TorqueCombineMethod`, not a bare
integer."""

from extensions.carla.physics.vehicle_physics import WheelPhysicsControl


def main():
    var wheel = WheelPhysicsControl()
    wheel.external_torque_combine_method = 1
    print(wheel.external_torque_combine_method.is_valid())
