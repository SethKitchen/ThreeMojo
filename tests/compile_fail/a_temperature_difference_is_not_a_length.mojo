# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A temperature difference does not add to a length."""

from units.si import Length64, METER
from units.temperature import KELVIN_DIFFERENCE, TemperatureDifference64


def main():
    var wall = Length64(0.2, METER)
    var drop = TemperatureDifference64(25.0, KELVIN_DIFFERENCE)
    _ = wall + drop
