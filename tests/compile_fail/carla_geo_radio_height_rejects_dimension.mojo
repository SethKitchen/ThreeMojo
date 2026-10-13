# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject dimension input at the radio_height quantity boundary."""

from extensions.carla.v2x import PathLossModel, PropagationParams
from units.si import Acceleration, Angle, Angle64, Duration, Length, Length64


def main() raises:
    var model = PathLossModel(PropagationParams())
    _ = model.two_ray(Length64(20), Angle64(0), Length64(1))
