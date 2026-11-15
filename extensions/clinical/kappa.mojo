# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Cohen's kappa: the agreement of two raters on categories, beyond the
agreement that chance gives.

Two raters, such as two radiologists, put each subject in one of k
categories. Their table holds the subjects that rater A put in category
i (the row) and rater B in category j (the column).

- `cohens_kappa(table)` counts only exact agreement.
- `linear_weighted_kappa(table)` and `quadratic_weighted_kappa(table)` give
  part credit to near categories, for ordered categories such as grades:
  the agreement weight of categories i and j is `1 - |i - j| / (k - 1)`,
  or `1 - ((i - j) / (k - 1))^2`.

Each gives kappa with the large-sample standard error of Fleiss, Cohen
and Everitt (1969), its 95 percent interval, and the test that kappa is
0, with the standard error under no agreement beyond chance, as
statsmodels gives them.
"""

from extensions.clinical.survival import Z95
from extensions.numerics.dense import DenseMatrix
from std.math import erfc, sqrt

comptime _SQRT_TWO = 1.4142135623730951
# The most categories of one table.
comptime MAX_CATEGORIES = 100


struct Kappa(Copyable, Movable):
    """A kappa with its interval and test."""

    var value: Float64
    """Kappa: 1 for full agreement, 0 for chance agreement."""
    var standard_error: Float64
    """The standard error of kappa."""
    var null_error: Float64
    """The standard error of kappa when the agreement is chance only."""
    var z: Float64
    """Kappa over its null standard error."""
    var p_value: Float64
    """The two-sided chance of a z this far from 0 under chance agreement."""
    var lower: Float64
    """The low end of the 95 percent interval."""
    var upper: Float64
    """The high end of the 95 percent interval."""

    def __init__(
        out self, value: Float64, standard_error: Float64, null_error: Float64
    ):
        """Create a result, with its test and interval.

        Args:
            value: Kappa.
            standard_error: Its standard error.
            null_error: Its standard error under chance agreement.
        """
        self.value = value
        self.standard_error = standard_error
        self.null_error = null_error
        self.z = value / null_error
        self.p_value = erfc(abs(self.z) / _SQRT_TWO)
        self.lower = value - Z95 * standard_error
        self.upper = value + Z95 * standard_error


def _require_table(table: List[List[Int]]) raises -> Int:
    """Refuse a table that is not square, from 2 to 100 categories, with
    counts of 0 or more and one or more in all. Return the categories."""
    var k = len(table)
    if k < 2 or k > MAX_CATEGORIES:
        raise Error("A kappa table has from 2 to 100 categories")
    var total = 0
    for row in table:  # pragma: no branch
        if len(row) != k:
            raise Error("A kappa table must be square")
        for v in row:  # pragma: no branch
            if v < 0:
                raise Error("The counts of a kappa table must be 0 or more")
            total += v
    if total == 0:
        raise Error("A kappa table needs one subject or more")
    return k


def _kappa(table: List[List[Int]], weights: DenseMatrix) raises -> Kappa:
    """Return the kappa of a table with agreement weights."""
    var k = len(table)
    var n = 0.0
    for row in table:  # pragma: no branch
        for v in row:  # pragma: no branch
            n += Float64(v)
    var rows = List[Float64](length=k, fill=0.0)
    var cols = List[Float64](length=k, fill=0.0)
    var observed = 0.0
    for i in range(k):  # pragma: no branch
        for j in range(k):  # pragma: no branch
            var p = Float64(table[i][j]) / n
            rows[i] += p
            cols[j] += p
            observed += weights.get(i, j) * p
    var expected = 0.0
    for i in range(k):  # pragma: no branch
        for j in range(k):  # pragma: no branch
            expected += weights.get(i, j) * rows[i] * cols[j]
    if not (expected < 1):
        raise Error("A kappa table needs raters who do not agree by chance")
    var kappa = (observed - expected) / (1.0 - expected)
    # The mean weight of each row against the columns, and of each column.
    var row_weight = List[Float64](length=k, fill=0.0)
    var col_weight = List[Float64](length=k, fill=0.0)
    for i in range(k):  # pragma: no branch
        for j in range(k):  # pragma: no branch
            row_weight[i] += cols[j] * weights.get(i, j)
            col_weight[j] += rows[i] * weights.get(i, j)
    var spread = 0.0
    var null = 0.0
    for i in range(k):  # pragma: no branch
        for j in range(k):  # pragma: no branch
            var mean = row_weight[i] + col_weight[j]
            var a = weights.get(i, j) - mean * (1.0 - kappa)
            spread += Float64(table[i][j]) / n * a * a
            var b = weights.get(i, j) - mean
            null += rows[i] * cols[j] * b * b
    var scale = 1.0 / ((1.0 - expected) * (1.0 - expected) * n)
    var shift = kappa - expected * (1.0 - kappa)
    var variance = (spread - shift * shift) * scale
    var null_variance = (null - expected * expected) * scale
    return Kappa(kappa, sqrt(max(variance, 0.0)), sqrt(null_variance))


def cohens_kappa(table: List[List[Int]]) raises -> Kappa:
    """Return Cohen's kappa of exact agreement.

    Args:
        table: The k x k counts: rater A's category by row, rater B's by
            column.

    Returns:
        Kappa, `(p_o - p_e) / (1 - p_e)`, with its errors, test and
        interval.

    Raises:
        Error: If the table is not square, has not 2 to 100 categories, has
            a count below 0 or no subject, or its margins agree by chance
            alone.
    """
    var k = _require_table(table)
    var weights = DenseMatrix(k, k)
    for i in range(k):  # pragma: no branch
        weights.set(i, i, 1.0)
    return _kappa(table, weights)


def linear_weighted_kappa(table: List[List[Int]]) raises -> Kappa:
    """Return the linear weighted kappa of ordered categories.

    Args:
        table: The k x k counts: rater A's category by row, rater B's by
            column, in order.

    Returns:
        Kappa with the agreement weights `1 - |i - j| / (k - 1)`.

    Raises:
        Error: If the table is not valid, as for `cohens_kappa`.
    """
    var k = _require_table(table)
    var weights = DenseMatrix(k, k)
    for i in range(k):  # pragma: no branch
        for j in range(k):  # pragma: no branch
            weights.set(i, j, 1.0 - Float64(abs(i - j)) / Float64(k - 1))
    return _kappa(table, weights)


def quadratic_weighted_kappa(table: List[List[Int]]) raises -> Kappa:
    """Return the quadratic weighted kappa of ordered categories.

    Args:
        table: The k x k counts: rater A's category by row, rater B's by
            column, in order.

    Returns:
        Kappa with the agreement weights `1 - ((i - j) / (k - 1))^2`.

    Raises:
        Error: If the table is not valid, as for `cohens_kappa`.
    """
    var k = _require_table(table)
    var weights = DenseMatrix(k, k)
    for i in range(k):  # pragma: no branch
        for j in range(k):  # pragma: no branch
            var d = Float64(i - j) / Float64(k - 1)
            weights.set(i, j, 1.0 - d * d)
    return _kappa(table, weights)
