# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Frozen full-jet oracle from the restricted-seed source, 2026-10-03.

Only helper/type names change. Value/error/derivative statements below are
copied from the original three modules. The unchanged interval primitives
and stored trig/GL constants remain shared. See the isolated review for pins.
This file is test support, not production code.
"""

from extensions.carla.curve_interval import (
    _Interval,
    _next_up,
    _next_down,
    _roundoff,
    _tight_sum_bound,
    _tight_product_bound,
    _tight_quotient_bound,
)
from extensions.carla.curve_trig import (
    _PHASE_LIMIT,
    _INV_HALF_PI,
    _HALF_PI_HIGH,
    _HALF_PI_LOW,
    _SIN_COEFFICIENTS,
    _COS_COEFFICIENTS,
)
from extensions.carla.geometry import RoadGeometry, _GL_NODES, _GL_WEIGHTS
from math.vector3 import Vector3
from std.math import floor, inf, sqrt


@fieldwise_init
struct _FullJet(ImplicitlyCopyable):
    # The value and two derivatives enclose the exact real expression in
    # stored Float64 constants. `error` bounds scalar evaluation roundoff.
    # Keeping error separate permits a centered form without differentiating
    # the staircase created by rounded scalar arithmetic.
    var value: _Interval
    var first: _Interval
    var second: _Interval
    var error: Float64

    @staticmethod
    def constant(value: Float64) -> Self:
        var zero = _Interval.point(0.0)
        return Self(_Interval.point(value), zero, zero, 0.0)

    @staticmethod
    def variable(low: Float64, high: Float64) -> Self:
        return Self(
            _Interval(low, high),
            _Interval.point(1.0),
            _Interval.point(0.0),
            0.0,
        )

    def rounded_value(self) -> _Interval:
        if self.error == 0.0:
            return self.value
        return self.value + _Interval(-self.error, self.error)

    def __neg__(self) -> Self:
        return Self(-self.value, -self.first, -self.second, self.error)

    def __add__(self, other: Self) -> Self:
        if self.value.is_point(0.0) and self.error == 0.0:
            var value = other.value
            if other.value.is_point(0.0):
                value = _Interval(-0.0, 0.0)
            return Self(
                value,
                self.first + other.first,
                self.second + other.second,
                other.error,
            )
        if other.value.is_point(0.0) and other.error == 0.0:
            var value = self.value
            if self.value.is_point(0.0):
                value = _Interval(-0.0, 0.0)
            return Self(
                value,
                self.first + other.first,
                self.second + other.second,
                self.error,
            )
        var value = _tight_sum_bound(self.value, other.value)
        var inherited = _next_up(self.error + other.error)
        var magnitude = _next_up(value.magnitude() + inherited)
        return Self(
            value,
            self.first + other.first,
            self.second + other.second,
            _next_up(inherited + _roundoff(magnitude)),
        )

    def __sub__(self, other: Self) -> Self:
        return self + (-other)

    def __mul__(self, other: Self) -> Self:
        var value = _tight_product_bound(self.value, other.value)
        var inherited = (
            _Interval.point(self.value.magnitude())
            * _Interval.point(other.error)
            + _Interval.point(other.value.magnitude())
            * _Interval.point(self.error)
            + _Interval.point(self.error) * _Interval.point(other.error)
        ).high
        var magnitude = _next_up(value.magnitude() + inherited)
        var error = _next_up(inherited + _roundoff(magnitude))
        if self.value.is_point(0.0) and self.error == 0.0:
            if other.rounded_value().is_finite():
                error = 0.0
        elif other.value.is_point(0.0) and other.error == 0.0:
            if self.rounded_value().is_finite():
                error = 0.0
        elif self.value.is_point(1.0) and self.error == 0.0:
            error = other.error
        elif other.value.is_point(1.0) and other.error == 0.0:
            error = self.error
        return Self(
            value,
            self.first * other.value + self.value * other.first,
            self.second * other.value
            + _Interval.point(2.0) * self.first * other.first
            + self.value * other.second,
            error,
        )

    def __truediv__(self, other: Self) -> Self:
        var value = _tight_quotient_bound(self.value, other.value)
        var denominator = other.value.absolute().low - other.error
        if denominator <= 0.0:
            return Self(
                _Interval.whole(),
                _Interval.whole(),
                _Interval.whole(),
                inf[DType.float64](),
            )
        var inherited = (
            (
                _Interval.point(self.error)
                + _Interval.point(value.magnitude())
                * _Interval.point(other.error)
            )
            / _Interval.point(_next_down(denominator))
        ).high
        var first = (self.first - value * other.first) / other.value
        var second = (
            self.second
            - value * other.second
            - _Interval.point(2.0) * first * other.first
        ) / other.value
        return Self(
            value,
            first,
            second,
            _next_up(
                inherited + _roundoff(_next_up(value.magnitude() + inherited))
            ),
        )

    def sqrt(self) -> Self:
        var value = self.value.sqrt()
        if self.value.is_point(0.0) and self.error == 0.0:
            if self.first.is_point(0.0) and self.second.is_point(0.0):
                return Self.constant(0.0)
        var denominator = self.value.low - self.error
        if denominator <= 0.0:
            return Self(
                value,
                _Interval.whole(),
                _Interval.whole(),
                inf[DType.float64](),
            )
        var root_low = _next_down(sqrt(_next_down(denominator)))
        var inherited = (
            _Interval.point(self.error)
            / (_Interval.point(root_low) + _Interval.point(value.low))
        ).high
        var twice = _Interval.point(2.0) * value
        var first = self.first / twice
        var second = (
            self.second - _Interval.point(2.0) * first.square()
        ) / twice
        return Self(
            value,
            first,
            second,
            _next_up(
                inherited + _roundoff(_next_up(value.magnitude() + inherited))
            ),
        )


def _full_polynomial[
    n: Int
](coefficients: Array[Float64, n], x: _FullJet) -> _FullJet:
    var result = _FullJet.constant(coefficients[n - 1])
    var i = n - 2
    while i >= 0:
        result = result * x + _FullJet.constant(coefficients[i])
        i -= 1
    return result


def _full_sincos_branch(
    value: _FullJet, quadrant: Int
) -> Tuple[_FullJet, _FullJet]:
    # Products of constants are the same stored scalar values as the helper.
    # The derivative therefore includes only the variable subtraction and
    # the polynomial, not an ideal trigonometric identity.
    var high = Float64(quadrant) * _HALF_PI_HIGH
    var low = _FullJet.constant(Float64(quadrant)) * _FullJet.constant(
        _HALF_PI_LOW
    )
    var reduced = (value - _FullJet.constant(high)) - low
    var square = reduced * reduced
    var sine = reduced * _full_polynomial(
        materialize[_SIN_COEFFICIENTS](), square
    )
    var cosine = _full_polynomial(materialize[_COS_COEFFICIENTS](), square)
    var mode = quadrant & 3
    if mode == 0:
        return (sine, cosine)
    if mode == 1:
        return (cosine, -sine)
    if mode == 2:
        return (-sine, -cosine)
    return (-cosine, sine)


def _full_uncertain(value: _Interval) -> _FullJet:
    return _FullJet(value, _Interval.whole(), _Interval.whole(), 0.0)


def _full_sincos_jet(value: _FullJet) -> Tuple[_FullJet, _FullJet]:
    var domain = value.rounded_value()
    if not domain.is_finite():
        return (
            _full_uncertain(_Interval.whole()),
            _full_uncertain(_Interval.whole()),
        )
    if domain.magnitude() > _PHASE_LIMIT:
        if domain.low > _PHASE_LIMIT or domain.high < -_PHASE_LIMIT:
            var unknown = _full_uncertain(_Interval(-1.0, 1.0))
            return (unknown, unknown)
        return (
            _full_uncertain(_Interval.whole()),
            _full_uncertain(_Interval.whole()),
        )
    var selection = (
        value * _FullJet.constant(_INV_HALF_PI) + _FullJet.constant(0.5)
    ).rounded_value()
    var low = Int(floor(selection.low))
    var high = Int(floor(selection.high))
    if low == high:
        return _full_sincos_branch(value, low)
    if high - low > 4:
        # Polynomial output differs from exact [-1,1] by its arithmetic.
        # Evaluate possible branches only after further domain subdivision.
        return (
            _full_uncertain(_Interval.whole()),
            _full_uncertain(_Interval.whole()),
        )
    var source = _FullJet.variable(domain.low, domain.high)
    var result = _full_sincos_branch(source, low)
    var sine = result[0].rounded_value()
    var cosine = result[1].rounded_value()
    var quadrant = low + 1
    while quadrant <= high:
        var piece = _full_sincos_branch(source, quadrant)
        sine = sine.hull(piece[0].rounded_value())
        cosine = cosine.hull(piece[1].rounded_value())
        quadrant += 1
    # Quadrant changes are real branches in the scalar polynomial. No
    # smooth derivative is asserted across their rounded join.
    return (_full_uncertain(sine), _full_uncertain(cosine))


def _full_spiral_jet(
    geometry: RoadGeometry, d: _FullJet, pieces: Int, translation: Vector3
) -> Tuple[_FullJet, _FullJet, _FullJet]:
    var k0 = _FullJet.constant(geometry.curvature_start)
    var rate = _FullJet.constant(
        (geometry.curvature_end - geometry.curvature_start) / geometry.length
    )
    var step = d / _FullJet.constant(Float64(pieces))
    var nodes = materialize[_GL_NODES]()
    var weights = materialize[_GL_WEIGHTS]()
    var x = _FullJet.constant(0.0)
    var y = _FullJet.constant(0.0)
    var piece = 0
    while piece < pieces:
        var start = step * _FullJet.constant(Float64(piece))
        var i = 0
        while i < 5:
            var t = start + step * _FullJet.constant(0.5) * _FullJet.constant(
                1.0 + nodes[i]
            )
            var theta = _FullJet.constant(geometry.heading) + t * (
                k0 + _FullJet.constant(0.5) * rate * t
            )
            var trig = _full_sincos_jet(theta)
            x = (
                x
                + step
                * _FullJet.constant(0.5)
                * _FullJet.constant(weights[i])
                * trig[1]
            )
            y = (
                y
                + step
                * _FullJet.constant(0.5)
                * _FullJet.constant(weights[i])
                * trig[0]
            )
            i += 1
        piece += 1
    var heading = _FullJet.constant(geometry.heading) + d * (
        k0 + _FullJet.constant(0.5) * rate * d
    )
    return (
        (
            _FullJet.constant(geometry.x)
            - _FullJet.constant(Float64(translation.x))
        )
        + x,
        (
            _FullJet.constant(geometry.y)
            + _FullJet.constant(Float64(translation.y))
        )
        + y,
        heading,
    )


def _full_union_points(
    one: Tuple[_FullJet, _FullJet, _FullJet],
    two: Tuple[_FullJet, _FullJet, _FullJet],
) -> Tuple[_FullJet, _FullJet, _FullJet]:
    return (
        _full_uncertain(one[0].rounded_value().hull(two[0].rounded_value())),
        _full_uncertain(one[1].rounded_value().hull(two[1].rounded_value())),
        _full_uncertain(one[2].rounded_value().hull(two[2].rounded_value())),
    )
