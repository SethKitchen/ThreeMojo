# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's `geom::CubicPolynomial`: f(x) = a + b x + c x^2 + d x^3.

OpenDRIVE writes lane widths, elevations and lane offsets as cubics in a
distance ds from the start of their record. CARLA shifts each one to the
road's own s, so a caller evaluates every record at the same s. The
coefficients carry mixed units: a is in meters, b has none, c is per
meter and d is per square meter. They stay plain numbers for that reason.
"""


struct CubicPolynomial(ImplicitlyCopyable):
    """A cubic in s, shifted so that it reads the road's s directly."""

    var a: Float64
    var b: Float64
    var c: Float64
    var d: Float64
    # The s where the record starts, in meters.
    var s: Float64

    def __init__(
        out self, a: Float64, b: Float64, c: Float64, d: Float64, s: Float64
    ):
        """Create the cubic of a record that starts at `s`.

        The coefficients are re-expanded about zero, as CARLA does, so
        `evaluate(x)` equals the record's cubic at `x - s`.

        Args:
            a: The constant term, in meters.
            b: The linear term.
            c: The quadratic term, per meter.
            d: The cubic term, per square meter.
            s: Where the record starts along the road, in meters.
        """
        self.a = a - b * s + c * s * s - d * s * s * s
        self.b = b - 2 * c * s + 3 * d * s * s
        self.c = c - 3 * d * s
        self.d = d
        self.s = s

    @staticmethod
    def constant(value: Float64) -> CubicPolynomial:
        """Return a cubic that is `value` everywhere.

        Args:
            value: The constant, in meters.

        Returns:
            A cubic with a = value and every other term zero.
        """
        return CubicPolynomial(value, 0, 0, 0, 0)

    def evaluate(self, x: Float64) -> Float64:
        """Return f(x), `CubicPolynomial::Evaluate`.

        Args:
            x: The road's s, in meters.

        Returns:
            The value of the cubic.
        """
        return self.a + x * (self.b + x * (self.c + x * self.d))

    def tangent(self, x: Float64) -> Float64:
        """Return df/dx, `CubicPolynomial::Tangent`.

        Args:
            x: The road's s, in meters.

        Returns:
            The slope of the cubic.
        """
        return self.b + x * (2 * self.c + x * 3 * self.d)
