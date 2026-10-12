# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A CAM speed deviation is a Velocity, not a Duration."""

from extensions.carla.v2x import CamNoise
from units.si import (
    DEGREE,
    METER,
    SECOND,
    Acceleration,
    Angle,
    AngularVelocity,
    Duration,
    Length,
)


def noise() raises:
    _ = CamNoise(
        Angle(0, DEGREE),
        Angle(0, DEGREE),
        Angle(0, DEGREE),
        Angle(0, DEGREE),
        Length(0, METER),
        Length(0, METER),
        Angle(0, DEGREE),
        Angle(0, DEGREE),
        Duration(1, SECOND),
        AngularVelocity(0),
        AngularVelocity(0),
        Acceleration(0),
        Acceleration(0),
        Acceleration(0),
    )


def main() raises:
    pass
