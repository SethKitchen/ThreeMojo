# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Scale-safe distance predicates on stored finite Float64 center points.

An outward interval fast path uses one common positive scale. Ambiguous
comparisons use bounded exact binary products, not an epsilon or a rounded
square. This is point-distance arithmetic, not a global curve certificate.
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
struct _DistanceInterval(ImplicitlyCopyable):
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


comptime _WORDS = 132
comptime _MASK = UInt64(0xFFFFFFFF)
comptime _ORIGIN = 2148


def _finite_point(point: Array[Float64, 3]) raises:
    var axis = 0
    while axis < 3:
        if not isfinite(point[axis]):
            raise Error("Lane distance comparison needs finite coordinates")
        axis += 1


def _binary_parts(value: Float64) -> Tuple[UInt64, Int, Bool]:
    # value = (-1)^sign * significand * 2^exponent. The caller checks
    # finiteness before this extraction; zero has a zero significand.
    var bits = bitcast[DType.uint64](value)
    var significand = bits & UInt64(0x000FFFFFFFFFFFFF)
    var biased = Int((bits >> UInt64(52)) & UInt64(0x7FF))
    var exponent = -1074
    if biased != 0:
        significand = significand | UInt64(0x0010000000000000)
        exponent = biased - 1075
    return (significand, exponent, (bits >> UInt64(63)) != 0)


def _significand_product(a: UInt64, b: UInt64) -> Array[UInt64, 4]:
    # Each significand has at most 53 bits. Split it before multiplication:
    # every individual product and carry sum fits UInt64 without wrapping.
    var a0 = a & _MASK
    var a1 = a >> UInt64(32)
    var b0 = b & _MASK
    var b1 = b >> UInt64(32)
    var p0 = a0 * b0
    var p1 = a0 * b1
    var p2 = a1 * b0
    var p3 = a1 * b1
    var middle = (p0 >> UInt64(32)) + (p1 & _MASK) + (p2 & _MASK)
    var high = p3 + (p1 >> UInt64(32)) + (p2 >> UInt64(32))
    high += middle >> UInt64(32)
    return [p0 & _MASK, middle & _MASK, high & _MASK, high >> UInt64(32)]


def _accumulate(
    mut words: Array[UInt64, _WORDS],
    product: Array[UInt64, 4],
    bit_position: Int,
):
    var index = bit_position // 32
    var shift = UInt64(bit_position % 32)
    var carry = UInt64(0)
    var part = 0
    while part < 4:
        var total = words[index] + (product[part] << shift) + carry
        words[index] = total & _MASK
        carry = total >> UInt64(32)
        index += 1
        part += 1
    while carry != 0:
        var total = words[index] + carry
        words[index] = total & _MASK
        carry = total >> UInt64(32)
        index += 1


def _signed_product(
    mut positive: Array[UInt64, _WORDS],
    mut negative: Array[UInt64, _WORDS],
    a: Float64,
    b: Float64,
    coefficient_shift: Int,
    negate: Bool,
):
    var one = _binary_parts(a)
    var two = _binary_parts(b)
    if one[0] == 0 or two[0] == 0:
        return
    var product = _significand_product(one[0], two[0])
    var position = one[1] + two[1] + coefficient_shift + _ORIGIN
    var sign = (one[2] != two[2]) != negate
    if sign:
        _accumulate(negative, product, position)
    else:
        _accumulate(positive, product, position)


def _exact_sign(
    positive: Array[UInt64, _WORDS], negative: Array[UInt64, _WORDS]
) -> Int:
    var index = _WORDS
    while index > 0:
        index -= 1
        if positive[index] != negative[index]:
            if positive[index] > negative[index]:
                return 1
            return -1
    return 0


def _normalized_square[
    axes: Int
](
    point: Array[Float64, 3], query: Array[Float64, 3], scale: Float64
) -> _DistanceInterval:
    comptime assert axes >= 1 and axes <= 3
    var result = _DistanceInterval.point(0.0)
    var axis = 0
    while axis < axes:
        var gap = _DistanceInterval.point(0.0)
        if point[axis] != query[axis]:
            gap = _DistanceInterval.point(
                point[axis]
            ) - _DistanceInterval.point(query[axis])
        var normalized = gap / _DistanceInterval.point(scale)
        result = result + normalized.square()
        axis += 1
    return _DistanceInterval(max(0.0, result.low), max(0.0, result.high))


