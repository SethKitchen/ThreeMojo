# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject raw input at the builder profile quantity boundary."""

from extensions.carla.map_builder import MapBuilder
from units.si import (
    Length64,
    Angle64,
    InverseLength64,
    InverseArea64,
    Duration64,
    Length,
    Angle,
    InverseLength,
)
from units.quantity import Quantity


def main() raises:
    var builder = MapBuilder()
    builder.create_lane_width(
        (0, 0, 0), Length64(0), Length64(3.5), 0, Float64(1), InverseArea64(0)
    )
