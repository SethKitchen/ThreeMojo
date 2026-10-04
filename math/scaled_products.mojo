# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Finite product sums with explicit exponents for normalized directions.

Keep each product's exponent separate from its floating-point fraction.
Error-free product splits and TwoSum expansions retain small terms when
large terms cancel. The Float32 specialization is device-compatible.
"""

from std.math import fma, frexp, inf, isfinite, ldexp


@fieldwise_init
struct _Scaled[dtype: DType](ImplicitlyCopyable):
    """A finite floating-point fraction times an integer power of two."""

    var fraction: SIMD[Self.dtype, 1]
    var exponent: Int


def _split[
    dtype: DType
](value: SIMD[dtype, 1], exponent: Int = 0) -> _Scaled[dtype]:
    """Split a finite value, including pinned frexp's subnormal inputs."""
    comptime assert dtype.is_floating_point()
    comptime tiny = SIMD[dtype, 1](
        1.1754943508222875e-38
    ) if dtype == DType.float32 else SIMD[dtype, 1](2.2250738585072014e-308)
    comptime shift = 64 if dtype == DType.float32 else 512
    if value != 0 and abs(value) < tiny:
        var parts = frexp(value * ldexp(SIMD[dtype, 1](1), Int32(shift)))
        return _Scaled(parts[0], exponent + Int(parts[1]) - shift)
    var parts = frexp(value)
    return _Scaled(parts[0], exponent + Int(parts[1]))


def _two_sum[
    dtype: DType
](var a: _Scaled[dtype], var b: _Scaled[dtype]) -> Tuple[
    _Scaled[dtype], _Scaled[dtype]
]:
    """Return an exact sum as a rounded high term and a residual term."""
    comptime assert dtype.is_floating_point()
    if a.fraction == 0:
        return b, a
    if b.fraction == 0:
        return a, b
    if a.exponent < b.exponent:
        var held = a
        a = b
        b = held
    comptime precision = 24 if dtype == DType.float32 else 53
    var gap = a.exponent - b.exponent
    if gap > precision + 1:
        # The smaller number cannot change the larger rounded fraction.
        # Keep it as a tagged residual instead of underflowing it to zero.
        return a, b
    var small = b.fraction * ldexp(SIMD[dtype, 1](1), Int32(-gap))
    var total = a.fraction + small
    var virtual = total - a.fraction
    var error = (a.fraction - (total - virtual)) + (small - virtual)
    return _split(total, a.exponent), _split(error, a.exponent)


def _at_exponent[
    dtype: DType
](value: _Scaled[dtype], exponent: Int) -> SIMD[dtype, 1]:
    """Convert to a common exponent without forming an invalid power."""
    comptime assert dtype.is_floating_point()
    comptime lowest_power = -126 if dtype == DType.float32 else -1022
    comptime highest_power = 127 if dtype == DType.float32 else 1023
    comptime lowest_subnormal = -149 if dtype == DType.float32 else -1074
    var remaining = value.exponent - exponent
    if value.fraction == 0:
        return value.fraction
    if remaining < lowest_subnormal:
        return value.fraction * SIMD[dtype, 1](0)
    if remaining < lowest_power:
        # Keep the first product normal; round into subnormal only once.
        return (
            value.fraction
            * ldexp(SIMD[dtype, 1](1), Int32(remaining - lowest_power))
        ) * ldexp(SIMD[dtype, 1](1), Int32(lowest_power))
    if remaining > highest_power:
        if remaining > highest_power + 1:
            return value.fraction * inf[dtype]()
        return (value.fraction * 2) * ldexp(
            SIMD[dtype, 1](1), Int32(highest_power)
        )
    return value.fraction * ldexp(SIMD[dtype, 1](1), Int32(remaining))


