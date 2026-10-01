# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A differential must be a `DifferentialType`, not a bare integer."""

from extensions.carla.physics.vehicle_physics import VehiclePhysicsControl


def main():
    var physics = VehiclePhysicsControl()
    physics.differential_type = 2
    print(physics.differential_type.is_valid())
