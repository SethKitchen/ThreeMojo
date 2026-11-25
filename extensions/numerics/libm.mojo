# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from math/pow.c and math/log.c of Arm's optimized routines,
# commit 9a0d5027. Copyright (c) 2018 Arm Limited. MIT license: see
# THIRD-PARTY-NOTICES.md.

"""`pow` and `log` with the bits of glibc on x86-64, on every platform.

The EPANET and MODFLOW ports call `pow` and `log` where the C programs
do. Their references come from glibc on Linux x86-64. The C library of
another platform rounds some of these values to the other neighbor of
the true value. One such bit can change the iterations of a solver, and
then a status and every head after it. So the ports call these two
functions in place of the C library, and give the same doubles on every
platform.

glibc's `pow` and `log` are the code of Arm's optimized routines. On a
processor with fused multiply-add, glibc runs a build that GCC compiles
with `-mfma`, and GCC then fuses many of the products and sums. Mojo also
fuses a product into a sum when it can, so this port states each fused
operation as `fma` and keeps each other product apart with `_mul`. The
choice of fused operations is that of GCC 15 on the code with
`HAVE_FAST_FMA`. `tests/test_numerics_libm.mojo` checks the result against
glibc 2.43, bit for bit.

Errors do not set `errno` here. The values are those of glibc.
"""

from extensions.numerics.libm_data import (
    EXP_INV_LN2_N,
    EXP_NEG_LN2_HI_N,
    EXP_NEG_LN2_LO_N,
    EXP_POLY,
    EXP_SHIFT,
    EXP_TAB,
    LOG_LN2_HI,
    LOG_LN2_LO,
    LOG_POLY,
    LOG_POLY1,
    LOG_TAB,
    POW_LN2_HI,
    POW_LN2_LO,
    POW_POLY,
    POW_TAB,
)
from std.builtin.globals import global_constant
from std.math import fma
from std.memory import bitcast

# The bits of 1.0 and of infinity.
comptime _ONE: UInt64 = 0x3FF0000000000000
comptime _INF: UInt64 = 0x7FF0000000000000
# The sign bit, and the bits of a double without it.
comptime _SIGN: UInt64 = 0x8000000000000000
comptime _ABS: UInt64 = 0x7FFFFFFFFFFFFFFF
# The start of the range that the tables of `pow` split.
comptime _POW_OFF: UInt64 = 0x3FE6955500000000
# The start of the range that the tables of `log` split.
comptime _LOG_OFF: UInt64 = 0x3FE6000000000000
# The edges of the range near 1.0 where `log` has its own polynomial:
# 1 - 2^-4 and 1 + 0x1.09p-4.
comptime _NEAR_LO: UInt64 = 0x3FEE000000000000
comptime _NEAR_HI: UInt64 = 0x3FF1090000000000
# The exponent and fraction field of a double.
comptime _EXPONENT: UInt64 = 0xFFF0000000000000
# The flag that `pow` adds to the exponent of 2^(k/128) for a negative
# result.
comptime _SIGN_BIAS: UInt64 = 0x800 << 7
# 2^52, 2^27, 2^1009 and 2^-1022.
comptime _TWO_52: UInt64 = 0x4330000000000000
comptime _TWO_27: UInt64 = 0x41A0000000000000
comptime _TWO_1009: UInt64 = 0x7F00000000000000
comptime _TWO_M1022: UInt64 = 0x0010000000000000


def _f(bits: UInt64) -> Float64:
    """Return the double whose bits these are.

    Args:
        bits: The bits.

    Returns:
        The double.
    """
    return bitcast[DType.float64](bits)


def _u(x: Float64) -> UInt64:
    """Return the bits of a double.

    Args:
        x: The double.

    Returns:
        Its bits.
    """
    return bitcast[DType.uint64](x)


@no_inline
def _mul(a: Float64, b: Float64) -> Float64:
    """Return `a * b`, rounded before any sum uses it.

    The function is not inlined, so that Mojo cannot fuse the product
    into a later sum. GCC did not fuse it in glibc.

    Args:
        a: The first factor.
        b: The second factor.

    Returns:
        The rounded product.
    """
    return a * b


