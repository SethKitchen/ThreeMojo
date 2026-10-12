# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's `geom::CubicPolynomial`: f(x) = a + b x + c x^2 + d x^3.

OpenDRIVE writes lane widths, elevations and lane offsets as cubics in a
distance ds from the start of their record. The record retains its local coefficients and subtracts the record start
before Horner evaluation. This avoids cancellation at a large road station.
The coefficients carry mixed units: a is in meters, b has none, c is per
meter and d is per square meter. They stay plain numbers for that reason.
"""


from extensions.carla.quantity_boundary import _RAW_SI, _RawSI, _finite_si
from units.si import Length64, InverseLength64, InverseArea64


struct CubicPolynomial(ImplicitlyCopyable):
    """A local cubic evaluated at a road station or an explicit parameter."""

    var a: Float64
    var b: Float64
    var c: Float64
    var d: Float64
    # The s where the record starts, in meters.
    var s: Float64

    def __init__(
        out self,
        raw: _RawSI,
        a: Float64,
        b: Float64,
        c: Float64,
        d: Float64,
        s: Float64,
    ):
        """Create the cubic of a record that starts at `s`.

        The original coefficients are stored unchanged. Unlike CARLA
        1360bb9, evaluation forms the local coordinate `x - s` first.
        This is a numerical correction, not bit-identical legacy behavior.

        Args:
            raw: The private raw-storage construction capability.
            a: The constant term, in meters.
            b: The linear term.
            c: The quadratic term, per meter.
            d: The cubic term, per square meter.
            s: Where the record starts along the road, in meters."""
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.s = s

    def __init__(
        out self,
        a: Length64,
        b: Float64,
        c: InverseLength64,
        d: InverseArea64,
        s: Length64,
    ) raises:
        """Create a local distance profile with typed Float64 coefficients.

        Args:
            a: The value at the record start.
            b: The dimensionless slope.
            c: The quadratic coefficient, per meter.
            d: The cubic coefficient, per square meter.
            s: The record start in meters.

        Returns:
            A profile that retains the original coefficients.

        Raises:
            Error: If a coefficient or the record start is not finite.
        """
        self = CubicPolynomial.from_coefficients(
            a.value, b, c.value, d.value, s.value
        )

    @staticmethod
    def from_coefficients(
        a: Float64,
        b: Float64,
        c: Float64,
        d: Float64,
        s: Float64,
    ) raises -> CubicPolynomial:
        """Read explicit raw local coefficients from a format or parameter model.

        This adapter keeps the source numbers unchanged. For a road-distance
        profile their units are meters, one, per meter, per square meter,
        and meters. A normalized paramPoly3 uses its declared parameter units.

        Args:
            a: The local constant coefficient.
            b: The local linear coefficient.
            c: The local quadratic coefficient.
            d: The local cubic coefficient.
            s: The independent parameter origin.

        Returns:
            The unchanged finite coefficients and origin.

        Raises:
            Error: If any source value is not finite.
        """
        return CubicPolynomial(
            _RAW_SI,
            _finite_si(a),
            _finite_si(b),
            _finite_si(c),
            _finite_si(d),
            _finite_si(s),
        )

    @staticmethod
    def constant(value: Length64) raises -> CubicPolynomial:
        """Create a constant typed distance profile.

        Args:
            value: Its finite length.

        Returns:
            A constant profile.

        Raises:
            Error: If the value is not finite.
        """
        return CubicPolynomial.constant_si(value.value)

    def evaluate(self, x: Length64) raises -> Length64:
        """Evaluate a distance profile without losing Float64 precision.

        Args:
            x: The road station.

        Returns:
            The finite profile value in meters.

        Raises:
            Error: If the input, stored coefficients, or result is not finite.
        """
        return Length64(self.evaluate_meters(x.value))

    def tangent(self, x: Length64) raises -> Float64:
        """Return the dimensionless slope of a distance profile.

        Args:
            x: The road station.

        Returns:
            The finite slope in meters per meter.

        Raises:
            Error: If the input, stored coefficients, or result is not finite.
        """
        return self.tangent_meters(x.value)

    @staticmethod
    def constant_si(value: Float64) raises -> CubicPolynomial:
        """Return a cubic that is `value` everywhere.

        Args:
            value: The constant, in meters.

        Returns:
            A cubic with a = value and every other term zero.

        Raises:
            Error: If the constant value is nonfinite.
        """
        return CubicPolynomial.from_coefficients(value, 0, 0, 0, 0)

    def evaluate_meters(self, x: Float64) raises -> Float64:
        """Return f(x), `CubicPolynomial::Evaluate`.

        Args:
            x: The road's s, in meters.

        Returns:
            The value of the cubic.

        Raises:
            Error: If the station, origin, any coefficient, or the evaluated
                result is nonfinite.
        """
        _ = _finite_si(self.a)
        _ = _finite_si(self.b)
        _ = _finite_si(self.c)
        _ = _finite_si(self.d)
        _ = _finite_si(x)
        _ = _finite_si(self.s)
        return _finite_si(self._evaluate_si(x))

    def tangent_meters(self, x: Float64) raises -> Float64:
        """Return df/dx, `CubicPolynomial::Tangent`.

        Args:
            x: The road's s, in meters.

        Returns:
            The slope of the cubic.

        Raises:
            Error: If the station, origin, any coefficient, or the computed
                slope is nonfinite.
        """
        _ = _finite_si(self.a)
        _ = _finite_si(self.b)
        _ = _finite_si(self.c)
        _ = _finite_si(self.d)
        _ = _finite_si(x)
        _ = _finite_si(self.s)
        return _finite_si(self._tangent_si(x))

    def _evaluate_si(self, x: Float64) -> Float64:
        var local = x - self.s
        return self.a + local * (self.b + local * (self.c + local * self.d))

    def _tangent_si(self, x: Float64) -> Float64:
        var local = x - self.s
        return self.b + local * (2 * self.c + local * 3 * self.d)

    def a_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw a compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_finite_si(self.a))

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_finite_si(self.s))

    def c_quantity(self) raises -> InverseLength64:
        """Read the checked typed view of the raw c compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return InverseLength64(_finite_si(self.c))

    def d_quantity(self) raises -> InverseArea64:
        """Read the checked typed view of the raw d compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return InverseArea64(_finite_si(self.d))

    @staticmethod
    def _from_coefficients(
        a: Float64, b: Float64, c: Float64, d: Float64, s: Float64
    ) -> CubicPolynomial:
        return CubicPolynomial(_RAW_SI, a, b, c, d, s)

    @staticmethod
    def _constant_si(value: Float64) -> CubicPolynomial:
        return CubicPolynomial(_RAW_SI, value, 0.0, 0.0, 0.0, 0.0)
