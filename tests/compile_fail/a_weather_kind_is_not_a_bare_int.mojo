# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A weather must be a `WeatherKind`, not a bare integer."""

from extensions.village.weather import weather_look


def main() raises:
    var look = weather_look(2)
    print(look.rain)
