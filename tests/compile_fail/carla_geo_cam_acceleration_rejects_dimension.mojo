# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject dimension input at the cam_acceleration quantity boundary."""

from extensions.carla.v2x import CamNoise
from units.si import (
    Acceleration,
    Acceleration64,
    Angle,
    Angle64,
    Duration,
    Length,
    Length64,
)


def main() raises:
    var noise = CamNoise()
    noise.set_acceleration_noise(Length(0), Acceleration(0), Acceleration(0))
