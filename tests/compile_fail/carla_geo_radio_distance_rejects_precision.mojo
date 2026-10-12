# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject precision input at the radio_distance quantity boundary."""

from extensions.carla.v2x import PathLossModel, PropagationParams, LOS
from units.si import Acceleration, Angle, Angle64, Duration, Length, Length64


def main() raises:
    var model = PathLossModel(PropagationParams())
    _ = model.winner(LOS, Length(0))
