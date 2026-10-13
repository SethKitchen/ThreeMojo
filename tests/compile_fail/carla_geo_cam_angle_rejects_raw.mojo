# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject raw input at the cam_angle quantity boundary."""

from extensions.carla.v2x import CamNoise
from units.si import Acceleration, Angle, Angle64, Duration, Length, Length64


def main() raises:
    var noise = CamNoise()
    noise.set_heading_noise(Float32(0), Angle(0))
