# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject precision input at the body size quantity boundary."""

from extensions.carla.render_actors import body_geometry, SEDAN
from units.si import (
    Length64,
    Length,
    Duration,
    Duration64,
    Velocity,
    Velocity64,
)


def main() raises:
    _ = body_geometry(Length64(1), Length(2), Length(1.5), SEDAN)
