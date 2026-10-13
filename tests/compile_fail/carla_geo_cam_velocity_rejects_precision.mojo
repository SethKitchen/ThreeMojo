# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject precision input at the cam_velocity quantity boundary."""

from extensions.carla.v2x import CamNoise
from units.si import (
    Acceleration,
    Angle,
    Angle64,
    Duration,
    Length,
    Length64,
    Velocity,
    Velocity64,
)


def main() raises:
    var noise = CamNoise()
    noise.set_velocity_noise(Velocity64(0))
