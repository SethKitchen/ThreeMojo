# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The log-rank test of two groups or more, as lifelines'
`multivariate_logrank_test` gives it.

At each time of an event in any group, each group expects its share at
risk of the events. The statistic is `(O - E)' V^-1 (O - E)` over all
groups but the last, with V the hypergeometric covariance of the observed
events. It has chi-square with `g - 1` degrees of freedom when the groups
have one survival. With two groups, it is the log-rank test of
`survival.log_rank_test`.
"""

from extensions.clinical.cox import chi_square_p_value
from extensions.clinical.survival import kaplan_meier, require_group
from extensions.numerics.dense import (
    DenseMatrix,
    cholesky_solve,
)
from math.sort_utils import stable_sort
from units.si import Duration64, SECOND

# The most groups of one test.
comptime MAX_GROUPS = 100


struct GroupLogRank(Copyable, Movable):
    """The log-rank test of several groups."""

    var statistic: Float64
    """The chi-square statistic."""
    var freedom: Int
    """The degrees of freedom, one less than the groups."""
    var p_value: Float64
    """The chance of a statistic this large when the groups have one
    survival."""
    var observed: List[Int]
    """The events of each group."""
    var expected: List[Float64]
    """The events that each group expects."""

    def __init__(
        out self,
        statistic: Float64,
        var observed: List[Int],
        var expected: List[Float64],
    ) raises:
        """Create a result, with its p value.

        Args:
            statistic: The statistic.
            observed: The events of each group.
            expected: The expected events of each group.

        Raises:
            Error: If there are fewer than two groups.
        """
        self.statistic = statistic
        self.freedom = len(observed) - 1
        self.p_value = chi_square_p_value(max(statistic, 0.0), self.freedom)
        self.observed = observed^
        self.expected = expected^


def log_rank_groups(
    times: List[List[Duration64]], events: List[List[Bool]]
) raises -> GroupLogRank:
    """Compare the survival of two groups or more by the log-rank test.

    Args:
        times: The times of the patients of each group.
        events: Whether each patient of each group had the event.

    Returns:
        The statistic with one degree of freedom less than the groups, its
        p value, and the observed and expected events of each group.

    Raises:
        Error: If there are not 2 to 100 groups, a group is not valid, or
            the events do not change the risk of the groups.
    """
    var g = len(times)
    if g < 2 or g > MAX_GROUPS or len(events) != g:
        raise Error("A log-rank test needs 2 to 100 groups, each with events")
    var pooled = List[Float64]()
    for k in range(g):  # pragma: no branch
        require_group(times[k], events[k])
        var curve = kaplan_meier(times[k], events[k])
        for t in curve.times:
            pooled.append(t.to(SECOND))

    def lower(a: Float64, b: Float64) capturing -> Bool:
        return a < b

    stable_sort[lower](pooled)
    var observed = List[Int](length=g, fill=0)
    var expected = List[Float64](length=g, fill=0.0)
    var covariance = DenseMatrix(g, g)
    var at = 0
    while at < len(pooled):
        var t = pooled[at]
        while at < len(pooled) and pooled[at] == t:
            at += 1
        var risk = List[Float64](length=g, fill=0.0)
        var dead = List[Float64](length=g, fill=0.0)
        var n = 0.0
        var d = 0.0
        for k in range(g):  # pragma: no branch
            for i in range(len(times[k])):  # pragma: no branch
                var s = times[k][i].to(SECOND)
                if s >= t:
                    risk[k] += 1.0
                    if s == t and events[k][i]:
                        dead[k] += 1.0
            n += risk[k]
            d += dead[k]
        for k in range(g):  # pragma: no branch
            observed[k] += Int(dead[k])
            expected[k] += d * risk[k] / n
        if n > 1:
            var scale = d * (n - d) / (n * n * (n - 1.0))
            for a in range(g):  # pragma: no branch
                for b in range(g):  # pragma: no branch
                    var cross = -risk[b]
                    if a == b:
                        cross += n
                    covariance.add(a, b, scale * risk[a] * cross)
    # All groups but the last: the last is fixed by the others.
    var m = g - 1
    var reduced = DenseMatrix(m, m)
    var gap = List[Float64]()
    for a in range(m):  # pragma: no branch
        gap.append(Float64(observed[a]) - expected[a])
        for b in range(m):  # pragma: no branch
            reduced.set(a, b, covariance.get(a, b))
    var solved: List[Float64]
    try:
        solved = cholesky_solve(reduced, gap)
    except:
        raise Error("A log-rank test needs events that change the risk")
    var statistic = 0.0
    for a in range(m):  # pragma: no branch
        statistic += gap[a] * solved[a]
    return GroupLogRank(statistic, observed^, expected^)
