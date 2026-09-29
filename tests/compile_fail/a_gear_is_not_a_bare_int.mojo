# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A gear must be a `Gear`, not a bare integer."""

from extensions.carla.physics.vehicle_control import VehicleControl


def main():
    var control = VehicleControl(0.5, 0, 0, False, False, True, 2)
    print(control)
