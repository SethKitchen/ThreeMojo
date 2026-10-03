# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact binary remainder without a floating-point quotient or host library.

The finite path reduces integer significands. It uses at most 205 shifts
of ten bits for binary64, and no floating-point remainder instruction.
CPU controls verify the result. Device execution needs a hardware review.
"""

from std.math import isfinite
from std.memory import bitcast


def remainder_float64(n: Float64, m: Float64) -> Float64:
    """Return the exact truncating remainder of two binary64 operands.

    Args:
        n: The dividend.
        m: The divisor. Its sign does not affect the magnitude.

    Returns:
        For finite operands and nonzero `m`, the exact remainder with the
        sign of `n`, including signed zero. A finite dividend and infinite
        divisor return `n`. Zero divisors, infinite dividends, and NaN
        operands return NaN. NaN payloads are not preserved.
    """
    if not isfinite(n) or m != m or m == 0:
        return bitcast[DType.float64](UInt64(0x7FF8000000000000))
    var a = abs(n)
    var b = abs(m)
    if a < b:
        return n
    # This subtraction is exact when the ratio is in [1, 2]. A rounded
    # difference for a larger ratio cannot fall below representable b.
    var result = a - b
    if result >= b:
        var a_bits = bitcast[DType.uint64](a)
        var b_bits = bitcast[DType.uint64](b)
        var a_exponent = Int(a_bits >> 52)
        var b_exponent = Int(b_bits >> 52)
        var numerator = a_bits & 0xFFFFFFFFFFFFF
        var divisor = b_bits & 0xFFFFFFFFFFFFF
        if a_exponent != 0:
            numerator |= 0x10000000000000
        if b_exponent != 0:
            divisor |= 0x10000000000000
        # A subnormal has the same quantum as exponent field one, with
        # no implicit leading bit. Since a >= b, the shift is nonnegative.
        a_exponent = max(a_exponent, 1)
        b_exponent = max(b_exponent, 1)
        var shift = a_exponent - b_exponent
        var residual = numerator % divisor
        while shift > 0 and residual != 0:
            var step = min(shift, 10)
            # residual < divisor < 2^53, so a ten-bit shift fits UInt64.
            residual = (residual << UInt64(step)) % divisor
            shift -= step
        # The exact remainder fits binary64, including its subnormal
        # lattice. Both scale factors are powers of two. Scaling down
        # before scaling up avoids an overflowing intermediate product.
        result = (Float64(residual) * Float64(2.220446049250313e-16)) * (
            bitcast[DType.float64](UInt64(b_exponent) << 52)
        )
    if n < 0:
        return -result
    return result
