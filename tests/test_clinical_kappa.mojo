# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Cohen's kappa, simple and weighted, and Fleiss' kappa of many raters.

`assets/agreement/kappa_expected.txt` holds the results of statsmodels
0.15.0. See `assets/agreement/make_kappa.py`.
`assets/agreement/fleiss_expected.txt` holds Fleiss' kappa of two tables.
See `assets/agreement/make_fleiss.py`.
"""

from extensions.clinical.kappa import (
    Kappa,
    MAX_SUBJECTS,
    cohens_kappa,
    fleiss_kappa,
    linear_weighted_kappa,
    quadratic_weighted_kappa,
)
from std.math import isnan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def _check(result: Kappa, row: List[Float64], at: Int) raises:
    assert_almost_equal(result.value, row[at], rtol=1e-14)
    assert_almost_equal(result.standard_error, row[at + 1], rtol=1e-12)
    assert_almost_equal(result.null_error, row[at + 2], rtol=1e-12)
    assert_almost_equal(result.lower, row[at + 3], rtol=1e-12)
    assert_almost_equal(result.upper, row[at + 4], rtol=1e-12)


def test_against_statsmodels() raises:
    var text = open("assets/agreement/kappa_expected.txt", "r").read()
    var checked = 0
    for line in text.splitlines():
        var words = String(line).split(" ")
        var row = List[Float64]()
        for w in range(1, len(words)):
            row.append(atof(String(words[w])))
        var k = Int(row[0])
        var table = List[List[Int]]()
        for i in range(k):
            var cells = List[Int]()
            for j in range(k):
                cells.append(Int(row[1 + i * k + j]))
            table.append(cells^)
        var at = 1 + k * k
        var kind = String(words[0])
        if kind == "simple":
            _check(cohens_kappa(table), row, at)
        elif kind == "linear":
            _check(linear_weighted_kappa(table), row, at)
        else:
            _check(quadratic_weighted_kappa(table), row, at)
        checked += 1
    assert_equal(checked, 4)


def test_by_hand() raises:
    # Full agreement: kappa 1, with no error.
    var full: List[List[Int]] = [[10, 0], [0, 10]]
    var perfect = cohens_kappa(full)
    assert_equal(perfect.value, 1.0)
    assert_equal(perfect.standard_error, 0.0)
    # Agreement at chance: 25 in each cell gives kappa 0 and p 1.
    var chance: List[List[Int]] = [[25, 25], [25, 25]]
    var none = cohens_kappa(chance)
    assert_equal(none.value, 0.0)
    assert_equal(none.p_value, 1.0)
    # With two categories, the weighted kappas are the simple one.
    var two: List[List[Int]] = [[22, 4], [6, 28]]
    assert_almost_equal(
        linear_weighted_kappa(two).value, cohens_kappa(two).value, rtol=1e-14
    )
    assert_almost_equal(
        quadratic_weighted_kappa(two).value, cohens_kappa(two).value, rtol=1e-14
    )
    # Systematic disagreement gives a kappa below 0.
    var opposite: List[List[Int]] = [[2, 10], [10, 2]]
    assert_true(cohens_kappa(opposite).value < 0)


def test_refusals() raises:
    var one: List[List[Int]] = [[3]]
    with assert_raises(contains="2 to 100 categories"):
        _ = cohens_kappa(one)
    var big = List[List[Int]]()
    for _ in range(101):
        big.append(List[Int](length=101, fill=1))
    with assert_raises(contains="2 to 100 categories"):
        _ = linear_weighted_kappa(big)
    var ragged: List[List[Int]] = [[1, 2], [3]]
    with assert_raises(contains="must be square"):
        _ = quadratic_weighted_kappa(ragged)
    var negative: List[List[Int]] = [[1, -2], [3, 4]]
    with assert_raises(contains="0 or more"):
        _ = cohens_kappa(negative)
    var empty: List[List[Int]] = [[0, 0], [0, 0]]
    with assert_raises(contains="one subject or more"):
        _ = cohens_kappa(empty)
    # Both raters always choose the first category: chance agreement is 1.
    var single: List[List[Int]] = [[9, 0], [0, 0]]
    with assert_raises(contains="agree by chance"):
        _ = cohens_kappa(single)


def test_fleiss_against_references() raises:
    var text = open("assets/agreement/fleiss_expected.txt", "r").read()
    var table = List[List[Int]]()
    var checked = 0
    for line in text.splitlines():
        var words = String(line).split(" ")
        var row = List[Float64]()
        for at in range(1, len(words)):
            row.append(atof(String(words[at])))
        if String(words[0]) == "table":
            var counts = List[Int]()
            for v in row:
                counts.append(Int(v))
            table.append(counts^)
            continue
        var result = fleiss_kappa(table)
        assert_almost_equal(result.value, row[0], rtol=1e-14)
        assert_almost_equal(result.free_marginal, row[1], rtol=1e-14)
        assert_almost_equal(result.null_error, row[2], rtol=1e-13)
        assert_almost_equal(result.z, row[3], rtol=1e-13)
        assert_almost_equal(result.p_value, row[4], rtol=1e-10)
        assert_equal(len(result.categories), len(row) - 5)
        for j in range(len(result.categories)):
            assert_almost_equal(result.categories[j], row[5 + j], rtol=1e-13)
        table = List[List[Int]]()
        checked += 1
    assert_equal(checked, 2)


def test_fleiss_by_hand() raises:
    # Full agreement gives 1, in each category too.
    var full = fleiss_kappa([[3, 0], [0, 3]])
    assert_equal(full.value, 1)
    assert_equal(full.free_marginal, 1)
    assert_equal(full.categories[0], 1)
    # Raters who split each subject evenly give -1.
    var split = fleiss_kappa([[1, 1], [1, 1]])
    assert_equal(split.value, -1)
    # A category no rater chose has no kappa.
    var unused = fleiss_kappa([[3, 0, 0], [0, 3, 0]])
    assert_true(isnan(unused.categories[2]))
    assert_equal(unused.categories[1], 1)
    # With three categories, chance agreement is a third for Randolph.
    assert_equal(unused.free_marginal, 1)


def test_fleiss_refusals() raises:
    with assert_raises(contains="1 to 100000 subjects"):
        _ = fleiss_kappa(List[List[Int]]())
    var many = List[List[Int]]()
    for _ in range(MAX_SUBJECTS + 1):
        many.append([1, 1])
    with assert_raises(contains="1 to 100000 subjects"):
        _ = fleiss_kappa(many)
    with assert_raises(contains="2 to 100 categories"):
        _ = fleiss_kappa([[2]])
    var wide = List[Int](length=101, fill=0)
    wide[0] = 2
    with assert_raises(contains="2 to 100 categories"):
        _ = fleiss_kappa([wide^])
    with assert_raises(contains="a count for each"):
        _ = fleiss_kappa([[1, 1], [2]])
    with assert_raises(contains="0 or more"):
        _ = fleiss_kappa([[3, -1]])
    with assert_raises(contains="same number of ratings"):
        _ = fleiss_kappa([[1, 1], [2, 1]])
    with assert_raises(contains="same number of ratings"):
        _ = fleiss_kappa([[1, 0], [0, 1]])
    with assert_raises(contains="two categories"):
        _ = fleiss_kappa([[3, 0], [3, 0]])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
