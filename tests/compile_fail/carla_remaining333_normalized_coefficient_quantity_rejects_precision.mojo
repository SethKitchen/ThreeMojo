# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject precision input for a normalized cubic length coefficient."""

from extensions.carla.geometry import (
    LINE,
    ARC_LENGTH,
    NORMALIZED,
    RoadGeometry,
    NormalizedCubic,
    with_param_poly3,
    with_param_poly3_normalized,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.map_builder import MapBuilder
from units.si import Length, Length64, Angle64, InverseLength64, InverseArea64


def main() raises:
    _ = NormalizedCubic(Length64(0), Length64(10), Length(1), Length64(0))
