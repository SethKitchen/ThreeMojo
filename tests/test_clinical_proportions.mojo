# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Proportion intervals and two-by-two tables.

`assets/proportions/proportions_expected.txt` holds the results of
statsmodels 0.15.0. See `assets/proportions/make_proportions.py`.
"""

from extensions.numerics.distributions import beta_quantile
from extensions.clinical.proportions import (
    Estimate,
    compare_risks,
    diagnostic_accuracy,
    exact_interval,
    wilson_interval,
)
from std.math import exp, isinf, log, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def _numbers(line: String) raises -> List[Float64]:
    var out = List[Float64]()
    var first = True
    for part in line.split(" "):
        if first:
            first = False
            continue
        out.append(atof(String(part)))
    return out^


def _expected() raises -> List[List[Float64]]:
    var out = List[List[Float64]]()
    var text = open("assets/proportions/proportions_expected.txt", "r").read()
    for line in text.splitlines():
        out.append(_numbers(String(line)))
    return out^


def _check(estimate: Estimate, row: List[Float64], at: Int) raises:
    assert_almost_equal(estimate.value, row[at], rtol=1e-14)
    assert_almost_equal(estimate.lower, row[at + 1], rtol=1e-12, atol=1e-15)
    assert_almost_equal(estimate.upper, row[at + 2], rtol=1e-12, atol=1e-15)


def test_proportions() raises:
    ref row = _expected()[0]
    for c in range(6):
        var x = Int(row[6 * c])
        var n = Int(row[6 * c + 1])
        var wilson = wilson_interval(x, n)
        assert_almost_equal(wilson[0], row[6 * c + 2], rtol=1e-13, atol=1e-15)
        assert_almost_equal(wilson[1], row[6 * c + 3], rtol=1e-13, atol=1e-15)
        var exact = exact_interval(x, n)
        assert_almost_equal(exact[0], row[6 * c + 4], rtol=1e-12, atol=1e-15)
        assert_almost_equal(exact[1], row[6 * c + 5], rtol=1e-12, atol=1e-15)
    # With no success, the exact high end is 1 - 0.025^(1/n).
    assert_almost_equal(
        exact_interval(0, 20)[1], 1.0 - exp(log(0.025) / 20.0), rtol=1e-14
    )
    assert_equal(exact_interval(0, 20)[0], 0.0)
    assert_equal(exact_interval(20, 20)[1], 1.0)
    # The beta quantile on both sides of a half: Beta(2, 1) has x^2.
    assert_almost_equal(beta_quantile(0.25, 2.0, 1.0), 0.5, rtol=1e-14)
    assert_almost_equal(beta_quantile(0.81, 2.0, 1.0), 0.9, rtol=1e-14)


def test_diagnostic() raises:
    ref row = _expected()[1]
    var test = diagnostic_accuracy(90, 30, 10, 170)
    _check(test.sensitivity, row, 0)
    _check(test.specificity, row, 3)
    _check(test.positive_predictive, row, 6)
    _check(test.negative_predictive, row, 9)
    _check(test.accuracy, row, 12)
    _check(test.prevalence, row, 15)
    _check(test.positive_likelihood, row, 18)
    _check(test.negative_likelihood, row, 21)
    # By hand: LR+ = 0.9 / 0.15 = 6, LR- = 0.1 / 0.85.
    assert_almost_equal(test.positive_likelihood.value, 6.0, rtol=1e-14)
    assert_almost_equal(test.negative_likelihood.value, 0.1 / 0.85, rtol=1e-14)
    # A perfect specificity: no false positive, so a half more per cell.
    var perfect = diagnostic_accuracy(9, 0, 1, 10)
    assert_equal(perfect.specificity.value, 1.0)
    assert_almost_equal(
        perfect.positive_likelihood.value,
        (9.5 / 11.0) / (0.5 / 11.0),
        rtol=1e-14,
    )


def test_risks() raises:
    ref row = _expected()[2]
    var trial = compare_risks(30, 100, 15, 100)
    _check(trial.difference, row, 0)
    _check(trial.ratio, row, 3)
    _check(trial.odds_ratio, row, 6)
    assert_almost_equal(trial.number_needed, 1.0 / 0.15, rtol=1e-14)
    assert_equal(trial.first.value, 0.3)
    var same = compare_risks(5, 50, 5, 50)
    assert_true(isinf(same.number_needed))
    assert_equal(same.difference.value, 0.0)


def test_refusals() raises:
    var counts: List[List[Int]] = [[1, 0], [-1, 5], [6, 5]]
    for c in counts:
        with assert_raises(contains="successes from 0 to its trials"):
            _ = wilson_interval(c[0], c[1])
        with assert_raises(contains="successes from 0 to its trials"):
            _ = exact_interval(c[0], c[1])
    var cells: List[List[Int]] = [
        [-1, 1, 1, 1],
        [1, -1, 1, 1],
        [1, 1, -1, 1],
        [1, 1, 1, -1],
    ]
    for c in cells:
        with assert_raises(contains="0 or more"):
            _ = diagnostic_accuracy(c[0], c[1], c[2], c[3])
    var empty: List[List[Int]] = [
        [0, 1, 0, 1],
        [1, 0, 1, 0],
        [0, 0, 1, 1],
        [1, 1, 0, 0],
    ]
    for c in empty:
        with assert_raises(contains="diseased, healthy, positive"):
            _ = diagnostic_accuracy(c[0], c[1], c[2], c[3])
    with assert_raises(contains="successes from 0 to its trials"):
        _ = compare_risks(5, 4, 1, 10)
    with assert_raises(contains="between 0 and 1"):
        _ = beta_quantile(nan[DType.float64](), 1.0, 1.0)
    with assert_raises(contains="degrees of freedom"):
        _ = beta_quantile(0.5, 0.0, 1.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
