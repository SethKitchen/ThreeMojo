# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Correlations of two measures, as scipy gives them.

- `pearson(x, y)` gives Pearson's r, the two-sided p value of the test
  that r is 0, and the 95 percent interval of r by Fisher's z.
- `spearman(x, y)` gives Spearman's rho, Pearson's r of the midranks, with
  the same test.
- `kendall(x, y)` gives Kendall's tau-b, which corrects for ties, with the
  two-sided test of the normal approximation and its tie-corrected
  variance.

The p value of r is `2 I_((1 - |r|) / 2)(n/2 - 1, n/2 - 1)`, as scipy
computes it from the beta distribution. Fisher's z uses `atanh` and `tanh`
from `log1p` and `expm1`, which are exact.
"""

from extensions.clinical.distributions import beta_tails
from extensions.clinical.hypothesis import midranks
from extensions.clinical.survival import Z95
from math.sort_utils import stable_sort
from std.math import erfc, expm1, isfinite, log1p, sqrt

comptime _SQRT_TWO = 1.4142135623730951


struct Correlation(Copyable, Movable):
    """A correlation with its two-sided test."""

    var value: Float64
    """The correlation, from -1 to 1."""
    var p_value: Float64
    """The chance of a correlation this far from 0 when there is none."""
    var lower: Float64
    """The low end of the 95 percent interval. Pearson's only; -1
    otherwise."""
    var upper: Float64
    """The high end of the 95 percent interval. Pearson's only; 1
    otherwise."""

    def __init__(
        out self,
        value: Float64,
        p_value: Float64,
        lower: Float64,
        upper: Float64,
    ):
        """Create a result.

        Args:
            value: The correlation.
            p_value: The two-sided p value.
            lower: The low end of the interval.
            upper: The high end of the interval.
        """
        self.value = value
        self.p_value = p_value
        self.lower = lower
        self.upper = upper


def _require_pairs(x: List[Float64], y: List[Float64], least: Int) raises:
    """Refuse lists that differ in length, are too short, or hold a value
    that is not finite."""
    if len(x) != len(y) or len(x) < least:
        raise Error("A correlation needs pairs of values, enough of them")
    for i in range(len(x)):  # pragma: no branch
        if not isfinite(x[i]) or not isfinite(y[i]):
            raise Error("The values of a correlation must be finite")


def _r(x: List[Float64], y: List[Float64]) raises -> Float64:
    """Return Pearson's r, held from -1 to 1."""
    var n = Float64(len(x))
    var mx = 0.0
    var my = 0.0
    for i in range(len(x)):  # pragma: no branch
        mx += x[i]
        my += y[i]
    mx /= n
    my /= n
    var sxy = 0.0
    var sxx = 0.0
    var syy = 0.0
    for i in range(len(x)):  # pragma: no branch
        var dx = x[i] - mx
        var dy = y[i] - my
        sxy += dx * dy
        sxx += dx * dx
        syy += dy * dy
    if not (sxx > 0 and syy > 0):
        raise Error("A correlation needs values that vary")
    return max(-1.0, min(1.0, sxy / sqrt(sxx) / sqrt(syy)))


def _r_p_value(r: Float64, n: Int) raises -> Float64:
    """Return the two-sided p value of r from the beta distribution."""
    var ab = Float64(n) / 2.0 - 1.0
    return 2.0 * beta_tails(0.5 * (1.0 - abs(r)), ab, ab)[0]


def _atanh(r: Float64) -> Float64:
    """Return atanh(r) for |r| < 1."""
    return 0.5 * log1p(2.0 * r / (1.0 - r))


def _tanh(z: Float64) -> Float64:
    """Return tanh(z)."""
    if z >= 0:
        var e = expm1(-2.0 * z)
        return -e / (e + 2.0)
    var e = expm1(2.0 * z)
    return e / (e + 2.0)


