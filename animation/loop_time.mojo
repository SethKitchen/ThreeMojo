# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact clip-length quotients and phases from stored Float32 times.

The largest count marker exceeds every supported Int difference. A marker
never becomes an event count. Finite repetitions can finish before conversion.
"""

from std.math import isfinite
from std.memory import bitcast

comptime _COUNT_LIMIT = UInt128(1) << 65


def _positive_loop_time(n: Float32, length: Float32) -> Tuple[Int128, Float64]:
    """Split finite nonnegative `n` by positive finite `length`.

    Return a whole count and exact residual. Counts at or above 2**65
    return that marker and zero. There is no loop over time or exponent.
    """
    if n < length:
        return (0, Float64(n))
    var difference = Float64(n) - Float64(length)
    if difference < Float64(length):
        return (1, difference)
    var n_bits = bitcast[DType.uint32](n)
    var l_bits = bitcast[DType.uint32](length)
    var n_exponent = Int(n_bits >> 23)
    var l_exponent = Int(l_bits >> 23)
    var numerator = UInt128(n_bits & 0x7FFFFF)
    var divisor = UInt128(l_bits & 0x7FFFFF)
    if n_exponent != 0:
        numerator |= UInt128(1) << 23
    if l_exponent != 0:
        divisor |= UInt128(1) << 23
    n_exponent = max(n_exponent, 1)
    l_exponent = max(l_exponent, 1)
    var shift = n_exponent - l_exponent
    # A larger shift needs over 128 bits and its quotient exceeds 2**80.
    if shift > 103:
        return (Int128(_COUNT_LIMIT), 0)
    numerator <<= UInt128(shift)
    var quotient = numerator // divisor
    if quotient >= _COUNT_LIMIT:
        return (Int128(_COUNT_LIMIT), 0)
    var residual = numerator % divisor
    # The residual has at most 24 bits. Its quantum is a binary64 normal,
    # even when the original clip length is a binary32 subnormal.
    var quantum = bitcast[DType.float64](UInt64(l_exponent + 873) << 52)
    return (Int128(quotient), Float64(residual) * quantum)


def _split_loop_time(n: Float32, length: Float32) -> Tuple[Int128, Float64]:
    """Return the floor count and nonnegative residual of finite `n`."""
    var whole, residual = _positive_loop_time(abs(n), length)
    if n < 0:
        whole = -whole
        if residual != 0:
            whole -= 1
            residual = Float64(length) - residual
    return (whole, residual)


def _stored_loop_phase(
    whole: Int128,
    residual: Float64,
    length: Float32,
    ping_pong: Bool,
    wraps_first: Bool,
) raises -> Float32:
    """Round a reduced phase without rounding across its next leg boundary."""
    var second_leg = ping_pong and (whole % 2 != 0)
    if wraps_first:
        second_leg = not second_leg
    var lower = Float64(length) if second_leg else Float64(0)
    var upper = lower + Float64(length)
    var phase = Float32(lower + residual)
    if not isfinite(phase):
        raise Error("An action's reduced phase must fit Float32")
    if Float64(phase) >= upper:
        phase = bitcast[DType.float32](bitcast[DType.uint32](phase) - 1)
    # The exact-multiple path has no direction-dependent signed zero.
    if phase == 0:
        return 0
    return phase
