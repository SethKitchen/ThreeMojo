# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject precision input at the stride velocity quantity boundary."""

from extensions.carla.render_actors import stride
from units.si import (
    Length64,
    Length,
    Duration,
    Duration64,
    Velocity,
    Velocity64,
)


def main() raises:
    _ = stride(Velocity64(1))
