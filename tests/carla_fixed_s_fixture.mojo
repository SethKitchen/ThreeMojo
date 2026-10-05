# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Geometry fixtures shared by the fixed-s capture and its independent oracle."""

from extensions.carla.geometry import (
    ARC_LENGTH,
    RoadGeometry,
    RoadGeometryKind,
    with_arc,
    with_param_poly3,
    with_poly3,
    with_spiral,
)
from extensions.carla.polynomial import CubicPolynomial


def _fixed_geometry(
    kind: Int, origin: Float64, heading: Float64
) raises -> RoadGeometry:
    var base = RoadGeometry(
        RoadGeometryKind(kind), 0.0, origin, 7.0 - origin, heading, 10.0
    )
    if kind == 1:
        return with_arc(base^, 0.125)
    if kind == 2:
        return with_spiral(base^, -0.05, 0.15)
    if kind == 3:
        return with_poly3(base^, 0.25, 0.125, -0.01, 0.002)
    if kind == 4:
        return with_param_poly3(
            base^,
            CubicPolynomial(0, 1, 0.01, 0, 0),
            CubicPolynomial(0.25, -0.125, 0.01, 0.001, 0),
            ARC_LENGTH,
        )
    return base^
