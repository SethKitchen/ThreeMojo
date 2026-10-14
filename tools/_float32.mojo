# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Float32 products that round once, as numpy's float32 arithmetic does.

A ported numpy reference must round each Float32 operation separately. A
plain Float32 multiply can be fused with the next sum into one rounding,
and the compiler can turn a narrowed Float64 product back into a Float32
multiply. So `mul` forms the product in Float64, where two Float32 values
multiply exactly, and `round32` rounds it to Float32 with integer
operations. The compiler cannot see through them.
"""

from std.memory import bitcast


def round32(value: Float64) -> Float32:
    """Round a double to the nearest Float32, ties to even, with integer
    operations, so the compiler cannot see a narrowing to undo.

    Args:
        value: A finite double.

    Returns:
        The nearest Float32.
    """
    var bits = bitcast[DType.uint64](value)
    var sign = UInt32(bits >> 63) << 31
    var field = Int((bits >> 52) & 0x7FF)
    var fraction = bits & ((UInt64(1) << 52) - 1)
    if field == 0:
        # A double this small rounds to a Float32 zero.
        return bitcast[DType.float32](sign)
    var exponent = field - 1023
    var significand = fraction | (UInt64(1) << 52)
    # Float32 keeps 24 significant bits, fewer below 2**-126.
    var drop = 29 + max(0, -126 - exponent)
    if drop > 53:
        return bitcast[DType.float32](sign)
    var kept = significand >> UInt64(drop)
    var rest = significand & ((UInt64(1) << UInt64(drop)) - 1)
    var half = UInt64(1) << UInt64(drop - 1)
    if rest > half or (rest == half and kept & 1 == 1):
        kept += 1
    if exponent < -126:
        # Subnormal: the field is zero unless rounding reached 2**-126.
        return bitcast[DType.float32](sign | UInt32(kept))
    if kept == UInt64(1) << 24:
        kept >>= 1
        exponent += 1
    var stored = UInt32(exponent + 127) << 23
    return bitcast[DType.float32](sign | stored | (UInt32(kept) & 0x7FFFFF))


def mul(a: Float32, b: Float32) -> Float32:
    """Return the Float32 product, rounded once.

    Args:
        a: The first factor.
        b: The second factor.

    Returns:
        The product.
    """
    return round32(Float64(a) * Float64(b))
