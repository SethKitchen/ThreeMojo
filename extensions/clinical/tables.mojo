# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests of tables of counts, as scipy and statsmodels give them.

- `fisher_exact(a, b, c, d)` gives the odds ratio of a two-by-two table and
  the two-sided p value of Fisher's exact test: the chance of the tables
  with the same margins that are no more likely than this one. The
  probabilities come from the ratio of each to the next, from the most
  likely table, so they need no factorials. A table counts as no more
  likely within a relative 1e-7, as R counts it.
- `chi_square_test(table)` tests the independence of the rows and the
  columns of a table, without a continuity correction.
  `yates_chi_square_test` tests a two-by-two table with Yates's
  correction.
- `mcnemar_exact(b, c)` and `mcnemar_chi_square(b, c)` test paired yes or
  no results by their discordant pairs: exactly by the binomial
  distribution, or by chi-square with the continuity correction.
"""

from extensions.clinical.cox import chi_square_p_value
from extensions.clinical.distributions import beta_tails
from std.math import floor, inf, nan

# The most rows or columns of a table.
comptime MAX_SIDE = 100
# A table is no more likely than the observed one within this ratio.
comptime _TIE = 1.0 + 1e-7


struct FisherTest(Copyable, Movable):
    """Fisher's exact test of a two-by-two table."""

    var odds_ratio: Float64
    """`a d / (b c)`: infinite when b or c is 0, and not a number when a
    margin is 0."""
    var p_value: Float64
    """The two-sided p value."""

    def __init__(out self, odds_ratio: Float64, p_value: Float64):
        """Create a result.

        Args:
            odds_ratio: The odds ratio of the table.
            p_value: The two-sided p value.
        """
        self.odds_ratio = odds_ratio
        self.p_value = p_value


struct TableTest(Copyable, Movable):
    """A chi-square test of a table."""

    var statistic: Float64
    """The chi-square statistic."""
    var freedom: Int
    """The degrees of freedom."""
    var p_value: Float64
    """The chance of a statistic this large when the null holds."""

    def __init__(out self, statistic: Float64, freedom: Int) raises:
        """Create a result, with its p value.

        Args:
            statistic: The statistic, 0 or more.
            freedom: The degrees of freedom, 1 or more.

        Raises:
            Error: If the freedom is out of range.
        """
        self.statistic = statistic
        self.freedom = freedom
        self.p_value = chi_square_p_value(statistic, freedom)


def _require_cells(a: Int, b: Int, c: Int, d: Int) raises:
    """Refuse a cell below 0."""
    if a < 0 or b < 0 or c < 0 or d < 0:
        raise Error("The cells of a table must be 0 or more")


def fisher_exact(a: Int, b: Int, c: Int, d: Int) raises -> FisherTest:
    """Return Fisher's exact test of a two-by-two table.

    The table has the rows (a, b) and (c, d).

    Args:
        a: The first row, first column.
        b: The first row, second column.
        c: The second row, first column.
        d: The second row, second column.

    Returns:
        The odds ratio and the two-sided p value. A table with a margin of
        0 has a p value of 1.

    Raises:
        Error: If a cell is below 0.
    """
    _require_cells(a, b, c, d)
    var n1 = a + b
    var n2 = c + d
    var n = a + c
    if n1 == 0 or n2 == 0 or n == 0 or b + d == 0:
        return FisherTest(nan[DType.float64](), 1.0)
    var odds = inf[DType.float64]()
    if b > 0 and c > 0:
        odds = Float64(a * d) / Float64(b * c)
    var low = max(0, n - n2)
    var high = min(n, n1)
    var mode = Int(
        floor(Float64(n + 1) * Float64(n1 + 1) / Float64(n1 + n2 + 2))
    )
    var weights = List[Float64](length=high - low + 1, fill=0.0)
    weights[mode - low] = 1.0
    for x in range(mode, high):
        weights[x + 1 - low] = (
            weights[x - low]
            * Float64((n1 - x) * (n - x))
            / Float64((x + 1) * (n2 - n + x + 1))
        )
    var x = mode
    while x > low:
        weights[x - 1 - low] = (
            weights[x - low]
            * Float64(x * (n2 - n + x))
            / Float64((n1 - x + 1) * (n - x + 1))
        )
        x -= 1
    var total = 0.0
    for w in weights:  # pragma: no branch
        total += w
    var limit = weights[a - low] * _TIE
    var tail = 0.0
    for w in weights:  # pragma: no branch
        if w <= limit:
            tail += w
    return FisherTest(odds, min(1.0, tail / total))


