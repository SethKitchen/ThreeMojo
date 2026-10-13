# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject dimension input at the loft lengths quantity boundary."""

from extensions.carla.render_actors import loft
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
    _ = loft(
        [Duration(1), Duration(1)],
        [Length(1), Length(1)],
        [Length(0), Length(0)],
        [Length(1), Length(1)],
        0.25,
        8,
    )