def _zero_inf_nan(bits: UInt64) -> Bool:
    """Return whether a double is zero, infinite or not a number.

    Args:
        bits: The bits of the double.

    Returns:
        True for a zero of either sign, an infinity or a NaN.
    """
    return 2 * bits - 1 >= 2 * _INF - 1


def _signaling(x: Float64) -> Bool:
    """Return whether a double is a signaling NaN.

    Args:
        x: The double.

    Returns:
        True for a NaN whose quiet bit is clear.
    """
    return 2 * (_u(x) ^ 0x0008000000000000) > 2 * UInt64(0x7FF8000000000000)


def _check_int(iy: UInt64) -> Int:
    """Classify a double as not an integer, an odd or an even integer.

    Args:
        iy: The bits of the double, which is finite and not zero.

    Returns:
        0 when it is not an integer, 1 when it is odd and 2 when it is
        even.
    """
    var e = Int((iy >> 52) & 0x7FF)
    if e < 0x3FF:
        return 0
    if e > 0x3FF + 52:
        return 2
    var unit = UInt64(1) << UInt64(0x3FF + 52 - e)
    if iy & (unit - 1) != 0:
        return 0
    if iy & unit != 0:
        return 1
    return 2


def _invalid(x: Float64) -> Float64:
    """Return the NaN of an invalid operation, as glibc computes it.

    Args:
        x: The argument.

    Returns:
        `(x - x) / (x - x)`.
    """
    var d = x - x
    return d / d


def _overflow(negative: Bool) -> Float64:
    """Return the infinity of an overflow.

    Args:
        negative: Whether the result is negative.

    Returns:
        The infinity.
    """
    return -_f(_INF) if negative else _f(_INF)


def _underflow(negative: Bool) -> Float64:
    """Return the zero of an underflow.

    Args:
        negative: Whether the result is negative.

    Returns:
        The zero.
    """
    return -0.0 if negative else 0.0


def _log_inline(ix: UInt64) -> Tuple[Float64, Float64]:
    """Return the logarithm of a double in two parts, for `pow`.

    Args:
        ix: The bits of the double. A subnormal double is normalized,
            with an exponent below that of the normal range.

    Returns:
        The rounded logarithm and about 15 bits more of it.
    """
    ref tab = global_constant[POW_TAB]()
    ref a = global_constant[POW_POLY]()
    var tmp = ix - _POW_OFF
    var i = Int((tmp >> 45) % 128)
    var k = Int(bitcast[DType.int64](tmp) >> 52)
    var iz = ix - (tmp & _EXPONENT)
    var z = _f(iz)
    var kd = Float64(k)
    var invc = _f(tab[3 * i])
    var logc = _f(tab[3 * i + 1])
    var logctail = _f(tab[3 * i + 2])
    var r = fma(z, invc, -1.0)
    var t1 = fma(kd, _f(POW_LN2_HI), logc)
    var t2 = r + t1
    var lo1 = fma(kd, _f(POW_LN2_LO), logctail)
    var lo2 = r + (t1 - t2)
    var ar = _mul(r, _f(a[0]))
    var ar2 = _mul(r, ar)
    var ar3 = _mul(r, ar2)
    var hi = t2 + ar2
    var lo3 = fma(r, ar, -ar2)
    var lo4 = ar2 + (t2 - hi)
    var p12 = fma(r, _f(a[2]), _f(a[1]))
    var p34 = fma(r, _f(a[4]), _f(a[3]))
    var p56 = fma(r, _f(a[6]), _f(a[5]))
    var p = fma(ar2, fma(ar2, p56, p34), p12)
    var lo = fma(ar3, p, lo4 + (lo3 + (lo1 + lo2)))
    var y = hi + lo
    return (y, lo + (hi - y))


