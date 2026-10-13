# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject raw input at the dvs angle quantity boundary."""

from extensions.carla.sensor_data import dvs_data
from extensions.carla.cameras import DVSEvent
from units.si import (
    Duration,
    Duration64,
    Length,
    Length64,
    Angle,
    Angle64,
    Velocity,
    Velocity64,
    Area,
    Area64,
    InverseLength,
    InverseLength64,
)


def main() raises:
    _ = dvs_data(1, 1, Float32(1), List[DVSEvent]())
