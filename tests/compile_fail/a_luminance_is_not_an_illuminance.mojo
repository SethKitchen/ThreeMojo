# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A luminance is not an illuminance: light leaving a surface and light
falling on it are different quantities."""

from extensions.carla.render_weather import light_units
from units.photometry import NIT, Luminance


def main() raises:
    print(light_units(Luminance(4000, NIT)))
