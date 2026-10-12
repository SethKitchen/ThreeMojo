# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A typed weather's fog distance is a Length, not an Angle."""

from extensions.carla.weather import WeatherParameters
from units.si import DEGREE, Angle


def weather():
    _ = WeatherParameters(
        0,
        0,
        0,
        0,
        Angle(10, DEGREE),
        Angle(20, DEGREE),
        0,
        Angle(30, DEGREE),
        0,
        0,
        0,
        0,
        0,
        0,
    )


def main():
    pass
