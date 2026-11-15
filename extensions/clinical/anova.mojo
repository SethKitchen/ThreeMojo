# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests of two groups or more at once, as scipy gives them.

- `one_way_anova(groups)` tests whether the means of the groups differ: F
  is the variance between the group means over the variance within the
  groups, with `k - 1` and `n - k` degrees of freedom.
- `kruskal_wallis(groups)` tests whether the groups differ, by the ranks of
  all the values: H with the tie correction, against chi-square with
  `k - 1` degrees of freedom.

A test that finds a difference does not say which groups differ. Compare
the pairs next, with a correction for many tests.
"""

from extensions.clinical.cox import chi_square_p_value
from extensions.clinical.distributions import f_upper
from extensions.clinical.hypothesis import midranks
from math.sort_utils import stable_sort
from std.math import isfinite

# The most groups of one test.
comptime MAX_GROUPS = 1000


struct GroupsTest(Copyable, Movable):
    """A test of several groups."""

    var statistic: Float64
    """F, or H."""
    var freedom: Int
    """The degrees of freedom of the groups, `k - 1`."""
    var residual: Int
    """The degrees of freedom within the groups, `n - k`. 0 for H."""
    var p_value: Float64
    """The chance of a statistic this large when the groups do not
    differ."""

    def __init__(
        out self,
        statistic: Float64,
        freedom: Int,
        residual: Int,
        p_value: Float64,
    ):
        """Create a result.

        Args:
            statistic: The statistic.
            freedom: The degrees of freedom of the groups.
            residual: The degrees of freedom within the groups.
            p_value: The p value.
        """
        self.statistic = statistic
        self.freedom = freedom
        self.residual = residual
        self.p_value = p_value


def _require_groups(groups: List[List[Float64]], least: Int) raises -> Int:
    """Refuse fewer than 2 groups, a group of fewer than `least` values,
    or a value that is not finite. Return the count of values."""
    if len(groups) < 2 or len(groups) > MAX_GROUPS:
        raise Error("A test of groups needs 2 to 1000 groups")
    var n = 0
    for g in groups:  # pragma: no branch
        if len(g) < least:
            raise Error("Each group of a test needs enough values")
        for v in g:  # pragma: no branch
            if not isfinite(v):
                raise Error("The values of a test must be finite")
        n += len(g)
    return n


def one_way_anova(groups: List[List[Float64]]) raises -> GroupsTest:
    """Test whether the means of several groups differ.

    Args:
        groups: The values of each group, one value or more each, and more
            values than groups in all.

    Returns:
        F with `k - 1` and `n - k` degrees of freedom, and its p value.

    Raises:
        Error: If there are not 2 to 1000 groups, a group is empty or holds
            a value that is not finite, there are no more values than
            groups, or no group varies.
    """
    var n = _require_groups(groups, 1)
    var k = len(groups)
    if n <= k:
        raise Error("A one-way analysis needs more values than groups")
    var grand = 0.0
    for g in groups:  # pragma: no branch
        for v in g:  # pragma: no branch
            grand += v
    grand /= Float64(n)
    var between = 0.0
    var within = 0.0
    for g in groups:  # pragma: no branch
        var mean = 0.0
        for v in g:  # pragma: no branch
            mean += v
        mean /= Float64(len(g))
        between += Float64(len(g)) * (mean - grand) * (mean - grand)
        for v in g:  # pragma: no branch
            within += (v - mean) * (v - mean)
    if not (within > 0):
        raise Error("A one-way analysis needs values that vary in a group")
    var df1 = k - 1
    var df2 = n - k
    var f = (between / Float64(df1)) / (within / Float64(df2))
    return GroupsTest(f, df1, df2, f_upper(f, Float64(df1), Float64(df2)))


def kruskal_wallis(groups: List[List[Float64]]) raises -> GroupsTest:
    """Test whether several groups differ, by the Kruskal-Wallis test.

    Args:
        groups: The values of each group, one value or more each.

    Returns:
        H with the tie correction and `k - 1` degrees of freedom, and its
        p value.

    Raises:
        Error: If there are not 2 to 1000 groups, a group is empty or holds
            a value that is not finite, or all the values tie.
    """
    var n = _require_groups(groups, 1)
    var pooled = List[Float64]()
    for g in groups:  # pragma: no branch
        for v in g:  # pragma: no branch
            pooled.append(v)
    var ranks = midranks(pooled)
    var h = 0.0
    var at = 0
    for g in groups:  # pragma: no branch
        var total = 0.0
        for _ in range(len(g)):  # pragma: no branch
            total += ranks[at]
            at += 1
        h += total * total / Float64(len(g))
    var count = Float64(n)
    h = 12.0 / (count * (count + 1.0)) * h - 3.0 * (count + 1.0)
    # The tie correction: 1 - sum(t^3 - t) / (n^3 - n).
    var sorted = pooled.copy()

    def lower(a: Float64, b: Float64) capturing -> Bool:
        return a < b

    stable_sort[lower](sorted)
    var ties = 0.0
    var i = 0
    while i < n:
        var j = i
        while j < n and sorted[j] == sorted[i]:
            j += 1
        var t = Float64(j - i)
        ties += t * t * t - t
        i = j
    var correction = 1.0 - ties / (count * count * count - count)
    if not (correction > 0):
        raise Error("A rank test needs values that do not all tie")
    h /= correction
    var df = len(groups) - 1
    return GroupsTest(h, df, 0, chi_square_p_value(max(h, 0.0), df))
