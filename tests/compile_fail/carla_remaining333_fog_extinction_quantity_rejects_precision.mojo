# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject precision assignment of the typed fog extinction result."""

from extensions.carla.render_weather import HeightFog
from extensions.carla.render_light import fog_density_at
from math.vector3 import Vector3
from units.si import (
    Duration,
    Duration64,
    Length,
    Length64,
    Angle,
    Angle64,
    Velocity,
    Velocity64,
    Area,
    Area64,
    InverseLength,
    InverseLength64,
)


def main() raises:
    var fog = HeightFog(
        InverseLength(0.1), Length(0), InverseLength(0), 1, InverseLength(0)
    )
    var result: InverseLength64 = fog_density_at(fog, Length(0))
    _ = result
