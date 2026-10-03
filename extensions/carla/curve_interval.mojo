# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Outward Float64 arithmetic for bounded CARLA curve queries.

The arithmetic is separate from lane types, map APIs, and search budgets.
Each rounded elementary operation is widened by one representable value.
This encloses both its exact real result and its rounded scalar result,
including gradual underflow. Indeterminate extended-real operations return
the whole line. A caller must not turn that uncertainty into a certificate.

No transcendental error allowance is assumed in this module.
"""

from std.math import inf, isfinite, isnan, sqrt
from std.memory import bitcast


def _next_up(value: Float64) -> Float64:
    # Observe the rounded bits before any following arithmetic. Unlike an
    # epsilon multiplier, this also handles zero and subnormal results.
    if isnan(value) or value == inf[DType.float64]():
        return value
    if value == 0.0:
        return bitcast[DType.float64](UInt64(1))
    var bits = bitcast[DType.uint64](value)
    if value < 0.0:
        return bitcast[DType.float64](bits - 1)
    return bitcast[DType.float64](bits + 1)


def _next_down(value: Float64) -> Float64:
    return -_next_up(-value)


@fieldwise_init
struct _Interval(ImplicitlyCopyable):
    var low: Float64
    var high: Float64

    @staticmethod
    def point(value: Float64) -> Self:
        if isnan(value):
            return Self.whole()
        return Self(value, value)

    @staticmethod
    def whole() -> Self:
        return Self(-inf[DType.float64](), inf[DType.float64]())

    @staticmethod
    def rounded(low: Float64, high: Float64) -> Self:
        if isnan(low) or isnan(high):
            return Self.whole()
        return Self(_next_down(low), _next_up(high))

    def is_finite(self) -> Bool:
        return isfinite(self.low) and isfinite(self.high)

    def contains(self, value: Float64) -> Bool:
        return self.low <= value and value <= self.high

    def is_point(self, value: Float64) -> Bool:
        return self.low == value and self.high == value

    def magnitude(self) -> Float64:
        return max(abs(self.low), abs(self.high))

    def width(self) -> Float64:
        return _next_up(self.high - self.low)

    def hull(self, other: Self) -> Self:
        var low = min(self.low, other.low)
        var high = max(self.high, other.high)
        if low == 0.0 and high == 0.0:
            return Self(-0.0, 0.0)
        return Self(low, high)

    def __neg__(self) -> Self:
        return Self(-self.high, -self.low)

    def __add__(self, other: Self) -> Self:
        if self.is_point(0.0) and other.is_point(0.0):
            return Self(-0.0, 0.0)
        if self.is_point(0.0):
            return other
        if other.is_point(0.0):
            return self
        return Self.rounded(self.low + other.low, self.high + other.high)

    def __sub__(self, other: Self) -> Self:
        return self + (-other)

    def __mul__(self, other: Self) -> Self:
        if self.is_point(1.0):
            return other
        if other.is_point(1.0):
            return self
        if self.is_point(0.0) and other.is_finite():
            return Self(-0.0, 0.0)
        if other.is_point(0.0) and self.is_finite():
            return Self(-0.0, 0.0)
        var a = self.low * other.low
        var b = self.low * other.high
        var c = self.high * other.low
        var d = self.high * other.high
        if isnan(a) or isnan(b) or isnan(c) or isnan(d):
            return Self.whole()
        return Self.rounded(min(min(a, b), min(c, d)), max(max(a, b), max(c, d)))

    def __truediv__(self, other: Self) -> Self:
        if other.contains(0.0):
            return Self.whole()
        if other.is_point(1.0):
            return self
        if self.is_point(0.0) and other.is_finite():
            return Self(-0.0, 0.0)
        var a = self.low / other.low
        var b = self.low / other.high
        var c = self.high / other.low
        var d = self.high / other.high
        if isnan(a) or isnan(b) or isnan(c) or isnan(d):
            return Self.whole()
        return Self.rounded(min(min(a, b), min(c, d)), max(max(a, b), max(c, d)))

    def square(self) -> Self:
        if self.is_point(0.0):
            return Self.point(0.0)
        var a = self.low * self.low
        var b = self.high * self.high
        var low = max(0.0, _next_down(min(a, b)))
        if self.contains(0.0):
            low = 0.0
        return Self(low, _next_up(max(a, b)))

    def sqrt(self) -> Self:
        if self.low < 0.0:
            return Self.whole()
        if self.is_point(0.0):
            return self
        return Self(
            max(0.0, _next_down(sqrt(self.low))), _next_up(sqrt(self.high))
        )

    def absolute(self) -> Self:
        if self.contains(0.0):
            return Self(0.0, self.magnitude())
        return Self(min(abs(self.low), abs(self.high)), self.magnitude())

    def minimum(self, other: Self) -> Self:
        return Self(min(self.low, other.low), min(self.high, other.high))

    def maximum(self, other: Self) -> Self:
        return Self(max(self.low, other.low), max(self.high, other.high))


def _roundoff(magnitude: Float64) -> Float64:
    # For each finite Float64 operation, absolute rounding error is bounded
    # by u*|exact result| + eta/2. Use eta instead so the bound is itself
    # representable even at gradual underflow. This is not a query tolerance.
    comptime u = Float64(1.1102230246251565e-16)
    var eta = bitcast[DType.float64](UInt64(1))
    return _next_up(_next_up(u * magnitude) + eta)


@fieldwise_init
struct _Jet(ImplicitlyCopyable):
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
        var value = self.value + other.value
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
        var value = self.value * other.value
        var inherited = (
            _Interval.point(self.value.magnitude()) * _Interval.point(other.error)
            + _Interval.point(other.value.magnitude()) * _Interval.point(self.error)
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
        var value = self.value / other.value
        var denominator = other.value.absolute().low - other.error
        if denominator <= 0.0:
            return Self(
                _Interval.whole(),
                _Interval.whole(),
                _Interval.whole(),
                inf[DType.float64](),
            )
        var inherited = (
            (_Interval.point(self.error)
             + _Interval.point(value.magnitude()) * _Interval.point(other.error))
            / _Interval.point(_next_down(denominator))
        ).high
        var first = (self.first - value * other.first) / other.value
        var second = (
            self.second - value * other.second
            - _Interval.point(2.0) * first * other.first
        ) / other.value
        return Self(
            value,
            first,
            second,
            _next_up(inherited + _roundoff(_next_up(value.magnitude() + inherited))),
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
            _next_up(inherited + _roundoff(_next_up(value.magnitude() + inherited))),
        )
