# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Elementary functions to about one unit in the last place.

The Float64 `exp` of Mojo 1.2 is off by up to about 3e-11 near -70, and so
is a fractional power `x**y`, which takes it. `log2` is off by about 1e-9.
`log` and `expm1` are exact to the last place, so these functions build on
them:

- `precise_exp(x)` reduces x by ln 2 in two parts, after Cody and Waite,
  and takes `expm1` of the rest.
- `precise_power(x, p)` is `x^p` for an x of 0 or more.
- `precise_power10(x)` is `10^x`.
- `precise_log2(x)` is `log(x) / ln 2`.

`LN2`, `LN10` and `INVERSE_LN2` are the constants, rounded once.
"""

from std.math import expm1, floor, inf, ldexp, log

comptime LN2 = 0.6931471805599453
"""The natural logarithm of 2."""
comptime LN10 = 2.302585092994046
"""The natural logarithm of 10."""
comptime INVERSE_LN2 = 1.4426950408889634
"""1 / ln 2: the base-2 logarithm of e."""
# ln 2 in two parts, for an exact reduction (Cody and Waite).
comptime _LN2_HI = 6.93147180369123816490e-01
comptime _LN2_LO = 1.90821492927058770002e-10


def precise_exp(x: Float64) -> Float64:
    """Return `e^x` to about one unit in the last place.

    Args:
        x: The exponent.

    Returns:
        `e^x`. 0 below -708, where the result is no longer a normal
        number, and infinity above 709.
    """
    if not (x >= -708.0):
        return 0.0
    if x > 709.0:
        return inf[DType.float64]()
    var n = floor(x * INVERSE_LN2 + 0.5)
    var r = (x - n * _LN2_HI) - n * _LN2_LO
    return ldexp(1.0 + expm1(r), Int32(Int(n)))


def precise_power(x: Float64, p: Float64) -> Float64:
    """Return `x^p` for an x of 0 or more.

    Args:
        x: The base, 0 or more.
        p: The exponent.

    Returns:
        `exp(p ln x)`. At x = 0: 0 for a positive p, 1 for p = 0 and
        infinity for a negative p.
    """
    if x == 0:
        if p > 0:
            return 0.0
        if p == 0:
            return 1.0
        return inf[DType.float64]()
    return precise_exp(p * log(x))


def precise_power10(x: Float64) -> Float64:
    """Return `10^x`.

    Args:
        x: The exponent.

    Returns:
        `exp(x ln 10)`.
    """
    return precise_exp(x * LN10)


def precise_log2(x: Float64) -> Float64:
    """Return the base-2 logarithm.

    Args:
        x: The value, above 0.

    Returns:
        `log(x) / ln 2`.
    """
    return log(x) * INVERSE_LN2