def _exp_special(tmp: Float64, sbits: UInt64, ki: UInt64) -> Float64:
    """Return `scale * (1 + tmp)` where it can overflow or underflow.

    Args:
        tmp: The polynomial part.
        sbits: The bits of the scale, with an exponent that can be out of
            range.
        ki: The integer of the reduction. Bit 31 is set when the result
            can underflow.

    Returns:
        The result, rounded once in the subnormal range.
    """
    if ki & 0x80000000 == 0:
        var scale = _f(sbits - (UInt64(1009) << 52))
        return _mul(fma(tmp, scale, scale), _f(_TWO_1009))
    var signed = sbits + (UInt64(1022) << 52)
    var scale = _f(signed)
    var product = _mul(tmp, scale)
    var y = scale + product
    if abs(y) < 1.0:
        var one = -1.0 if y < 0.0 else 1.0
        var lo = product + (scale - y)
        var hi = y + one
        lo = lo + (y + (one - hi))
        y = (hi + lo) - one
        if y == 0.0:
            y = _f(signed & _SIGN)
    return _mul(_f(_TWO_M1022), y)


def _exp_inline(x: Float64, xtail: Float64, sign_bias: UInt64) -> Float64:
    """Return `exp(x + xtail)`, negated when `sign_bias` is set, for `pow`.

    Args:
        x: The argument.
        xtail: A small correction to it.
        sign_bias: `_SIGN_BIAS` for a negative result, or 0.

    Returns:
        The exponential.
    """
    var abstop = (_u(x) >> 52) & 0x7FF
    var special = False
    if abstop - 0x3C9 >= 0x408 - 0x3C9:
        if abstop < 0x3C9:
            var one = 1.0 + x
            return -one if sign_bias != 0 else one
        if abstop >= 0x409:
            if _u(x) >> 63 != 0:
                return _underflow(sign_bias != 0)
            return _overflow(sign_bias != 0)
        special = True
    ref tab = global_constant[EXP_TAB]()
    ref c = global_constant[EXP_POLY]()
    var shift = _f(EXP_SHIFT)
    var kd = fma(x, _f(EXP_INV_LN2_N), shift)
    var ki = _u(kd)
    kd = kd - shift
    var r = fma(kd, _f(EXP_NEG_LN2_LO_N), fma(kd, _f(EXP_NEG_LN2_HI_N), x))
    r = xtail + r
    var idx = Int(2 * (ki % 128))
    var top = (ki + sign_bias) << 45
    var tail = _f(tab[idx])
    var sbits = tab[idx + 1] + top
    var r2 = _mul(r, r)
    var low = fma(r2, fma(r, _f(c[1]), _f(c[0])), r + tail)
    var tmp = fma(_mul(r2, r2), fma(r, _f(c[3]), _f(c[2])), low)
    if special:
        return _exp_special(tmp, sbits, ki)
    var scale = _f(sbits)
    return fma(tmp, scale, scale)


def _pow_zero_inf_nan_y(x: Float64, y: Float64) -> Float64:
    """Return `x^y` for a `y` that is zero, infinite or not a number.

    Args:
        x: The base.
        y: The exponent.

    Returns:
        The power.
    """
    var ix = _u(x)
    var iy = _u(y)
    if 2 * iy == 0:
        return x + y if _signaling(x) else 1.0
    if ix == _ONE:
        return x + y if _signaling(y) else 1.0
    if 2 * ix > 2 * _INF:
        return x + y
    if 2 * iy > 2 * _INF:
        return x + y
    if 2 * ix == 2 * _ONE:
        return 1.0
    if (2 * ix < 2 * _ONE) == (iy >> 63 == 0):
        return 0.0
    return y * y


def _pow_zero_inf_nan_x(x: Float64, iy: UInt64) -> Float64:
    """Return `x^y` for an `x` that is zero, infinite or not a number.

    Args:
        x: The base.
        iy: The bits of the exponent, which is finite and not zero.

    Returns:
        The power.
    """
    var x2 = x * x
    if _u(x) >> 63 != 0 and _check_int(iy) == 1:
        x2 = -x2
    if iy >> 63 != 0:
        return 1.0 / x2
    return x2


