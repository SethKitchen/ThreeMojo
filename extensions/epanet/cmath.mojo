# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The C arithmetic of the EPANET port: `pow`, `log` and unfused products.

EPANET raises numbers to real powers and takes logarithms with the C library. The
`**` operator and `log` of Mojo can round differently in the last digits. Those
digits change the iterations of the solver, so the port calls C.
"""

from std.ffi import external_call


def cpow(x: Float64, y: Float64) -> Float64:
    """Return x to the power y, with `pow` of the C library.

    Args:
        x: The base.
        y: The exponent.

    Returns:
        The power, as C computes it.
    """
    return external_call["pow", Float64](x, y)


def clog(x: Float64) -> Float64:
    """Return the natural logarithm of x, with `log` of the C library.

    Args:
        x: The number.

    Returns:
        The logarithm, as C computes it.
    """
    return external_call["log", Float64](x)


@no_inline
def mul(a: Float64, b: Float64) -> Float64:
    """Return `a * b`, rounded before any sum uses it, as C rounds it.

    The function is not inlined, so the compiler cannot contract the
    product and a later sum into one fused multiply-add. The C build of
    EPANET does not fuse them, and the solver amplifies the difference
    in the last digit.

    Args:
        a: The first factor.
        b: The second factor.

    Returns:
        The rounded product.
    """
    return a * b


def cstrtod(text: String, mut used: Int) -> Float64:
    """Read the number at the start of a text, with `strtod` of the C library.

    Args:
        text: The text.
        used: Receives the count of bytes that the number fills.

    Returns:
        The number, as C reads it, or 0 when `used` is 0.
    """
    var buf = List[UInt8](capacity=text.byte_length() + 1)
    for b in text.as_bytes():
        buf.append(b)
    buf.append(0)
    var end = List[Int](length=1, fill=0)
    var y = external_call["strtod", Float64](
        buf.unsafe_ptr().unsafe_bitcast[NoneType](),
        end.unsafe_ptr().unsafe_bitcast[NoneType](),
    )
    used = end[0] - Int(buf.unsafe_ptr())
    return y
