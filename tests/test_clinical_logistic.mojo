# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Logistic regression.

`assets/logistic/logistic_expected.txt` holds the results of statsmodels
0.15.0 on the synthetic cohort `assets/logistic/cohort.txt`. See
`tools/make_logistic.mojo` and `assets/logistic/make_logistic.py`.
"""

from extensions.clinical.logistic import LogisticModel, logistic_regression
from extensions.numerics.elementary import precise_exp
from std.math import exp, inf, log, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
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


def test_cohort() raises:
    var outcomes = List[Bool]()
    var rows = List[List[Float64]]()
    var text = open("assets/logistic/cohort.txt", "r").read()
    for line in text.splitlines():
        var words = String(line).split(" ")
        outcomes.append(String(words[0]) == "1")
        rows.append(
            [
                atof(String(words[1])),
                atof(String(words[2])),
                atof(String(words[3])),
            ]
        )
    var model = logistic_regression(outcomes, rows, 1e-10, 50)
    assert_true(model.converged)
    var lines = open("assets/logistic/logistic_expected.txt", "r").read()
    var expected = List[List[Float64]]()
    for line in lines.splitlines():
        expected.append(_numbers(String(line)))
    for a in range(4):
        ref row = expected[a]
        assert_almost_equal(model.coefficients[a], row[0], rtol=1e-12)
        assert_almost_equal(model.standard_errors[a], row[1], rtol=1e-12)
        assert_almost_equal(model.z(a), row[2], rtol=1e-12)
        assert_almost_equal(model.p_value(a), row[3], rtol=1e-10)
        var band = model.interval(a)
        # The interval of the ratio is that of the coefficient, raised.
        assert_almost_equal(band[0], precise_exp(row[4]), rtol=1e-12)
        assert_almost_equal(band[1], precise_exp(row[5]), rtol=1e-12)
        assert_almost_equal(model.odds_ratio(a), exp(row[0]), rtol=1e-12)
    ref fit = expected[4]
    assert_almost_equal(model.log_likelihood, fit[0], rtol=1e-14)
    assert_almost_equal(model.null_log_likelihood, fit[1], rtol=1e-14)
    var test = model.likelihood_ratio()
    assert_almost_equal(test[0], fit[2], rtol=1e-12)
    assert_almost_equal(test[1], fit[3], rtol=1e-10)
    ref risk = expected[5]
    var patients: List[List[Float64]] = [
        [5.0, 0.0, 1.0],
        [6.5, 1.0, 2.5],
        [8.0, 1.0, 4.0],
    ]
    for r in range(3):
        assert_almost_equal(model.risk(patients[r]), risk[r], rtol=1e-12)


def test_two_by_two() raises:
    # Exposed: 10 cases and 20 controls. Not exposed: 5 cases and 40
    # controls. The odds ratio is (10 x 40) / (20 x 5) = 4, with Woolf's
    # standard error sqrt(1/10 + 1/20 + 1/5 + 1/40) of its logarithm.
    var outcomes = List[Bool]()
    var rows = List[List[Float64]]()
    var counts: List[Int] = [10, 20, 5, 40]
    for c in range(4):
        for _ in range(counts[c]):
            outcomes.append(c % 2 == 0)
            rows.append([1.0 if c < 2 else 0.0])
    var model = logistic_regression(outcomes, rows, 1e-12, 50)
    assert_almost_equal(model.odds_ratio(1), 4.0, rtol=1e-13)
    assert_almost_equal(
        model.standard_errors[1], sqrt(0.1 + 0.05 + 0.2 + 0.025), rtol=1e-12
    )
    # The intercept is the log odds of the unexposed, 5/40.
    assert_almost_equal(model.coefficients[0], log(0.125), rtol=1e-13)
    assert_almost_equal(model.standard_errors[0], sqrt(0.2 + 0.025), rtol=1e-12)
    assert_almost_equal(model.risk([1.0]), 1.0 / 3.0, rtol=1e-13)
    assert_almost_equal(model.risk([0.0]), 5.0 / 45.0, rtol=1e-13)
    # Large covariates: risks of 1 and 0 without overflow.
    assert_almost_equal(model.risk([1000.0]), 1.0, rtol=1e-15)
    assert_true(model.risk([-1000.0]) < 1e-300)


def test_steps() raises:
    # An outcome that the covariate separates: the coefficient grows at
    # each step, and the fit does not converge.
    var apart = logistic_regression(
        [False, False, True, True], [[0.0], [1.0], [2.0], [3.0]], 1e-10, 5
    )
    assert_false(apart.converged)
    assert_equal(apart.steps, 5)
    assert_true(apart.coefficients[1] > 3)
    # An intercept alone.
    var empty = LogisticModel(1)
    assert_equal(empty.risk(List[Float64]()), 0.5)
    with assert_raises(contains="degrees of freedom"):
        _ = empty.likelihood_ratio()


def test_refusals() raises:
    var outcomes: List[Bool] = [True, False, True]
    var good: List[List[Float64]] = [[0.0], [1.0], [3.0]]
    with assert_raises(contains="one row of covariates"):
        _ = logistic_regression(List[Bool](), List[List[Float64]](), 1e-10, 50)
    with assert_raises(contains="one row of covariates"):
        _ = logistic_regression(outcomes, [[0.0]], 1e-10, 50)
    var wide = List[List[Float64]]()
    var empty = List[List[Float64]]()
    for _ in range(3):
        wide.append(List[Float64](length=33, fill=0.0))
        empty.append(List[Float64]())
    with assert_raises(contains="from 1 to 32 covariates"):
        _ = logistic_regression(outcomes, wide, 1e-10, 50)
    with assert_raises(contains="from 1 to 32 covariates"):
        _ = logistic_regression(outcomes, empty, 1e-10, 50)
    var ragged: List[List[Float64]] = [[0.0], [1.0, 2.0], [3.0]]
    with assert_raises(contains="same count"):
        _ = logistic_regression(outcomes, ragged, 1e-10, 50)
    var bad: List[List[Float64]] = [[0.0], [nan[DType.float64]()], [3.0]]
    with assert_raises(contains="must be finite"):
        _ = logistic_regression(outcomes, bad, 1e-10, 50)
    var tolerances: List[Float64] = [0.0, 1.0, nan[DType.float64]()]
    for t in tolerances:
        with assert_raises(contains="between 0 and 1"):
            _ = logistic_regression(outcomes, good, t, 50)
    var counts: List[Int] = [0, 1001]
    for c in counts:
        with assert_raises(contains="Newton steps"):
            _ = logistic_regression(outcomes, good, 1e-10, c)
    with assert_raises(contains="with and without the outcome"):
        _ = logistic_regression([True, True, True], good, 1e-10, 50)
    with assert_raises(contains="with and without the outcome"):
        _ = logistic_regression([False, False, False], good, 1e-10, 50)
    with assert_raises(contains="not positive definite"):
        _ = logistic_regression(outcomes, [[2.0], [2.0], [2.0]], 1e-10, 50)
    var model = logistic_regression(outcomes, good, 1e-10, 50)
    var indices: List[Int] = [-1, 2]
    for i in indices:
        with assert_raises(contains="no coefficient of that index"):
            _ = model.z(i)
        with assert_raises(contains="no coefficient of that index"):
            _ = model.odds_ratio(i)
        with assert_raises(contains="no coefficient of that index"):
            _ = model.interval(i)
    with assert_raises(contains="one value for each covariate"):
        _ = model.risk([1.0, 2.0])
    with assert_raises(contains="must be finite"):
        _ = model.risk([inf[DType.float64]()])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