def pearson(x: List[Float64], y: List[Float64]) raises -> Correlation:
    """Return Pearson's correlation of two measures.

    Args:
        x: The first measure of each subject.
        y: The second measure of each subject.

    Returns:
        The r, its two-sided p value, and the 95 percent interval by Fisher's
        z, `tanh(atanh(r) -+ 1.96 / sqrt(n - 3))`. A perfect r has the
        interval (r, r).

    Raises:
        Error: If the lists differ in length, have fewer than 4 values or
            one that is not finite, or a measure does not vary.
    """
    _require_pairs(x, y, 4)
    var r = _r(x, y)
    var p = _r_p_value(r, len(x))
    if abs(r) == 1:
        return Correlation(r, p, r, r)
    var z = _atanh(r)
    var half = Z95 / sqrt(Float64(len(x) - 3))
    return Correlation(r, p, _tanh(z - half), _tanh(z + half))


def spearman(x: List[Float64], y: List[Float64]) raises -> Correlation:
    """Return Spearman's rank correlation of two measures.

    Args:
        x: The first measure of each subject.
        y: The second measure of each subject.

    Returns:
        The rho, Pearson's r of the midranks, and its two-sided p value. The
        interval is (-1, 1): scipy gives none.

    Raises:
        Error: If the lists differ in length, have fewer than 3 values or
            one that is not finite, or a measure does not vary.
    """
    _require_pairs(x, y, 3)
    var r = _r(midranks(x), midranks(y))
    return Correlation(r, _r_p_value(r, len(x)), -1.0, 1.0)


def _ties(values: List[Float64]) -> Tuple[Float64, Float64, Float64]:
    """Return the sums over groups of t ties of `t (t - 1) / 2`,
    `t (t - 1) (t - 2)` and `t (t - 1) (2 t + 5)`."""
    var sorted = values.copy()

    def lower(a: Float64, b: Float64) capturing -> Bool:
        return a < b

    stable_sort[lower](sorted)
    var pairs = 0.0
    var cubic = 0.0
    var spread = 0.0
    var i = 0
    while i < len(sorted):
        var j = i
        while j < len(sorted) and sorted[j] == sorted[i]:
            j += 1
        var t = Float64(j - i)
        pairs += t * (t - 1.0) / 2.0
        cubic += t * (t - 1.0) * (t - 2.0)
        spread += t * (t - 1.0) * (2.0 * t + 5.0)
        i = j
    return (pairs, cubic, spread)


def _sign(v: Float64) -> Float64:
    """Return -1, 0 or 1."""
    if v > 0:
        return 1.0
    if v < 0:
        return -1.0
    return 0.0


def kendall(x: List[Float64], y: List[Float64]) raises -> Correlation:
    """Return Kendall's tau-b of two measures.

    Args:
        x: The first measure of each subject.
        y: The second measure of each subject.

    Returns:
        The tau-b, `(C - D) / sqrt((T - Tx)(T - Ty))`, and its two-sided p
        value by the normal approximation with the tie-corrected variance.
        The interval is (-1, 1). The count of pairs is the square of the
        values.

    Raises:
        Error: If the lists differ in length, have fewer than 3 values or
            one that is not finite, or a measure does not vary.
    """
    _require_pairs(x, y, 3)
    var n = len(x)
    var difference = 0.0
    for i in range(n):  # pragma: no branch
        for j in range(i + 1, n):
            difference += _sign(x[i] - x[j]) * _sign(y[i] - y[j])
    var tx = _ties(x)
    var ty = _ties(y)
    var total = Float64(n) * Float64(n - 1) / 2.0
    if not (tx[0] < total and ty[0] < total):
        raise Error("A correlation needs values that vary")
    var tau = difference / sqrt(total - tx[0]) / sqrt(total - ty[0])
    var m = Float64(n) * Float64(n - 1)
    var variance = (
        (m * (2.0 * Float64(n) + 5.0) - tx[2] - ty[2]) / 18.0
        + 2.0 * tx[0] * ty[0] / m
        + tx[1] * ty[1] / (9.0 * m * Float64(n - 2))
    )
    var z = difference / sqrt(variance)
    return Correlation(
        max(-1.0, min(1.0, tau)), erfc(abs(z) / _SQRT_TWO), -1.0, 1.0
    )
