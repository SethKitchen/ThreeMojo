# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject raw input at the radio_frequency quantity boundary."""

from extensions.carla.v2x import PropagationParams
from units.si import (
    Acceleration,
    Angle,
    Angle64,
    Duration,
    Frequency,
    Frequency64,
    Length,
    Length64,
)


def main() raises:
    var params = PropagationParams()
    params.set_carrier_frequency(Float32(0))
