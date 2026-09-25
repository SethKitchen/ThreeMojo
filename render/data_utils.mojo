# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Half floats, from three.js `src/extras/DataUtils.js`.

A half float is sixteen bits: a sign, five bits of exponent and ten of
fraction. three.js keeps half-float textures and vertex data in a
`Uint16Array` and converts with `DataUtils.toHalfFloat` and
`fromHalfFloat`. Both functions here give three.js's bits, bit for bit.

`to_half_float` is three.js's table method written as arithmetic. The
number is clamped to the largest half, 65504, and rounded to a `Float32`.
The float's extra fraction bits are then cut off, not rounded, as
three.js's shift table cuts them. So 1.0007 becomes 0x3C00, which is one,
here and in three.js, although 0x3C01 is nearer. An infinity is clamped
first, so it gives the largest half and not an infinite one.

A number that is not a number gives 0xFE00, a NaN with its sign set.
three.js's clamp returns the processor's own NaN, and on x86-64 that NaN
is negative, whatever NaN went in. So 0xFE00 is what three.js gives in
Node on a desktop, and what `exporters.exr` writes for a NaN.

`from_half_float` is `render.exr.half_to_float`, which the image decoders
use. Every half is a `Float32` exactly, so there is nothing to round.
"""

from render.exr import half_to_float
from std.math import isnan
from std.memory import bitcast

# The largest finite half, which three.js clamps to.
comptime HALF_MAX = Float64(65504)
# The half three.js gives for a NaN on x86-64: the sign set, and a quiet
# fraction.
comptime NAN_HALF = UInt16(0xFE00)


def to_half_float(value: Float64) -> UInt16:
    """Return a number as the bits of a half float, three.js's
    `DataUtils.toHalfFloat`.

    Args:
        value: The number.

    Returns:
        The sixteen bits: the number clamped to the largest half, rounded
        to a `Float32`, and its extra fraction bits cut off.
    """
    if isnan(value):
        # three.js's clamp lets a NaN through as the processor's own NaN,
        # whose sign is set on x86-64. Its payload is a quiet bit.
        return NAN_HALF
    var clamped = max(-HALF_MAX, min(HALF_MAX, value))
    var bits = bitcast[DType.uint32](Float32(clamped))
    var sign = Int((bits >> 16) & 0x8000)
    var exponent = Int((bits >> 23) & 0xFF) - 127
    var fraction = Int(bits & 0x007FFFFF)
    var base: Int
    var shift: Int
    if exponent < -27:
        base = 0
        shift = 24
    elif exponent < -14:
        base = 0x0400 >> (-exponent - 14)
        shift = -exponent - 1
    else:
        # A normal half. The clamp leaves no exponent above 15, the
        # largest half's, so three.js's rows for an infinity are not
        # reached.
        base = (exponent + 15) << 10
        shift = 13
    return UInt16((base | sign) + (fraction >> shift))


def from_half_float(bits: UInt16) -> Float32:
    """Return the number the bits of a half float spell, three.js's
    `DataUtils.fromHalfFloat`.

    Args:
        bits: The sixteen bits.

    Returns:
        The number, exactly. A zero keeps its sign, and an infinity and a
        number that is not a number keep theirs and their fraction.
    """
    return half_to_float(bits)
