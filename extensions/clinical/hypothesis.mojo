# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Two-sided tests of two groups, or of pairs, as scipy gives them.

- `student_t_test` and `welch_t_test` compare the means of two groups,
  with a pooled variance or with a variance for each and Welch's degrees
  of freedom. `paired_t_test` compares the two values of each pair. Each
  gives t, the degrees of freedom, the p value and the 95 percent interval
  of the difference of the means.
- `mann_whitney` compares two groups by ranks: the Mann-Whitney U of the
  first group, with a normal approximation, a tie correction and a
  continuity correction.
- `wilcoxon` compares pairs by the signed ranks of their differences. It
  drops zero differences, corrects the variance for ties, and has no
  continuity correction.
- `midranks` gives the rank of each value, a tie taking the mean rank.

A value is a plain number in a unit that the caller chooses, such as a
blood pressure in mmHg. A difference is in that unit.
"""

from extensions.clinical.distributions import (
    student_t_quantile,
    student_t_upper,
)
from math.sort_utils import stable_sort
from std.math import erfc, isfinite, sqrt

comptime _SQRT_TWO = 1.4142135623730951


def midranks(values: List[Float64]) -> List[Float64]:
    """Return the rank of each value from 1, a tie taking the mean rank.

    Args:
        values: The values.

    Returns:
        The rank of each value, in the order of the values.
    """
    var n = len(values)
    var order = List[Int]()
    for i in range(n):
        order.append(i)

    def before(a: Int, b: Int) capturing -> Bool:
        return values[a] < values[b]

    stable_sort[before](order)
    var ranks = List[Float64](length=n, fill=0.0)
    var i = 0
    while i < n:
        var j = i
        while j < n and values[order[j]] == values[order[i]]:
            j += 1
        var rank = 0.5 * Float64(i + j - 1) + 1.0
        for k in range(i, j):  # pragma: no branch
            ranks[order[k]] = rank
        i = j
    return ranks^


struct TTest(Copyable, Movable):
    """A two-sided t test of a difference of means."""

    var statistic: Float64
    """The t value: the difference over its standard error."""
    var freedom: Float64
    """The degrees of freedom."""
    var p_value: Float64
    """The chance of a t this far from 0 when the means are equal."""
    var difference: Float64
    """The difference of the means, first less second."""
    var lower: Float64
    """The low end of the 95 percent interval of the difference."""
    var upper: Float64
    """The high end of the 95 percent interval of the difference."""

    def __init__(
        out self, difference: Float64, error: Float64, freedom: Float64
    ) raises:
        """Create a test from a difference, its error and its freedom.

        Args:
            difference: The difference of the means.
            error: Its standard error. Positive.
            freedom: The degrees of freedom. Positive.

        Raises:
            Error: If the error is 0, or the freedom is out of range.
        """
        if not (error > 0):
            raise Error("A t test needs values that vary")
        self.statistic = difference / error
        self.freedom = freedom
        self.p_value = 2.0 * student_t_upper(abs(self.statistic), freedom)
        var half = student_t_quantile(0.975, freedom) * error
        self.difference = difference
        self.lower = difference - half
        self.upper = difference + half


def _require_group(values: List[Float64]) raises:
    """Refuse a group of fewer than two values, or one that is not
    finite."""
    if len(values) < 2:
        raise Error("A test needs two values or more in each group")
    for v in values:  # pragma: no branch
        if not isfinite(v):
            raise Error("The values of a test must be finite")


def _mean_and_variance(values: List[Float64]) -> Tuple[Float64, Float64]:
    """Return the mean and the sample variance."""
    var n = Float64(len(values))
    var total = 0.0
    for v in values:  # pragma: no branch
        total += v
    var mean = total / n
    var squares = 0.0
    for v in values:  # pragma: no branch
        squares += (v - mean) * (v - mean)
    return (mean, squares / (n - 1.0))


def student_t_test(first: List[Float64], second: List[Float64]) raises -> TTest:
    """Compare the means of two groups with a pooled variance.

    Args:
        first: The values of the first group, two or more.
        second: The values of the second group, two or more.

    Returns:
        The test, with `n1 + n2 - 2` degrees of freedom.

    Raises:
        Error: If a group has fewer than two values or one that is not
            finite, or the values do not vary.
    """
    _require_group(first)
    _require_group(second)
    var a = _mean_and_variance(first)
    var b = _mean_and_variance(second)
    var n1 = Float64(len(first))
    var n2 = Float64(len(second))
    var freedom = n1 + n2 - 2.0
    var pooled = ((n1 - 1.0) * a[1] + (n2 - 1.0) * b[1]) / freedom
    return TTest(a[0] - b[0], sqrt(pooled * (1.0 / n1 + 1.0 / n2)), freedom)


def welch_t_test(first: List[Float64], second: List[Float64]) raises -> TTest:
    """Compare the means of two groups, each with its own variance.

    Args:
        first: The values of the first group, two or more.
        second: The values of the second group, two or more.

    Returns:
        The test, with Welch's degrees of freedom.

    Raises:
        Error: If a group has fewer than two values or one that is not
            finite, or the values do not vary.
    """
    _require_group(first)
    _require_group(second)
    var a = _mean_and_variance(first)
    var b = _mean_and_variance(second)
    var n1 = Float64(len(first))
    var n2 = Float64(len(second))
    var va = a[1] / n1
    var vb = b[1] / n2
    var total = va + vb
    if not (total > 0):
        raise Error("A t test needs values that vary")
    var freedom = total * total / (va * va / (n1 - 1.0) + vb * vb / (n2 - 1.0))
    return TTest(a[0] - b[0], sqrt(total), freedom)


def _differences(
    first: List[Float64], second: List[Float64]
) raises -> List[Float64]:
    """Return the differences of pairs, first less second."""
    if len(first) != len(second):
        raise Error("A paired test needs one second value for each first")
    _require_group(first)
    _require_group(second)
    var out = List[Float64]()
    for i in range(len(first)):  # pragma: no branch
        out.append(first[i] - second[i])
    return out^


def paired_t_test(first: List[Float64], second: List[Float64]) raises -> TTest:
    """Compare the two values of each pair.

    Args:
        first: The first value of each pair, such as before a treatment.
        second: The second value of each pair, such as after it.

    Returns:
        The test of the mean difference, first less second, with `n - 1`
        degrees of freedom.

    Raises:
        Error: If the lists differ in length, have fewer than two values or
            one that is not finite, or the differences do not vary.
    """
    var d = _differences(first, second)
    var m = _mean_and_variance(d)
    var n = Float64(len(d))
    return TTest(m[0], sqrt(m[1] / n), n - 1.0)


struct RankTest(Copyable, Movable):
    """A two-sided rank test by the normal approximation."""

    var statistic: Float64
    """The rank statistic: U, or the smaller signed rank sum."""
    var z: Float64
    """The standardized statistic."""
    var p_value: Float64
    """The chance of a z this far from 0 when the groups do not differ."""

    def __init__(out self, statistic: Float64, z: Float64):
        """Create a test.

        Args:
            statistic: The rank statistic.
            z: The standardized statistic.
        """
        self.statistic = statistic
        self.z = z
        self.p_value = min(1.0, erfc(abs(z) / _SQRT_TWO))


def _tie_term(ranks: List[Float64]) -> Float64:
    """Return the sum of `t^3 - t` over the groups of tied ranks."""
    var sorted = ranks.copy()

    def lower(a: Float64, b: Float64) capturing -> Bool:
        return a < b

    stable_sort[lower](sorted)
    var term = 0.0
    var i = 0
    while i < len(sorted):
        var j = i
        while j < len(sorted) and sorted[j] == sorted[i]:
            j += 1
        var t = Float64(j - i)
        term += t * t * t - t
        i = j
    return term


def mann_whitney(
    first: List[Float64], second: List[Float64]
) raises -> RankTest:
    """Compare two groups by the Mann-Whitney U test.

    Args:
        first: The values of the first group, one or more.
        second: The values of the second group, one or more.

    Returns:
        U of the first group, and its two-sided test by the normal
        approximation, with the tie and continuity corrections.

    Raises:
        Error: If a group is empty or has a value that is not finite, or
            all the values tie.
    """
    if len(first) == 0 or len(second) == 0:
        raise Error("A rank test needs one value or more in each group")
    var pooled = first.copy()
    for v in second:  # pragma: no branch
        pooled.append(v)
    for v in pooled:  # pragma: no branch
        if not isfinite(v):
            raise Error("The values of a test must be finite")
    var ranks = midranks(pooled)
    var n1 = Float64(len(first))
    var n2 = Float64(len(second))
    var n = n1 + n2
    var r1 = 0.0
    for i in range(len(first)):  # pragma: no branch
        r1 += ranks[i]
    var u = r1 - n1 * (n1 + 1.0) / 2.0
    var spread = (
        n1 * n2 / 12.0 * ((n + 1.0) - _tie_term(ranks) / (n * (n - 1.0)))
    )
    if not (spread > 0):
        raise Error("A rank test needs values that do not all tie")
    var gap = u - n1 * n2 / 2.0
    if gap > 0:
        gap -= 0.5
    elif gap < 0:
        gap += 0.5
    return RankTest(u, gap / sqrt(spread))


def wilcoxon(first: List[Float64], second: List[Float64]) raises -> RankTest:
    """Compare pairs by the Wilcoxon signed-rank test.

    Args:
        first: The first value of each pair.
        second: The second value of each pair.

    Returns:
        The smaller of the sums of the ranks of the positive and the
        negative differences, and its two-sided test by the normal
        approximation, with the tie correction.

    Raises:
        Error: If the lists differ in length, have fewer than two values or
            one that is not finite, or every difference is 0.
    """
    var all = _differences(first, second)
    var d = List[Float64]()
    var sizes = List[Float64]()
    for v in all:  # pragma: no branch
        if v != 0:
            d.append(v)
            sizes.append(abs(v))
    if len(d) == 0:
        raise Error("A signed-rank test needs a difference that is not 0")
    var ranks = midranks(sizes)
    var plus = 0.0
    var minus = 0.0
    for i in range(len(d)):  # pragma: no branch
        if d[i] > 0:
            plus += ranks[i]
        else:
            minus += ranks[i]
    var n = Float64(len(d))
    var mean = n * (n + 1.0) / 4.0
    var variance = (
        n * (n + 1.0) * (2.0 * n + 1.0) / 24.0 - _tie_term(ranks) / 48.0
    )
    var smaller = min(plus, minus)
    return RankTest(smaller, (smaller - mean) / sqrt(variance))
