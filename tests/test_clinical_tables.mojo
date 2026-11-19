# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fisher's exact test, chi-square tests of tables, and McNemar's test.

`assets/hypothesis/tables_expected.txt` holds the results of scipy 1.18.1
and statsmodels 0.15.0. See `assets/hypothesis/make_tables.py`.
"""

from extensions.clinical.tables import (
    chi_square_test,
    fisher_exact,
    mcnemar_chi_square,
    mcnemar_exact,
    yates_chi_square_test,
)
from std.math import isinf, isnan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def _rows() raises -> List[List[Float64]]:
    var out = List[List[Float64]]()
    var text = open("assets/hypothesis/tables_expected.txt", "r").read()
    for line in text.splitlines():
        var words = String(line).split(" ")
        var row = List[Float64]()
        row.append(0.0)
        for k in range(1, len(words)):
            row.append(atof(String(words[k])))
        if String(words[0]) == "fisher":
            row[0] = 1.0
        elif String(words[0]) == "chi2":
            row[0] = 2.0
        elif String(words[0]) == "yates":
            row[0] = 3.0
        else:
            row[0] = 4.0
        out.append(row^)
    return out^


def test_against_references() raises:
    var checked = 0
    for row in _rows():
        if row[0] == 1.0:
            var r = fisher_exact(
                Int(row[1]), Int(row[2]), Int(row[3]), Int(row[4])
            )
            if isinf(row[5]):
                assert_true(isinf(r.odds_ratio))
            else:
                assert_almost_equal(r.odds_ratio, row[5], rtol=1e-15)
            assert_almost_equal(r.p_value, row[6], rtol=1e-12)
        elif row[0] == 2.0:
            var rows = Int(row[1])
            var cols = Int(row[2])
            var table = List[List[Int]]()
            for i in range(rows):
                var line = List[Int]()
                for j in range(cols):
                    line.append(Int(row[3 + i * cols + j]))
                table.append(line^)
            var at = 3 + rows * cols
            var r = chi_square_test(table)
            assert_almost_equal(r.statistic, row[at], rtol=1e-13)
            assert_equal(r.freedom, Int(row[at + 1]))
            assert_almost_equal(r.p_value, row[at + 2], rtol=1e-11)
        elif row[0] == 3.0:
            var r = yates_chi_square_test(
                Int(row[1]), Int(row[2]), Int(row[3]), Int(row[4])
            )
            assert_almost_equal(r.statistic, row[5], rtol=1e-13)
            assert_almost_equal(r.p_value, row[6], rtol=1e-11)
        else:
            var b = Int(row[1])
            var c = Int(row[2])
            assert_almost_equal(mcnemar_exact(b, c), row[3], rtol=1e-12)
            var r = mcnemar_chi_square(b, c)
            assert_almost_equal(r.statistic, row[4], rtol=1e-14)
            assert_almost_equal(r.p_value, row[5], rtol=1e-11)
        checked += 1
    assert_equal(checked, 14)


def test_by_hand() raises:
    # The most extreme of a 3 + 3 table: a p value of 2 / 20.
    var extreme = fisher_exact(3, 0, 0, 3)
    assert_true(isinf(extreme.odds_ratio))
    assert_almost_equal(extreme.p_value, 0.1, rtol=1e-14)
    # A margin of 0: no odds ratio, and a p value of 1.
    var cases: List[List[Int]] = [
        [0, 0, 2, 3],
        [2, 3, 0, 0],
        [0, 2, 0, 3],
        [2, 0, 3, 0],
    ]
    for t in cases:
        var r = fisher_exact(t[0], t[1], t[2], t[3])
        assert_true(isnan(r.odds_ratio))
        assert_equal(r.p_value, 1.0)
    # An empty second-row first cell: an infinite odds ratio. And a table
    # of one and one, whose most likely table is the last: scipy's p values.
    var lopsided = fisher_exact(3, 2, 0, 3)
    assert_true(isinf(lopsided.odds_ratio))
    assert_almost_equal(lopsided.p_value, 0.19642857142857145, rtol=1e-14)
    assert_equal(fisher_exact(1, 0, 0, 1).p_value, 1.0)
    # No discordant pair.
    assert_equal(mcnemar_exact(0, 0), 1.0)


def test_refusals() raises:
    var bad: List[List[Int]] = [
        [-1, 1, 1, 1],
        [1, -1, 1, 1],
        [1, 1, -1, 1],
        [1, 1, 1, -1],
    ]
    for t in bad:
        with assert_raises(contains="0 or more"):
            _ = fisher_exact(t[0], t[1], t[2], t[3])
        with assert_raises(contains="0 or more"):
            _ = yates_chi_square_test(t[0], t[1], t[2], t[3])
    var empty: List[List[Int]] = [
        [0, 0, 1, 1],
        [1, 1, 0, 0],
        [0, 1, 0, 1],
        [1, 0, 1, 0],
    ]
    for t in empty:
        with assert_raises(contains="each row and each column"):
            _ = yates_chi_square_test(t[0], t[1], t[2], t[3])
    var one_row: List[List[Int]] = [[1, 2]]
    with assert_raises(contains="2 to 100 rows"):
        _ = chi_square_test(one_row)
    var one_col: List[List[Int]] = [[1], [2]]
    with assert_raises(contains="2 to 100 rows"):
        _ = chi_square_test(one_col)
    var tall = List[List[Int]]()
    for _ in range(101):
        tall.append([1, 1])
    with assert_raises(contains="2 to 100 rows"):
        _ = chi_square_test(tall)
    var wide = List[List[Int]]()
    for _ in range(2):
        wide.append(List[Int](length=101, fill=1))
    with assert_raises(contains="2 to 100 rows"):
        _ = chi_square_test(wide)
    var ragged: List[List[Int]] = [[1, 2], [3]]
    with assert_raises(contains="one count for each column"):
        _ = chi_square_test(ragged)
    var negative: List[List[Int]] = [[1, 2], [3, -4]]
    with assert_raises(contains="0 or more"):
        _ = chi_square_test(negative)
    var zero_row: List[List[Int]] = [[0, 0], [3, 4]]
    with assert_raises(contains="each row and each column"):
        _ = chi_square_test(zero_row)
    var zero_col: List[List[Int]] = [[0, 2], [0, 4]]
    with assert_raises(contains="each row and each column"):
        _ = chi_square_test(zero_col)
    var pairs: List[List[Int]] = [[-1, 2], [2, -1]]
    for p in pairs:
        with assert_raises(contains="discordant counts"):
            _ = mcnemar_exact(p[0], p[1])
        with assert_raises(contains="discordant counts"):
            _ = mcnemar_chi_square(p[0], p[1])
    with assert_raises(contains="a discordant pair"):
        _ = mcnemar_chi_square(0, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
