# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A measurement's typed time is a Duration64, not a raw Float64."""

from extensions.carla.sensor_manager import SensorMeasurement


def seconds(measurement: SensorMeasurement) raises -> Float64:
    var elapsed: Float64 = measurement.elapsed()
    return elapsed


def main() raises:
    pass
