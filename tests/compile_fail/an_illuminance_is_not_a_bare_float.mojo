# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for an illuminance: say its unit with
`Illuminance(20000, LUX)`."""

from extensions.carla.render_weather import light_units


def main() raises:
    print(light_units(20000.0))
