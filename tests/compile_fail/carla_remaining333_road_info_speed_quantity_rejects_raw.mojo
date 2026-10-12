# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject raw input at the wide road-speed quantity boundary."""

from extensions.carla.road_info import RoadInfoSpeed
from units.si import Length64, Velocity, Velocity64


def main() raises:
    _ = RoadInfoSpeed(Length64(0), Float64(1), "town")
