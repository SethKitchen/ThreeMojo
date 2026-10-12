# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject dimension input at the location_angle quantity boundary."""

from extensions.carla.geo import GeoLocation
from units.si import Acceleration, Angle, Angle64, Duration, Length, Length64


def main() raises:
    _ = GeoLocation(Length64(0), Angle64(0), Length64(0))
