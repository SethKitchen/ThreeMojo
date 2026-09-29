# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sensor header's type must be a `SensorType`, not a bare integer."""

from extensions.carla.sensor_data import sensor_header
from extensions.carla.transform import CarlaRotation, CarlaTransform
from units.si import DEGREE, METER, Angle, Length


def main() raises:
    var pose = CarlaTransform(
        Length(0, METER),
        Length(0, METER),
        Length(0, METER),
        CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE)),
    )
    print(len(sensor_header(5, 0, 0, pose)))
