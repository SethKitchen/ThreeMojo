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

`fleiss_kappa(table)` measures the agreement of many raters, such as six
pathologists who each grade every slide. Its table holds, for each
subject, how many raters put it in each category.
"""

from extensions.numerics.dense import DenseMatrix
from std.math import nan, sqrt
from extensions.numerics.distributions import normal_two_sided, wald_interval

# The most categories of one table.
comptime MAX_CATEGORIES = 100
# The most subjects of a table of many raters.
comptime MAX_SUBJECTS = 100000


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
        self.p_value = normal_two_sided(self.z)
        var band = wald_interval(value, standard_error)
        self.lower = band[0]
        self.upper = band[1]


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


struct FleissKappa(Copyable, Movable):
    """Fleiss' kappa of many raters, with its test."""

    var value: Float64
    """Kappa: 1 for full agreement, 0 for chance agreement."""
    var null_error: Float64
    """The standard error of kappa when the agreement is chance only, by
    Fleiss, Nee and Landis (1979)."""
    var z: Float64
    """Kappa over its null standard error."""
    var p_value: Float64
    """The two-sided chance of a z this far from 0 under chance agreement."""
    var free_marginal: Float64
    """Randolph's free-marginal kappa, with chance agreement 1 over the
    categories."""
    var categories: List[Float64]
    """The kappa of each category, by Fleiss (1971). Not a number for a
    category that no rater chose."""

    def __init__(out self):
        """Create an empty result."""
        self.value = 0.0
        self.null_error = 0.0
        self.z = 0.0
        self.p_value = 1.0
        self.free_marginal = 0.0
        self.categories = List[Float64]()


def fleiss_kappa(table: List[List[Int]]) raises -> FleissKappa:
    """Return Fleiss' kappa of many raters on categories.

    Each subject has the same number of ratings, from two raters or more.
    Each rater can be another person for each subject.

    Args:
        table: One row for each subject, of the number of raters who put
            it in each category.

    Returns:
        Kappa, `(P - Pe) / (1 - Pe)`, with its null error, z, p value, the
        free-marginal kappa and the kappa of each category.

    Raises:
        Error: If there are not 1 to 100000 subjects of 2 to 100
            categories, a count is below 0, the subjects have not one
            number of ratings of 2 or more, or every rating is in one
            category.
    """
    var subjects = len(table)
    if subjects < 1 or subjects > MAX_SUBJECTS:
        raise Error("A table of many raters has from 1 to 100000 subjects")
    var k = len(table[0])
    if k < 2 or k > MAX_CATEGORIES:
        raise Error("A table of many raters has from 2 to 100 categories")
    var raters = -1
    var totals = List[Float64](length=k, fill=0.0)
    var agree = 0.0
    for row in table:  # pragma: no branch
        if len(row) != k:
            raise Error("Each subject needs a count for each category")
        var count = 0
        var pairs = 0.0
        for j in range(k):  # pragma: no branch
            if row[j] < 0:
                raise Error("The counts of a table must be 0 or more")
            count += row[j]
            pairs += Float64(row[j]) * Float64(row[j] - 1)
            totals[j] += Float64(row[j])
        if raters < 0:
            raters = count
        if count != raters or count < 2:
            raise Error(
                "Each subject needs the same number of ratings, 2 or more"
            )
        agree += pairs
    var n = Float64(raters)
    var ratings = Float64(subjects) * n
    var observed = agree / (ratings * (n - 1.0))
    var expected = 0.0
    var spread = 0.0
    var skew = 0.0
    var shares = List[Float64]()
    for j in range(k):  # pragma: no branch
        var p = totals[j] / ratings
        shares.append(p)
        expected += p * p
        spread += p * (1.0 - p)
        skew += p * (1.0 - p) * (1.0 - 2.0 * p)
    if not (expected < 1):
        raise Error("A kappa of many raters needs ratings in two categories")
    var out = FleissKappa()
    out.value = (observed - expected) / (1.0 - expected)
    var chance = 1.0 / Float64(k)
    out.free_marginal = (observed - chance) / (1.0 - chance)
    out.null_error = (
        sqrt(2.0)
        / (spread * sqrt(ratings * (n - 1.0)))
        * sqrt(spread * spread - skew)
    )
    out.z = out.value / out.null_error
    out.p_value = normal_two_sided(out.z)
    for j in range(k):  # pragma: no branch
        var p = shares[j]
        if not (p > 0):
            out.categories.append(nan[DType.float64]())
            continue
        var apart = 0.0
        for row in table:  # pragma: no branch
            apart += Float64(row[j]) * Float64(raters - row[j])
        out.categories.append(
            1.0 - apart / (ratings * (n - 1.0) * p * (1.0 - p))
        )
    return out^
