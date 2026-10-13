# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject precision input at the cam_length quantity boundary."""

from extensions.carla.v2x import CamNoise
from units.si import Acceleration, Angle, Angle64, Duration, Length, Length64


def main() raises:
    var noise = CamNoise()
    noise.set_altitude_noise(Length64(0), Length(0))
