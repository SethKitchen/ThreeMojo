# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A vehicle role must be a `VehicleRole`, not a bare integer."""

from extensions.carla.v2x import CONTAINER_VEHICLE, LowFrequencyContainer


def main():
    var low = LowFrequencyContainer(CONTAINER_VEHICLE, 1, 0, 0)
    print(low.vehicle_role.is_valid())
