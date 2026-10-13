# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject precision input at the polynomial station quantity boundary."""

from extensions.carla.polynomial import CubicPolynomial
from units.si import (
    Length64,
    Angle64,
    InverseLength64,
    InverseArea64,
    Duration64,
    Length,
    Angle,
    InverseLength,
)
from units.quantity import Quantity


def main() raises:
    var profile = CubicPolynomial.constant(Length64(3.5))
    _ = profile.evaluate(Length(1))