def glibc_pow(x: Float64, y: Float64) -> Float64:
    """Return `x^y` with the bits of glibc's `pow` on x86-64.

    Args:
        x: The base.
        y: The exponent.

    Returns:
        The power. A negative base with an exponent that is not an
        integer gives NaN.
    """
    var ix = _u(x)
    var iy = _u(y)
    var topx = ix >> 52
    var topy = iy >> 52
    var sign_bias: UInt64 = 0
    var tiny_or_huge_y = (topy & 0x7FF) - 0x3BE >= 0x43E - 0x3BE
    if topx - 1 >= 0x7FF - 1 or tiny_or_huge_y:
        if _zero_inf_nan(iy):
            return _pow_zero_inf_nan_y(x, y)
        if _zero_inf_nan(ix):
            return _pow_zero_inf_nan_x(x, iy)
        if ix >> 63 != 0:
            var yint = _check_int(iy)
            if yint == 0:
                return _invalid(x)
            if yint == 1:
                sign_bias = _SIGN_BIAS
            ix = ix & _ABS
            topx = topx & 0x7FF
        if tiny_or_huge_y:
            if ix == _ONE:
                return 1.0
            if (topy & 0x7FF) < 0x3BE:
                return 1.0 + y if ix > _ONE else 1.0 - y
            if (ix > _ONE) == (topy < 0x800):
                return _overflow(False)
            return _underflow(False)
        if topx == 0:
            ix = (_u(x * _f(_TWO_52)) & _ABS) - (UInt64(52) << 52)
    var parts = _log_inline(ix)
    var hi = parts[0]
    var lo = parts[1]
    var ehi = _mul(y, hi)
    var elo = fma(y, lo, fma(y, hi, -ehi))
    return _exp_inline(ehi, elo, sign_bias)


def _log_near_one(x: Float64) -> Float64:
    """Return `log(x)` for an `x` within about 1/16 of 1.

    Args:
        x: The number.

    Returns:
        The logarithm.
    """
    ref b = global_constant[LOG_POLY1]()
    var r = x - 1.0
    var r2 = _mul(r, r)
    var r3 = _mul(r, r2)
    var p1 = fma(_f(b[3]), r2, fma(_f(b[2]), r, _f(b[1])))
    var p4 = fma(_f(b[6]), r2, fma(_f(b[5]), r, _f(b[4])))
    var p7 = fma(_f(b[10]), r3, fma(_f(b[9]), r2, fma(_f(b[8]), r, _f(b[7]))))
    var poly = fma(fma(p7, r3, p4), r3, p1)
    var two27 = _f(_TWO_27)
    var rhi = fma(-r, two27, fma(r, two27, r))
    var rlo = r - rhi
    var rhi2 = _mul(rhi, rhi)
    var b0 = _f(b[0])
    var hi = fma(rhi2, b0, r)
    var lo = fma(rhi2, b0, r - hi)
    lo = fma(_mul(b0, rlo), r + rhi, lo)
    return hi + fma(poly, r3, lo)


def glibc_log(x: Float64) -> Float64:
    """Return the natural logarithm with the bits of glibc's `log` on
    x86-64.

    Args:
        x: The number.

    Returns:
        The logarithm: minus infinity at zero, and NaN below zero.
    """
    var ix = _u(x)
    if ix - _NEAR_LO < _NEAR_HI - _NEAR_LO:
        if ix == _ONE:
            return 0.0
        return _log_near_one(x)
    var top = ix >> 48
    if top - 0x0010 >= 0x7FF0 - 0x0010:
        if ix * 2 == 0:
            return -_f(_INF)
        if ix == _INF:
            return x
        if top & 0x8000 != 0:
            return _invalid(x)
        if top & 0x7FF0 == 0x7FF0:
            return _invalid(x)
        ix = _u(x * _f(_TWO_52)) - (UInt64(52) << 52)
    ref tab = global_constant[LOG_TAB]()
    ref a = global_constant[LOG_POLY]()
    var tmp = ix - _LOG_OFF
    var i = Int((tmp >> 45) % 128)
    var k = Int(bitcast[DType.int64](tmp) >> 52)
    var iz = ix - (tmp & _EXPONENT)
    var invc = _f(tab[2 * i])
    var logc = _f(tab[2 * i + 1])
    var r = fma(_f(iz), invc, -1.0)
    var kd = Float64(k)
    var w = fma(_f(LOG_LN2_HI), kd, logc)
    var hi = r + w
    var lo = fma(_f(LOG_LN2_LO), kd, (w - hi) + r)
    var r2 = _mul(r, r)
    var low = fma(_f(a[0]), r2, lo)
    var p = fma(fma(_f(a[4]), r, _f(a[3])), r2, fma(_f(a[2]), r, _f(a[1])))
    return fma(_mul(r, r2), p, low) + hi
