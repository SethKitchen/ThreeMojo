# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The Fortran arithmetic of the MODFLOW 6 port: powers, logarithms and unfused products.

MODFLOW 6 raises numbers to real powers and takes logarithms with the
library of its compiler, which calls the C library. The `**` operator and
`log` of Mojo can round differently in the last digits, and so can the C
library of a platform other than Linux. Those digits change the iterations
of the solver. So the port calls `glibc_pow` and `glibc_log` of
`extensions/numerics/libm.mojo`, which give the bits of glibc on x86-64,
where the references were made, on every platform.
"""

from std.ffi import external_call

from extensions.numerics.libm import glibc_log, glibc_pow


def cpow(x: Float64, y: Float64) -> Float64:
    """Return x to the power y, with the bits of glibc's `pow`.

    Args:
        x: The base.
        y: The exponent.

    Returns:
        The power, as glibc computes it on x86-64.
    """
    return glibc_pow(x, y)


def clog(x: Float64) -> Float64:
    """Return the natural logarithm of x, with the bits of glibc's `log`.

    Args:
        x: The number.

    Returns:
        The logarithm, as glibc computes it on x86-64.
    """
    return glibc_log(x)


@no_inline
def mul(a: Float64, b: Float64) -> Float64:
    """Return `a * b`, rounded before any sum uses it, as Fortran rounds it.

    The function is not inlined, so the compiler cannot contract the
    product and a later sum into one fused multiply-add. The build of
    MODFLOW 6 does not fuse them.

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


def powi(x: Float64, m: Int) -> Float64:
    """Return x to an integer power, as gfortran computes `x**m`.

    gfortran calls `__powidf2` of libgcc for a real base and an integer
    exponent. It squares and multiplies, and does not call `pow`.

    Args:
        x: The base.
        m: The exponent.

    Returns:
        The power, rounded as `__powidf2` rounds it.
    """
    var n = m
    if n < 0:
        n = -n
    var b = x
    var y = 1.0
    if n % 2 == 1:
        y = b
    n = n // 2
    while n > 0:
        b = mul(b, b)
        if n % 2 == 1:
            y = mul(y, b)
        n = n // 2
    if m < 0:
        return 1.0 / y
    return y


def is_close(
    a: Float64, b: Float64, rtol: Float64 = 2.220446049250313e-14
) -> Bool:
    """Return True if two numbers are equal within a relative tolerance.

    This is the symmetric test of `is_close` in MathUtil.f90, with no
    absolute tolerance.

    Args:
        a: The first number.
        b: The second number.
        rtol: The relative tolerance. The default is `DSAME`.

    Returns:
        Whether `|a - b| <= rtol * max(|a|, |b|)`.
    """
    if a == b:
        return True
    return abs(a - b) <= max(mul(rtol, max(abs(a), abs(b))), 0.0)


def fsign(a: Float64, b: Float64) -> Float64:
    """Return |a| with the sign of b, as the Fortran `SIGN` does.

    Args:
        a: The magnitude.
        b: The number whose sign the result takes.

    Returns:
        |a| if b >= 0, else -|a|. A negative zero b gives -|a|.
    """
    from std.math import copysign

    return copysign(abs(a), b)
