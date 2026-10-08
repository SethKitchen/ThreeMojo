# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject dimensional or kind misuse at speed boundaries."""

from extensions.carla.road_info import RoadInfoSpeed


def main() raises:
    var record = RoadInfoSpeed(0, 1, "Town", "m/s")
    record.kind = 0
