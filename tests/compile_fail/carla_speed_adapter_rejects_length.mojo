# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject dimensional or kind misuse at speed boundaries."""

from extensions.carla.speed_limits import simulation_speed
from units.si import Length64


def main() raises:
    _ = simulation_speed(Length64(1))