def _sum_products[
    dtype: DType, terms: Int
](
    a: Array[SIMD[dtype, 1], terms],
    b: Array[SIMD[dtype, 1], terms],
    c: Array[SIMD[dtype, 1], terms],
) -> _Scaled[dtype]:
    """Return an exponent-tagged estimate of an exact finite product sum.

    Each term has three factors. A factor of one represents a two-factor
    product. Four exact pieces per product suffice for either precision.
    The final estimate has the exact nonzero sign before scalar rounding.
    """
    comptime assert dtype.is_floating_point()
    var expansion = Array[_Scaled[dtype], 4 * terms](fill=_Scaled[dtype](0, 0))
    var count = 0
    for term in range(terms):  # pragma: no branch
        var sa = _split(a[term])
        var sb = _split(b[term])
        var sc = _split(c[term])
        var exponent = sa.exponent + sb.exponent + sc.exponent
        var product = fma(sa.fraction, sb.fraction, SIMD[dtype, 1](0))
        var remainder = fma(sa.fraction, sb.fraction, -product)
        var high = fma(product, sc.fraction, SIMD[dtype, 1](0))
        var low = fma(product, sc.fraction, -high)
        var tail = fma(remainder, sc.fraction, SIMD[dtype, 1](0))
        var last = fma(remainder, sc.fraction, -tail)
        for piece in [last, tail, low, high]:  # pragma: no branch
            var total = _split(piece, exponent)
            var parts = Array[_Scaled[dtype], 4 * terms](
                fill=_Scaled[dtype](0, 0)
            )
            var part_count = 0
            for index in range(count):
                var sum = _two_sum(total, expansion[index])
                if sum[1].fraction != 0:
                    parts[part_count] = sum[1]
                    part_count += 1
                total = sum[0]
            if total.fraction != 0:
                parts[part_count] = total
                part_count += 1
            expansion = parts^
            count = part_count
    if count == 0:
        return _Scaled[dtype](0, 0)
    var exponent = expansion[count - 1].exponent
    var estimate = SIMD[dtype, 1](0)
    for index in range(count):  # pragma: no branch
        estimate += _at_exponent(expansion[index], exponent)
    return _split(estimate, exponent)


def _common_scale[
    dtype: DType, size: Int
](values: Array[_Scaled[dtype], size]) -> Array[SIMD[dtype, 1], size]:
    """Return proportional components with a representable common scale."""
    comptime assert dtype.is_floating_point()
    var exponent = -100000
    for index in range(size):  # pragma: no branch
        if values[index].fraction != 0:
            exponent = max(exponent, values[index].exponent)
    var result = Array[SIMD[dtype, 1], size](fill=0)
    if exponent == -100000:
        return result^
    for index in range(size):  # pragma: no branch
        result[index] = _at_exponent(values[index], exponent - 1)
    return result^


def _grow_sum[
    dtype: DType
](mut expansion: List[_Scaled[dtype]], value: _Scaled[dtype]):
    """Accumulate a tagged scalar in a host-side variable-length expansion."""
    comptime assert dtype.is_floating_point()
    if not isfinite(value.fraction):
        expansion.clear()
        expansion.append(value)
        return
    var parts = List[_Scaled[dtype]](capacity=len(expansion) + 1)
    var total = value
    for part in expansion:
        if not isfinite(part.fraction):
            return
        var sum = _two_sum(total, part)
        if sum[1].fraction != 0:
            parts.append(sum[1])
        total = sum[0]
    if total.fraction != 0:
        parts.append(total)
    expansion = parts^


def _estimate[dtype: DType](expansion: List[_Scaled[dtype]]) -> _Scaled[dtype]:
    """Estimate a host-side expansion without losing its exponent."""
    comptime assert dtype.is_floating_point()
    if len(expansion) == 0:
        return _Scaled[dtype](0, 0)
    var exponent = expansion[len(expansion) - 1].exponent - 1
    var result = SIMD[dtype, 1](0)
    for part in expansion:
        if not isfinite(part.fraction):
            return part
        result += _at_exponent(part, exponent)
    return _split(result, exponent)


def _grow_products[
    dtype: DType, terms: Int
](
    mut expansion: List[_Scaled[dtype]],
    a: Array[SIMD[dtype, 1], terms],
    b: Array[SIMD[dtype, 1], terms],
    c: Array[SIMD[dtype, 1], terms],
):
    """Keep all exact product pieces through a host-side outer sum."""
    comptime assert dtype.is_floating_point()
    for term in range(terms):  # pragma: no branch
        var sa = _split(a[term])
        var sb = _split(b[term])
        var sc = _split(c[term])
        var exponent = sa.exponent + sb.exponent + sc.exponent
        var product = fma(sa.fraction, sb.fraction, SIMD[dtype, 1](0))
        var remainder = fma(sa.fraction, sb.fraction, -product)
        var high = fma(product, sc.fraction, SIMD[dtype, 1](0))
        var low = fma(product, sc.fraction, -high)
        var tail = fma(remainder, sc.fraction, SIMD[dtype, 1](0))
        var last = fma(remainder, sc.fraction, -tail)
        for piece in [last, tail, low, high]:  # pragma: no branch
            _grow_sum(expansion, _split(piece, exponent))