@no_inline
def _exact_point_order(
    a: Array[Float64, 3], b: Array[Float64, 3], query: Array[Float64, 3]
) -> Int:
    # The common query-square terms cancel symbolically. For each axis:
    # (a-q)^2-(b-q)^2 = a^2-b^2-2*a*q+2*b*q.
    var positive = Array[UInt64, _WORDS](fill=0)
    var negative = Array[UInt64, _WORDS](fill=0)
    var axis = 0
    while axis < 3:
        _signed_product(positive, negative, a[axis], a[axis], 0, False)
        _signed_product(positive, negative, b[axis], b[axis], 0, True)
        _signed_product(positive, negative, a[axis], query[axis], 1, True)
        _signed_product(positive, negative, b[axis], query[axis], 1, False)
        axis += 1
    return _exact_sign(positive, negative)


def _wide_point_order(
    a: Array[Float64, 3], b: Array[Float64, 3], query: Array[Float64, 3]
) raises -> Int:
    """Return the exact order of squared distances for stored finite points.

    Negative means a is closer, positive means b is closer, and zero is
    exact equality. No zero-square or epsilon tie substitutes for equality.
    """
    _finite_point(a)
    _finite_point(b)
    _finite_point(query)
    var scale = Float64(0)
    var axis = 0
    while axis < 3:
        scale = max(
            scale, max(abs(a[axis] - query[axis]), abs(b[axis] - query[axis]))
        )
        axis += 1
    if scale == 0.0:
        return 0
    if isfinite(scale):
        var one = _normalized_square[3](a, query, scale)
        var two = _normalized_square[3](b, query, scale)
        if one.high < two.low:
            return -1
        if two.high < one.low:
            return 1
    return _exact_point_order(a, b, query)


def _distance_overflow_result(
    point: Array[Float64, 3], query: Array[Float64, 3]
) raises -> Float64:
    # The scaled norm can round above the finite limit even when the exact
    # norm is in range. Reuse the bounded product kernel to check that edge.
    # All inputs are finite before this private helper is called.
    var positive = Array[UInt64, _WORDS](fill=0)
    var negative = Array[UInt64, _WORDS](fill=0)
    var axis = 0
    while axis < 3:
        _signed_product(positive, negative, point[axis], point[axis], 0, False)
        _signed_product(positive, negative, query[axis], query[axis], 0, False)
        _signed_product(positive, negative, point[axis], query[axis], 1, True)
        axis += 1
    var limit = Float64(1.7976931348623157e308)
    _signed_product(positive, negative, limit, limit, 0, True)
    if _exact_sign(positive, negative) > 0:
        raise Error("Lane distance exceeds the finite Float64 range")
    return limit


def _wide_distance(
    point: Array[Float64, 3], query: Array[Float64, 3]
) raises -> Float64:
    """Approximate the stored-point norm without a false zero or overflow.

    Selection must use _wide_point_order instead of this rounded output.
    """
    _finite_point(point)
    _finite_point(query)
    var gaps = Array[Float64, 3](fill=0.0)
    var scale = Float64(0)
    var axis = 0
    while axis < 3:
        gaps[axis] = abs(point[axis] - query[axis])
        scale = max(scale, gaps[axis])
        axis += 1
    if scale == 0.0:
        return 0.0
    if not isfinite(scale):
        return _distance_overflow_result(point, query)
    # A finite reconstruction can round to the maximum even when the exact
    # norm exceeds it. Below half the maximum, three components cannot do
    # that; above it, check the exact norm before returning a finite value.
    if scale > Float64(1.7976931348623157e308) * 0.5:
        _ = _distance_overflow_result(point, query)
    var sum = Float64(0)
    axis = 0
    while axis < 3:
        var part = gaps[axis] / scale
        sum += part * part
        axis += 1
    var distance = scale * sqrt(sum)
    if not isfinite(distance):
        return _distance_overflow_result(point, query)
    return distance
