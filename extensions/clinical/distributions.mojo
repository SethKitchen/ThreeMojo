# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The t and F distributions, from the regularized incomplete beta
function.

- `beta_tails(x, a, b)` gives both tails of the beta distribution. The
  smaller tail comes from the continued fraction of Numerical Recipes,
  section 6.4, with the modified Lentz method, so it keeps its relative
  accuracy far out. `beta_quantile` inverts it.
- `student_t_upper` and `student_t_quantile` give the upper tail and the
  quantile of Student's t.
- `f_upper` and `f_quantile` give the upper tail and the quantile of the F
  distribution.
- `normal_quantile` gives the quantile of the standard normal
  distribution.
- `precise_exp` is `exp` to about one unit in the last place. The `exp`
  of Mojo 1.2 is off by about 3e-11 near -70, and a p value is an `exp`.

A quantile comes from Newton steps on the tail, kept inside a bracket by
bisection. The degrees of freedom are real numbers, as the interval of an
ICC needs.
"""

from std.math import erfc, expm1, floor, inf, isfinite, ldexp, lgamma, log
from std.math import log1p
from std.math import sqrt

# The most degrees of freedom of a distribution here.
comptime MAX_DEGREES = 1e8
# ln 2 in two parts, for an exact reduction (Cody and Waite).
comptime _LN2_HI = 6.93147180369123816490e-01
comptime _LN2_LO = 1.90821492927058770002e-10
comptime _INVERSE_LN2 = 1.4426950408889634
# The most terms of a continued fraction, and of a quantile search.
comptime _TERMS = 10000
comptime _SEARCH = 200
comptime _EPSILON = 1e-16


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
    var n = floor(x * _INVERSE_LN2 + 0.5)
    var r = (x - n * _LN2_HI) - n * _LN2_LO
    return ldexp(1.0 + expm1(r), Int32(Int(n)))


def _fraction(x: Float64, a: Float64, b: Float64) -> Float64:
    """Evaluate the continued fraction of I_x(a, b), for x below
    (a + 1) / (a + b + 2). Its denominators stay well away from 0 there."""
    var qab = a + b
    var qap = a + 1.0
    var qam = a - 1.0
    var c = 1.0
    var d = 1.0 / (1.0 - qab * x / qap)
    var h = d
    for m in range(1, _TERMS + 1):  # pragma: no branch
        var fm = Float64(m)
        var m2 = 2.0 * fm
        var aa = fm * (b - fm) * x / ((qam + m2) * (a + m2))
        d = 1.0 / (1.0 + aa * d)
        c = 1.0 + aa / c
        h *= d * c
        aa = -(a + fm) * (qab + fm) * x / ((a + m2) * (qap + m2))
        d = 1.0 / (1.0 + aa * d)
        c = 1.0 + aa / c
        var delta = d * c
        h *= delta
        if abs(delta - 1.0) < _EPSILON:
            break
    return h


def _log_beta(a: Float64, b: Float64) -> Float64:
    """Return ln B(a, b)."""
    return lgamma(a) + lgamma(b) - lgamma(a + b)


def _tails(
    x: Float64, y: Float64, a: Float64, b: Float64
) -> Tuple[Float64, Float64]:
    """Return I_x(a, b) and 1 - I_x(a, b), with y = 1 - x given exactly."""
    if x <= 0:
        return (0.0, 1.0)
    if y <= 0:
        return (1.0, 0.0)
    var front = a * log(x) + b * log(y) - _log_beta(a, b)
    if x < (a + 1.0) / (a + b + 2.0):
        var lower = precise_exp(front) * _fraction(x, a, b) / a
        return (lower, 1.0 - lower)
    var upper = precise_exp(front) * _fraction(y, b, a) / b
    return (1.0 - upper, upper)


def _require_shape(a: Float64, b: Float64) raises:
    """Refuse a shape that is not positive, finite and at most twice
    MAX_DEGREES."""
    if not (
        a > 0 and a <= 2.0 * MAX_DEGREES and b > 0 and b <= 2.0 * MAX_DEGREES
    ):
        raise Error("The degrees of freedom must be positive and at most 1e8")


def beta_tails(
    x: Float64, a: Float64, b: Float64
) raises -> Tuple[Float64, Float64]:
    """Return both tails of the beta distribution at a point.

    Args:
        x: The point, from 0 to 1.
        a: The first shape. Positive, at most 2e8.
        b: The second shape. Positive, at most 2e8.

    Returns:
        The regularized incomplete beta function I_x(a, b), and 1 less it.

    Raises:
        Error: If the point or a shape is out of range.
    """
    _require_shape(a, b)
    if not (x >= 0 and x <= 1):
        raise Error("A beta point must be from 0 to 1")
    return _tails(x, 1.0 - x, a, b)


def _invert(target: Float64, a: Float64, b: Float64) -> Tuple[Float64, Float64]:
    """Return x and 1 - x with I_x(a, b) = target, for a target between 0
    and 1. Newton steps go on the lower tail, and bisection keeps them in
    the bracket."""
    var low = 0.0
    var high = 1.0
    var x = a / (a + b)
    var log_beta = _log_beta(a, b)
    for _ in range(_SEARCH):  # pragma: no branch
        var gap = _tails(x, 1.0 - x, a, b)[0] - target
        if gap > 0:
            high = x
        else:
            low = x
        var density = precise_exp(
            (a - 1.0) * log(x) + (b - 1.0) * log1p(-x) - log_beta
        )
        var next = x - gap / density
        if not (next > low and next < high):
            next = 0.5 * (low + high)
        if abs(next - x) <= 4e-16 * next:
            x = next
            break
        x = next
    return (x, 1.0 - x)


def beta_quantile(p: Float64, a: Float64, b: Float64) raises -> Float64:
    """Return the quantile of the beta distribution.

    Args:
        p: The probability. Between 0 and 1.
        a: The first shape. Positive, at most 2e8.
        b: The second shape. Positive, at most 2e8.

    Returns:
        The x with I_x(a, b) = p. Above a half, the search runs on the
        upper tail, so an x near 1 keeps its accuracy.

    Raises:
        Error: If the probability or a shape is out of range.
    """
    _require_shape(a, b)
    _require_probability(p)
    if p <= 0.5:
        return _invert(p, a, b)[0]
    return _invert(1.0 - p, b, a)[1]


# The rational approximation of Acklam (2003) to the normal quantile.
comptime _A0 = -3.969683028665376e01
comptime _A1 = 2.209460984245205e02
comptime _A2 = -2.759285104469687e02
comptime _A3 = 1.383577518672690e02
comptime _A4 = -3.066479806614716e01
comptime _A5 = 2.506628277459239e00
comptime _B0 = -5.447609879822406e01
comptime _B1 = 1.615858368580409e02
comptime _B2 = -1.556989798598866e02
comptime _B3 = 6.680131188771972e01
comptime _B4 = -1.328068155288572e01
comptime _C0 = -7.784894002430293e-03
comptime _C1 = -3.223964580411365e-01
comptime _C2 = -2.400758277161838e00
comptime _C3 = -2.549732539343734e00
comptime _C4 = 4.374664141464968e00
comptime _C5 = 2.938163982698783e00
comptime _D0 = 7.784695709041462e-03
comptime _D1 = 3.224671290700398e-01
comptime _D2 = 2.445134137142996e00
comptime _D3 = 3.754408661907416e00
comptime _SQRT_TWO = 1.4142135623730951
comptime _SQRT_TWO_PI = 2.5066282746310002


def normal_quantile(p: Float64) raises -> Float64:
    """Return the quantile of the standard normal distribution.

    Acklam's rational approximation, good to about 1e-9, starts one step
    of Halley's method on `erfc`, which is exact. Above a half, the
    quantile is the negative of the quantile of `1 - p`, which is exact.

    Args:
        p: The probability. Between 0 and 1, and at least 1e-300 from
            each end.

    Returns:
        The z with P(Z <= z) = p.

    Raises:
        Error: If the probability is out of range.
    """
    _require_probability(p)
    if p > 0.5:
        return -normal_quantile(1.0 - p)
    if p < 1e-300:
        raise Error("A normal quantile needs a probability of 1e-300 or more")
    var x: Float64
    if p < 0.02425:
        var q = sqrt(-2.0 * log(p))
        x = (((((_C0 * q + _C1) * q + _C2) * q + _C3) * q + _C4) * q + _C5) / (
            (((_D0 * q + _D1) * q + _D2) * q + _D3) * q + 1.0
        )
    else:
        var q = p - 0.5
        var r = q * q
        x = (
            (((((_A0 * r + _A1) * r + _A2) * r + _A3) * r + _A4) * r + _A5)
            * q
            / (((((_B0 * r + _B1) * r + _B2) * r + _B3) * r + _B4) * r + 1.0)
        )
    var e = 0.5 * erfc(-x / _SQRT_TWO) - p
    var u = e * _SQRT_TWO_PI * precise_exp(0.5 * x * x)
    return x - u / (1.0 + 0.5 * x * u)


def _require_probability(p: Float64) raises:
    """Refuse a probability that is not strictly between 0 and 1."""
    if not (p > 0 and p < 1):
        raise Error("A quantile needs a probability between 0 and 1")


def _require_degrees(df: Float64) raises:
    """Refuse degrees of freedom that are not positive or above the
    most."""
    if not (df > 0 and df <= MAX_DEGREES):
        raise Error("The degrees of freedom must be positive and at most 1e8")


def student_t_upper(t: Float64, df: Float64) raises -> Float64:
    """Return the chance that Student's t is more than a value.

    Args:
        t: The value. Finite.
        df: The degrees of freedom. Positive, at most 1e8.

    Returns:
        P(T > t).

    Raises:
        Error: If the value is not finite, or the freedom is out of range.
    """
    _require_degrees(df)
    if not isfinite(t):
        raise Error("A t value must be finite")
    var t2 = t * t
    # P(|T| > |t|) = I_z(df / 2, 1 / 2), with z = df / (df + t^2).
    var both = _tails(df / (df + t2), t2 / (df + t2), 0.5 * df, 0.5)[0]
    if t >= 0:
        return 0.5 * both
    return 1.0 - 0.5 * both


def student_t_quantile(p: Float64, df: Float64) raises -> Float64:
    """Return the quantile of Student's t.

    Args:
        p: The probability. Between 0 and 1.
        df: The degrees of freedom. Positive, at most 1e8.

    Returns:
        The t with P(T <= t) = p.

    Raises:
        Error: If the probability or the freedom is out of range.
    """
    _require_degrees(df)
    _require_probability(p)
    if p == 0.5:
        return 0.0
    var tail = min(p, 1.0 - p)
    var size: Float64
    if tail <= 0.25:
        # 2 tail = I_z(df / 2, 1 / 2), and t^2 = df (1 - z) / z.
        var z = _invert(2.0 * tail, 0.5 * df, 0.5)
        size = sqrt(df * z[1] / z[0])
    else:
        # 1 - 2 tail = I_w(1 / 2, df / 2), and t^2 = df w / (1 - w).
        var w = _invert(1.0 - 2.0 * tail, 0.5, 0.5 * df)
        size = sqrt(df * w[0] / w[1])
    if p > 0.5:
        return size
    return -size


def f_upper(x: Float64, d1: Float64, d2: Float64) raises -> Float64:
    """Return the chance that an F value is more than a value.

    Args:
        x: The value. 0 or more, and finite.
        d1: The degrees of freedom of the numerator.
        d2: The degrees of freedom of the denominator.

    Returns:
        P(F > x).

    Raises:
        Error: If the value is negative or not finite, or a freedom is out
            of range.
    """
    _require_degrees(d1)
    _require_degrees(d2)
    if not (x >= 0) or not isfinite(x):
        raise Error("An F value must be 0 or more, and finite")
    # P(F > x) = I_y(d2 / 2, d1 / 2), with y = d2 / (d2 + d1 x).
    var s = d2 + d1 * x
    return _tails(d2 / s, d1 * x / s, 0.5 * d2, 0.5 * d1)[0]


def f_quantile(p: Float64, d1: Float64, d2: Float64) raises -> Float64:
    """Return the quantile of the F distribution.

    Args:
        p: The probability. Between 0 and 1.
        d1: The degrees of freedom of the numerator.
        d2: The degrees of freedom of the denominator.

    Returns:
        The x with P(F <= x) = p.

    Raises:
        Error: If the probability or a freedom is out of range.
    """
    _require_degrees(d1)
    _require_degrees(d2)
    _require_probability(p)
    # 1 - p = I_y(d2 / 2, d1 / 2), and x = d2 (1 - y) / (d1 y).
    var y = _invert(1.0 - p, 0.5 * d2, 0.5 * d1)
    return d2 * y[1] / (d1 * y[0])
