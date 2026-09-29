# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A listened sensor must be named by a `SensorKind`, not a bare
integer."""

from extensions.carla.sensor_manager import sensor_type_of


def main() raises:
    print(sensor_type_of(16).value)
