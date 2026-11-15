# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Poisson regression of event rates over person-time.

`assets/rates/rates_expected.txt` holds the results of statsmodels 0.15.0
on the synthetic strata of `assets/rates/strata.txt`. See
`assets/rates/make_rates.py`.
"""

from extensions.clinical.rates import RateModel, poisson_regression
from std.math import exp, inf, log, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import PER_YEAR64, YEAR64, Duration64


def _numbers(line: String) raises -> List[Float64]:
    var out = List[Float64]()
    var first = True
    for part in line.split(" "):
        if first:
            first = False
            continue
        out.append(atof(String(part)))
    return out^


def _years(values: List[Float64]) -> List[Duration64]:
    var out = List[Duration64]()
    for v in values:
        out.append(Duration64(v, YEAR64))
    return out^


def test_against_statsmodels() raises:
    var events = List[Int]()
    var years = List[Float64]()
    var rows = List[List[Float64]]()
    for line in open("assets/rates/strata.txt", "r").read().splitlines():
        var words = String(line).split(" ")
        events.append(atol(String(words[0])))
        years.append(atof(String(words[1])))
        rows.append(
            [
                atof(String(words[2])),
                atof(String(words[3])),
                atof(String(words[4])),
            ]
        )
    var model = poisson_regression(events, _years(years), rows, 1e-12, 100)
    assert_true(model.converged)
    var lines = open("assets/rates/rates_expected.txt", "r").read().splitlines()
    var intercept = _numbers(String(lines[0]))
    assert_almost_equal(model.coefficients[0], intercept[0], rtol=1e-12)
    assert_almost_equal(model.standard_errors[0], intercept[1], rtol=1e-11)
    assert_almost_equal(
        model.baseline_rate().to(PER_YEAR64), exp(intercept[0]), rtol=1e-11
    )
    for a in range(1, 4):
        var row = _numbers(String(lines[a]))
        assert_almost_equal(model.coefficients[a], row[0], rtol=1e-12)
        assert_almost_equal(model.standard_errors[a], row[1], rtol=1e-11)
        assert_almost_equal(model.z(a), row[2], rtol=1e-11)
        assert_almost_equal(model.p_value(a), row[3], rtol=1e-8)
        var band = model.interval(a)
        assert_almost_equal(band[0], row[4], rtol=1e-11)
        assert_almost_equal(band[1], row[5], rtol=1e-11)
        assert_almost_equal(model.rate_ratio(a), exp(row[0]), rtol=1e-11)
    var fit = _numbers(String(lines[4]))
    assert_almost_equal(model.deviance, fit[0], rtol=1e-11)
    assert_almost_equal(model.dispersion, fit[1], rtol=1e-11)
    var predicted = _numbers(String(lines[5]))
    var strata: List[List[Float64]] = [[5.0, 0.0, 2.0], [7.5, 1.0, 4.0]]
    for r in range(2):
        assert_almost_equal(
            model.rate(strata[r]).to(PER_YEAR64), predicted[r], rtol=1e-11
        )


def test_by_hand() raises:
    # Two groups, unexposed then exposed, over 100 and 50 person-years:
    # 10 and 20 events. The rate ratio is (20/50) / (10/100) = 4, with the
    # standard error sqrt(1/10 + 1/20) of its log. One stratum more of each
    # keeps a residual degree of freedom.
    var model = poisson_regression(
        [6, 4, 12, 8],
        _years([60.0, 40.0, 30.0, 20.0]),
        [[0.0], [0.0], [1.0], [1.0]],
        1e-12,
        100,
    )
    assert_almost_equal(model.rate_ratio(1), 4.0, rtol=1e-12)
    assert_almost_equal(
        model.standard_errors[1], (0.1 + 0.05) ** 0.5, rtol=1e-12
    )
    assert_almost_equal(model.baseline_rate().to(PER_YEAR64), 0.1, rtol=1e-12)
    assert_almost_equal(model.deviance, 0.0, atol=1e-12)
    # One step is not enough to converge.
    var short = poisson_regression(
        [0, 4, 12, 8],
        _years([60.0, 40.0, 30.0, 20.0]),
        [[0.0], [0.0], [1.0], [1.0]],
        1e-12,
        1,
    )
    assert_false(short.converged)
    var empty = RateModel(1)
    assert_almost_equal(
        empty.rate(List[Float64]()).to(PER_YEAR64), 1.0, rtol=1e-15
    )


def test_refusals() raises:
    var events: List[Int] = [1, 2, 3]
    var years = _years([10.0, 10.0, 10.0])
    var rows: List[List[Float64]] = [[0.0], [1.0], [2.0]]
    with assert_raises(contains="per stratum"):
        _ = poisson_regression(
            List[Int](), List[Duration64](), List[List[Float64]](), 1e-12, 10
        )
    with assert_raises(contains="per stratum"):
        _ = poisson_regression(events, _years([1.0]), rows, 1e-12, 10)
    with assert_raises(contains="per stratum"):
        _ = poisson_regression(events, years, [[0.0]], 1e-12, 10)
    var wide = List[List[Float64]]()
    var none = List[List[Float64]]()
    for _ in range(3):
        wide.append(List[Float64](length=33, fill=0.0))
        none.append(List[Float64]())
    with assert_raises(contains="1 to 32 covariates"):
        _ = poisson_regression(events, years, wide, 1e-12, 10)
    with assert_raises(contains="1 to 32 covariates"):
        _ = poisson_regression(events, years, none, 1e-12, 10)
    with assert_raises(contains="0 or more"):
        _ = poisson_regression([1, -2, 3], years, rows, 1e-12, 10)
    var bad: List[Float64] = [0.0, inf[DType.float64]()]
    for b in bad:
        with assert_raises(contains="person-time"):
            _ = poisson_regression(
                events, _years([10.0, b, 10.0]), rows, 1e-12, 10
            )
    var ragged: List[List[Float64]] = [[0.0], [1.0, 2.0], [2.0]]
    with assert_raises(contains="same count"):
        _ = poisson_regression(events, years, ragged, 1e-12, 10)
    with assert_raises(contains="must be finite"):
        _ = poisson_regression(
            events, years, [[0.0], [nan[DType.float64]()], [2.0]], 1e-12, 10
        )
    with assert_raises(contains="one event or more"):
        _ = poisson_regression([0, 0, 0], years, rows, 1e-12, 10)
    with assert_raises(contains="more strata than coefficients"):
        _ = poisson_regression(
            [1, 2], _years([1.0, 1.0]), [[0.0], [1.0]], 1e-12, 10
        )
    var tolerances: List[Float64] = [0.0, 1.0]
    for t in tolerances:
        with assert_raises(contains="between 0 and 1"):
            _ = poisson_regression(events, years, rows, t, 10)
    var counts: List[Int] = [0, 1001]
    for c in counts:
        with assert_raises(contains="1 to 1000 steps"):
            _ = poisson_regression(events, years, rows, 1e-12, c)
    with assert_raises(contains="constant or collinear"):
        _ = poisson_regression(events, years, [[2.0], [2.0], [2.0]], 1e-12, 10)
    var model = poisson_regression(events, years, rows, 1e-12, 100)
    var indices: List[Int] = [0, 2]
    for i in indices:
        with assert_raises(contains="no covariate of that index"):
            _ = model.rate_ratio(i)
        with assert_raises(contains="no covariate of that index"):
            _ = model.interval(i)
        with assert_raises(contains="no covariate of that index"):
            _ = model.z(i)
    with assert_raises(contains="one value for each covariate"):
        _ = model.rate([1.0, 2.0])
    with assert_raises(contains="must be finite"):
        _ = model.rate([inf[DType.float64]()])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