def chi_square_test(table: List[List[Int]]) raises -> TableTest:
    """Test the independence of the rows and columns of a table.

    Args:
        table: The counts, one list for each row. From 2 to 100 rows and
            columns, each count 0 or more.

    Returns:
        `sum((O - E)^2 / E)` with `(r - 1)(c - 1)` degrees of freedom, with
        no continuity correction.

    Raises:
        Error: If the table is not a rectangle of 2 to 100 rows and
            columns, a count is below 0, or a row or a column sums to 0.
    """
    var rows = len(table)
    if rows < 2 or rows > MAX_SIDE:
        raise Error("A table has from 2 to 100 rows and columns")
    var cols = len(table[0])
    if cols < 2 or cols > MAX_SIDE:
        raise Error("A table has from 2 to 100 rows and columns")
    var row_sums = List[Float64](length=rows, fill=0.0)
    var col_sums = List[Float64](length=cols, fill=0.0)
    var total = 0.0
    for i in range(rows):  # pragma: no branch
        if len(table[i]) != cols:
            raise Error("Each row of a table needs one count for each column")
        for j in range(cols):  # pragma: no branch
            var v = table[i][j]
            if v < 0:
                raise Error("The cells of a table must be 0 or more")
            row_sums[i] += Float64(v)
            col_sums[j] += Float64(v)
            total += Float64(v)
    for s in row_sums:  # pragma: no branch
        if s == 0:
            raise Error("A table needs counts in each row and each column")
    for s in col_sums:  # pragma: no branch
        if s == 0:
            raise Error("A table needs counts in each row and each column")
    var statistic = 0.0
    for i in range(rows):  # pragma: no branch
        for j in range(cols):  # pragma: no branch
            var e = row_sums[i] * col_sums[j] / total
            var gap = Float64(table[i][j]) - e
            statistic += gap * gap / e
    return TableTest(statistic, (rows - 1) * (cols - 1))


def yates_chi_square_test(a: Int, b: Int, c: Int, d: Int) raises -> TableTest:
    """Test a two-by-two table by chi-square with Yates's correction.

    Each count moves a half toward its expected count, or all the way when
    it is nearer, as scipy moves it.

    Args:
        a: The first row, first column.
        b: The first row, second column.
        c: The second row, first column.
        d: The second row, second column.

    Returns:
        The corrected statistic with 1 degree of freedom.

    Raises:
        Error: If a cell is below 0, or a row or a column sums to 0.
    """
    _require_cells(a, b, c, d)
    var cells: List[Int] = [a, b, c, d]
    var rows: List[Float64] = [Float64(a + b), Float64(c + d)]
    var cols: List[Float64] = [Float64(a + c), Float64(b + d)]
    if rows[0] == 0 or rows[1] == 0 or cols[0] == 0 or cols[1] == 0:
        raise Error("A table needs counts in each row and each column")
    var total = rows[0] + rows[1]
    var statistic = 0.0
    for k in range(4):  # pragma: no branch
        var e = rows[k // 2] * cols[k % 2] / total
        var gap = abs(Float64(cells[k]) - e)
        var moved = max(0.0, gap - 0.5)
        statistic += moved * moved / e
    return TableTest(statistic, 1)


def _require_pairs(b: Int, c: Int) raises:
    """Refuse discordant counts below 0."""
    if b < 0 or c < 0:
        raise Error("The discordant counts must be 0 or more")


def mcnemar_exact(b: Int, c: Int) raises -> Float64:
    """Return the exact two-sided p value of McNemar's test.

    Args:
        b: The pairs with yes first and no second.
        c: The pairs with no first and yes second.

    Returns:
        `min(1, 2 P(X <= min(b, c)))` with X binomial of `b + c` trials of
        a half. 1 when there is no discordant pair.

    Raises:
        Error: If a count is below 0.
    """
    _require_pairs(b, c)
    var n = b + c
    if n == 0:
        return 1.0
    var k = min(b, c)
    # P(X <= k) = I_(1/2)(n - k, k + 1).
    var lower = beta_tails(0.5, Float64(n - k), Float64(k + 1))[0]
    return min(1.0, 2.0 * lower)


def mcnemar_chi_square(b: Int, c: Int) raises -> TableTest:
    """Return McNemar's chi-square test with the continuity correction.

    Args:
        b: The pairs with yes first and no second.
        c: The pairs with no first and yes second.

    Returns:
        `(|b - c| - 1)^2 / (b + c)` with 1 degree of freedom, as statsmodels
        gives it.

    Raises:
        Error: If a count is below 0, or there is no discordant pair.
    """
    _require_pairs(b, c)
    if b + c == 0:
        raise Error("McNemar's chi-square needs a discordant pair")
    var gap = Float64(abs(b - c)) - 1.0
    return TableTest(gap * gap / Float64(b + c), 1)
