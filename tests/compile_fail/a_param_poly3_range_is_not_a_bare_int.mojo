# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A paramPoly3 range must be a `ParamPoly3Range`, not a bare integer."""

from extensions.carla.geometry import param_poly3
from extensions.carla.polynomial import CubicPolynomial
from units.si import Angle, Length, METER, RADIAN


def main() raises:
    var g = param_poly3(
        Length(0.0, METER),
        Length(0.0, METER),
        Length(0.0, METER),
        Angle(0.0, RADIAN),
        Length(1.0, METER),
        CubicPolynomial(0, 1, 0, 0, 0),
        CubicPolynomial(0, 0, 0, 0, 0),
        0,
    )
    print(g.length)
