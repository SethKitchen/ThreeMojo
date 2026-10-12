# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject dimension input at the sign duration quantity boundary."""

from extensions.carla.traffic_sign import TrafficSign, STOP_SIGN
from extensions.carla.road_info import SignalId
from extensions.carla.transform import CarlaTransform, CarlaRotation
from units.si import (
    Length64,
    Length,
    Duration,
    Duration64,
    Velocity,
    Velocity64,
    Angle,
)


def main() raises:
    var sign = TrafficSign(
        SignalId("s"),
        STOP_SIGN,
        CarlaTransform(
            Length(0),
            Length(0),
            Length(0),
            CarlaRotation(Angle(0), Angle(0), Angle(0)),
        ),
        Velocity(0),
    )
    _ = sign.tick_timers(Length(1))
