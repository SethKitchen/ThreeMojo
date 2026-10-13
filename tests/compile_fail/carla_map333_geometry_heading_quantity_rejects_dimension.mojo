# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject dimension input at the geometry heading quantity boundary."""

from extensions.carla.geometry import RoadGeometry, LINE
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
    _ = RoadGeometry(
        LINE, Length64(0), Length64(0), Length64(0), Duration64(1), Length64(10)
    )
