# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Linear regression by least squares.

`assets/regression/regression_expected.txt` holds the results of
statsmodels 0.15.0 on the synthetic cohort of
`assets/regression/pressure.txt`. See `tools/make_regression.mojo` and
`assets/regression/make_regression.py`.
"""

from extensions.clinical.regression import LinearModel, linear_regression
from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
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


def test_against_statsmodels() raises:
    var outcome = List[Float64]()
    var rows = List[List[Float64]]()
    for line in open("assets/regression/pressure.txt", "r").read().splitlines():
        var words = String(line).split(" ")
        outcome.append(atof(String(words[0])))
        rows.append(
            [
                atof(String(words[1])),
                atof(String(words[2])),
                atof(String(words[3])),
            ]
        )
    var model = linear_regression(outcome, rows)
    var lines = (
        open("assets/regression/regression_expected.txt", "r")
        .read()
        .splitlines()
    )
    for a in range(4):
        var row = _numbers(String(lines[a]))
        assert_almost_equal(model.coefficients[a], row[0], rtol=1e-12)
        assert_almost_equal(model.standard_errors[a], row[1], rtol=1e-12)
        assert_almost_equal(model.t(a), row[2], rtol=1e-12)
        assert_almost_equal(model.p_value(a), row[3], rtol=1e-9)
        var band = model.interval(a)
        assert_almost_equal(band[0], row[4], rtol=1e-12)
        assert_almost_equal(band[1], row[5], rtol=1e-12)
    var fit = _numbers(String(lines[4]))
    assert_almost_equal(model.r_squared, fit[0], rtol=1e-13)
    assert_almost_equal(model.adjusted_r_squared, fit[1], rtol=1e-13)
    assert_almost_equal(model.f, fit[2], rtol=1e-12)
    assert_almost_equal(model.f_p_value, fit[3], rtol=1e-9)
    assert_almost_equal(model.residual_deviation, fit[4], rtol=1e-13)
    var predicted = _numbers(String(lines[5]))
    var patients: List[List[Float64]] = [[45.0, 24.0, 6.0], [70.0, 31.5, 11.0]]
    for r in range(2):
        assert_almost_equal(
            model.predict(patients[r]), predicted[r], rtol=1e-13
        )


def test_by_hand() raises:
    # y = 1 + 2x with residuals +1, -1, -1, +1 at x = 0, 1, 2, 3. The
    # slope stays 2, the intercept 1, and s^2 = 4 / 2.
    var model = linear_regression(
        [2.0, 2.0, 4.0, 8.0], [[0.0], [1.0], [2.0], [3.0]]
    )
    assert_almost_equal(model.coefficients[1], 2.0, rtol=1e-14)
    assert_almost_equal(model.coefficients[0], 1.0, rtol=1e-14)
    assert_almost_equal(model.residual_deviation, sqrt(2.0), rtol=1e-14)
    # Var(slope) = s^2 / sum((x - 1.5)^2) = 2 / 5.
    assert_almost_equal(model.standard_errors[1], sqrt(0.4), rtol=1e-14)
    assert_equal(model.freedom, 2)
    var empty = LinearModel(1)
    assert_equal(empty.predict(List[Float64]()), 0.0)


def test_refusals() raises:
    var y: List[Float64] = [1.0, 2.0, 4.0]
    var good: List[List[Float64]] = [[0.0], [1.0], [2.0]]
    with assert_raises(contains="one row of covariates"):
        _ = linear_regression(List[Float64](), List[List[Float64]]())
    with assert_raises(contains="one row of covariates"):
        _ = linear_regression(y, [[0.0]])
    var wide = List[List[Float64]]()
    var none = List[List[Float64]]()
    for _ in range(3):
        wide.append(List[Float64](length=33, fill=0.0))
        none.append(List[Float64]())
    with assert_raises(contains="from 1 to 32 covariates"):
        _ = linear_regression(y, wide)
    with assert_raises(contains="from 1 to 32 covariates"):
        _ = linear_regression(y, none)
    var ragged: List[List[Float64]] = [[0.0], [1.0, 2.0], [3.0]]
    with assert_raises(contains="same count"):
        _ = linear_regression(y, ragged)
    with assert_raises(contains="outcome of a subject must be finite"):
        _ = linear_regression([1.0, nan[DType.float64](), 2.0], good)
    with assert_raises(contains="covariates of a subject must be finite"):
        _ = linear_regression(y, [[0.0], [inf[DType.float64]()], [2.0]])
    with assert_raises(contains="more subjects than coefficients"):
        _ = linear_regression([1.0, 2.0], [[0.0], [1.0]])
    with assert_raises(contains="constant or collinear"):
        _ = linear_regression(y, [[5.0], [5.0], [5.0]])
    # A line of quarters fits exactly, with no roundoff.
    with assert_raises(contains="the fit misses"):
        _ = linear_regression(
            [1.0, 3.0, 5.0, 7.0], [[0.0], [1.0], [2.0], [3.0]]
        )
    var model = linear_regression(y, good)
    var indices: List[Int] = [-1, 2]
    for i in indices:
        with assert_raises(contains="no coefficient of that index"):
            _ = model.t(i)
        with assert_raises(contains="no coefficient of that index"):
            _ = model.interval(i)
    with assert_raises(contains="one value for each covariate"):
        _ = model.predict([1.0, 2.0])
    with assert_raises(contains="covariates of a subject must be finite"):
        _ = model.predict([nan[DType.float64]()])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
