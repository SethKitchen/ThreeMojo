# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject a precision mismatch at the weather_distance configuration boundary."""

from extensions.carla.weather import WeatherParameters
from units.si import Angle, Length64


def main() raises:
    _ = WeatherParameters(
        0, 0, 0, 0, Angle(0), Angle(0), 0, Length64(0), 0, 0, 0, 0, 0, 0
    )
