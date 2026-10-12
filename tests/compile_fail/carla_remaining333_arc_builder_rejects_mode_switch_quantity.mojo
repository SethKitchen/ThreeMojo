# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Keep normalized and arc-length coefficient units distinct."""

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
    var builder = MapBuilder()
    var p = CubicPolynomial.from_coefficients(0, 1, 0, 0, 0)
    builder.add_road_geometry_param_poly3(
        0,
        Length64(0),
        Length64(0),
        Length64(0),
        Angle64(0),
        Length64(10),
        p,
        p,
        "normalized",
    )
