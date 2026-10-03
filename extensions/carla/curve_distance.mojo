# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Scale-safe distance predicates on stored finite Float64 center points.

An outward interval fast path uses one common positive scale. Ambiguous
comparisons use bounded exact binary products, not an epsilon or a rounded
square. This is point-distance arithmetic, not a global curve certificate.
"""

from extensions.carla.curve_interval import _Interval
from std.math import inf, isfinite
from std.memory import bitcast

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
) -> _Interval:
    comptime assert axes >= 1 and axes <= 3
    var result = _Interval.point(0.0)
    var axis = 0
    while axis < axes:
        var gap = _Interval.point(0.0)
        if point[axis] != query[axis]:
            gap = _Interval.point(point[axis]) - _Interval.point(query[axis])
        var normalized = gap / _Interval.point(scale)
        result = result + normalized.square()
        axis += 1
    return _Interval(max(0.0, result.low), max(0.0, result.high))


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


@no_inline
def _exact_plan_width(
    center: Array[Float64, 3], query: Array[Float64, 3], width: Float64
) -> Int:
    # Sign of 4*((cx-qx)^2+(cy-qy)^2)-width^2. Multiplication by four
    # avoids forming a half-width that can underflow for positive widths.
    var positive = Array[UInt64, _WORDS](fill=0)
    var negative = Array[UInt64, _WORDS](fill=0)
    var axis = 0
    while axis < 2:
        _signed_product(
            positive, negative, center[axis], center[axis], 2, False
        )
        _signed_product(positive, negative, center[axis], query[axis], 3, True)
        _signed_product(positive, negative, query[axis], query[axis], 2, False)
        axis += 1
    _signed_product(positive, negative, width, width, 0, True)
    return _exact_sign(positive, negative)


def _wide_plan_contains(
    center: Array[Float64, 3], query: Array[Float64, 3], width: Float64
) raises -> Bool:
    """Apply the strict plan half-width test without narrowing or squaring loss.
    """
    _finite_point(center)
    _finite_point(query)
    if not isfinite(width):
        raise Error("Lane distance comparison needs a finite width")
    if width <= 0.0:
        return False
    var scale = width
    var axis = 0
    while axis < 2:
        scale = max(scale, abs(center[axis] - query[axis]))
        axis += 1
    if isfinite(scale):
        var distance = _normalized_square[2](center, query, scale)
        var diameter = _Interval.point(width) / _Interval.point(scale)
        var difference = _Interval.point(4.0) * distance - diameter.square()
        if difference.high < 0.0:
            return True
        if difference.low >= 0.0:
            return False
    return _exact_plan_width(center, query, width) < 0


def _wide_distance_upper(
    point: Array[Float64, 3], query: Array[Float64, 3]
) raises -> Float64:
    """Bound a stored-point distance without an unscaled squared norm."""
    _finite_point(point)
    _finite_point(query)
    var scale = Float64(0)
    var axis = 0
    while axis < 3:
        scale = max(scale, abs(point[axis] - query[axis]))
        axis += 1
    if scale == 0.0:
        return 0.0
    if not isfinite(scale):
        return inf[DType.float64]()
    var norm = _normalized_square[3](point, query, scale).sqrt()
    return (_Interval.point(scale) * norm).high


def _point_gap_scale(
    point: Array[Float64, 3], query: Array[Float64, 3]
) raises -> Float64:
    # Zero means componentwise coincidence. No square is evaluated here.
    _finite_point(point)
    _finite_point(query)
    var gap = Float64(0)
    var magnitude = Float64(0)
    var axis = 0
    while axis < 3:
        gap = max(gap, abs(point[axis] - query[axis]))
        magnitude = max(magnitude, max(abs(point[axis]), abs(query[axis])))
        axis += 1
    if not isfinite(gap):
        gap = magnitude
    if gap == 0.0:
        return 0.0
    # A power-of-two scale preserves squared-distance ULP units wherever the
    # original square is normal. For subnormals it gives a tighter unit.
    var bits = bitcast[DType.uint64](gap)
    var exponent = bits & UInt64(0x7FF0000000000000)
    if exponent != 0:
        return bitcast[DType.float64](exponent)
    while (bits & (bits - UInt64(1))) != 0:
        bits = bits & (bits - UInt64(1))
    return bitcast[DType.float64](bits)
