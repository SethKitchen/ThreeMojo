# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Outward Float64 arithmetic for bounded CARLA curve queries.

The arithmetic is separate from lane types, map APIs, and search budgets.
Potentially inexact elementary operations use adjacent representable bounds.
A proved normal power-of-two scaling can keep exact endpoints. These bounds
enclose both the exact real result and the rounded scalar result, including
gradual underflow. Indeterminate extended-real operations return
the whole line. A caller must not turn that uncertainty into a certificate.

No transcendental error allowance is assumed in this module.
"""

from std.math import fma, inf, isfinite, isnan, sqrt
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
        return Self.rounded(
            min(min(a, b), min(c, d)), max(max(a, b), max(c, d))
        )

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
        return Self.rounded(
            min(min(a, b), min(c, d)), max(max(a, b), max(c, d))
        )

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


def _binary_power(value: Float64) -> Bool:
    if not isfinite(value) or value == 0.0:
        return False
    var bits = bitcast[DType.uint64](value) & UInt64(0x7FFFFFFFFFFFFFFF)
    var exponent = bits & UInt64(0x7FF0000000000000)
    if exponent != 0:
        return (bits & UInt64(0x000FFFFFFFFFFFFF)) == 0
    return (bits & (bits - UInt64(1))) == 0


def _exact_scaled_endpoint(original: Float64, result: Float64) -> Bool:
    # Scaling is exact above the smallest normal result. Rounding from
    # below can produce that boundary normal, so equality is not proof.
    # Zero inputs are exact; boundary and subnormal results use the
    # ordinary outward path rather than assuming discarded bits were zero.
    return original == 0.0 or (
        isfinite(result) and abs(result) > 2.2250738585072014e-308
    )


def _power_product_bound(one: _Interval, two: _Interval) -> _Interval:
    var scale = Float64(0.0)
    var low = one.low
    var high = one.high
    if two.low == two.high and _binary_power(two.low):
        scale = two.low
    elif one.low == one.high and _binary_power(one.low):
        scale = one.low
        low = two.low
        high = two.high
    if scale != 0.0:
        var a = low * scale
        var b = high * scale
        if _exact_scaled_endpoint(low, a) and _exact_scaled_endpoint(high, b):
            if a == 0.0 and b == 0.0:
                return _Interval(-0.0, 0.0)
            return _Interval(min(a, b), max(a, b))
    return one * two


def _power_quotient_bound(one: _Interval, two: _Interval) -> _Interval:
    if two.low == two.high and _binary_power(two.low):
        var a = one.low / two.low
        var b = one.high / two.low
        if _exact_scaled_endpoint(one.low, a) and _exact_scaled_endpoint(
            one.high, b
        ):
            if a == 0.0 and b == 0.0:
                return _Interval(-0.0, 0.0)
            return _Interval(min(a, b), max(a, b))
    return one / two


def _endpoint_in_exact_range(value: Float64) -> Bool:
    # This is an arithmetic fast-path domain, not a map-coordinate limit.
    # Outside it the existing outward interval operation remains available.
    var magnitude = abs(value)
    return isfinite(value) and (
        value == 0.0
        or (
            magnitude >= bitcast[DType.float64](UInt64(0x26F0000000000000))
            and magnitude <= bitcast[DType.float64](UInt64(0x58F0000000000000))
        )
    )


def _residual_bracket(value: Float64, residual: Float64) -> _Interval:
    if residual > 0.0:
        return _Interval(value, _next_up(value))
    if residual < 0.0:
        return _Interval(_next_down(value), value)
    if value == 0.0:
        return _Interval(-0.0, 0.0)
    return _Interval.point(value)


def _directed_endpoint_sum(one: Float64, two: Float64) -> _Interval:
    if not (_endpoint_in_exact_range(one) and _endpoint_in_exact_range(two)):
        return _Interval.point(one) + _Interval.point(two)
    var value = one + two
    var second = value - one
    var first = value - second
    var residual = (one - first) + (two - second)
    return _residual_bracket(value, residual)


def _directed_endpoint_product(one: Float64, two: Float64) -> _Interval:
    if not (_endpoint_in_exact_range(one) and _endpoint_in_exact_range(two)):
        return _power_product_bound(_Interval.point(one), _Interval.point(two))
    var value = one * two
    var residual = fma(one, two, -value)
    return _residual_bracket(value, residual)


def _directed_endpoint_quotient(one: Float64, two: Float64) -> _Interval:
    if two == 0.0 or not (
        _endpoint_in_exact_range(one) and _endpoint_in_exact_range(two)
    ):
        return _power_quotient_bound(_Interval.point(one), _Interval.point(two))
    var value = one / two
    var residual = fma(-value, two, one)
    if two < 0.0:
        residual = -residual
    return _residual_bracket(value, residual)


def _tight_sum_bound(one: _Interval, two: _Interval) -> _Interval:
    var low = _directed_endpoint_sum(one.low, two.low)
    var high = _directed_endpoint_sum(one.high, two.high)
    return _Interval(low.low, high.high)


def _tight_product_bound(one: _Interval, two: _Interval) -> _Interval:
    return (
        _directed_endpoint_product(one.low, two.low)
        .hull(_directed_endpoint_product(one.low, two.high))
        .hull(_directed_endpoint_product(one.high, two.low))
        .hull(_directed_endpoint_product(one.high, two.high))
    )


def _tight_quotient_bound(one: _Interval, two: _Interval) -> _Interval:
    if two.contains(0.0):
        return _Interval.whole()
    return (
        _directed_endpoint_quotient(one.low, two.low)
        .hull(_directed_endpoint_quotient(one.low, two.high))
        .hull(_directed_endpoint_quotient(one.high, two.low))
        .hull(_directed_endpoint_quotient(one.high, two.high))
    )


def _tight_square_bound(value: _Interval) -> _Interval:
    var result = _directed_endpoint_product(value.low, value.low).hull(
        _directed_endpoint_product(value.high, value.high)
    )
    if value.contains(0.0):
        result.low = 0.0
    return result


def _roundoff(magnitude: Float64) -> Float64:
    # The caller encloses the exact pre-round magnitude, including inherited
    # input errors. The half-spacing in its binade bounds nearest rounding.
    # At a binade join this selects the larger spacing. Use eta instead of
    # the unrepresentable eta/2 at gradual underflow. Retain one outward ULP
    # in the returned allowance; this is not a geometric tolerance change.
    if not isfinite(magnitude) or magnitude < 0.0:
        return inf[DType.float64]()
    var exponent = Int(
        (bitcast[DType.uint64](magnitude) >> UInt64(52)) & UInt64(0x7FF)
    )
    if exponent <= 1:
        return _next_up(bitcast[DType.float64](UInt64(1)))
    if exponent < 54:
        return _next_up(
            bitcast[DType.float64](UInt64(1) << UInt64(exponent - 2))
        )
    return _next_up(bitcast[DType.float64](UInt64(exponent - 53) << UInt64(52)))


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
