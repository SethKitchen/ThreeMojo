# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Negative binomial (NB2) regression of event rates.

`assets/rates/negbin_expected.txt` holds 120 synthetic strata with the
values of statsmodels. See `assets/rates/make_negbin.py`.
"""

from extensions.numerics.elementary import precise_exp
from extensions.clinical.negbin import negative_binomial_regression
from extensions.clinical.rates import PER_YEAR64, YEAR64
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Duration64


def _close(a: Float64, b: Float64, tolerance: Float64) raises:
    assert_almost_equal(a, b, atol=tolerance * abs(b), rtol=0)


def _years(count: Int) -> List[Duration64]:
    var out = List[Duration64]()
    for _ in range(count):
        out.append(Duration64(1.0, YEAR64))
    return out^


def test_against_statsmodels() raises:
    var events = List[Int]()
    var exposure = List[Duration64]()
    var covariates = List[List[Float64]]()
    var rows = Dict[String, List[Float64]]()
    var text = open("assets/rates/negbin_expected.txt", "r").read()
    for line in text.splitlines():
        var parts = line.split(" ")
        var values = List[Float64]()
        for at in range(1, len(parts)):
            values.append(atof(String(parts[at])))
        if String(parts[0]) == "stratum":
            events.append(Int(values[0]))
            exposure.append(Duration64(values[1], YEAR64))
            covariates.append([values[2], values[3]])
        else:
            rows[String(parts[0])] = values^
    assert_equal(len(events), 120)
    var model = negative_binomial_regression(events, exposure, covariates)
    ref params = rows["params"]
    ref errors = rows["errors"]
    for a in range(3):
        _close(model.rates.coefficients[a], params[a], 1e-10)
        _close(model.rates.standard_errors[a], errors[a], 1e-9)
    _close(model.alpha, params[3], 1e-10)
    _close(model.alpha_error, errors[3], 1e-9)
    ref fit = rows["fit"]
    _close(model.log_likelihood, fit[0], 1e-13)
    _close(model.poisson_log_likelihood, fit[1], 1e-12)
    _close(model.likelihood_ratio(), fit[2], 1e-11)
    _close(model.p_value(), fit[3], 1e-8)
    ref glm = rows["glm"]
    _close(model.rates.deviance, glm[0], 1e-9)
    _close(model.rates.dispersion, glm[1], 1e-8)
    _close(model.rates.rate_ratio(1), precise_exp(params[1]), 1e-10)
    assert_true(model.rates.converged)


def test_two_groups() raises:
    # A model of one flag fits each group's mean: 4 and 12 a year.
    var model = negative_binomial_regression(
        [0, 2, 10, 4, 1, 30, 5, 12],
        _years(8),
        [[0.0], [0.0], [0.0], [0.0], [1.0], [1.0], [1.0], [1.0]],
    )
    _close(model.rates.rate_ratio(1), 3.0, 1e-9)
    _close(model.rates.baseline_rate().to(PER_YEAR64), 4.0, 1e-9)
    assert_true(model.alpha > 0.4)
    assert_true(model.p_value() < 0.05)


def test_refusals() raises:
    # Counts that spread less than Poisson counts have no dispersion.
    var even = List[List[Float64]]()
    for i in range(10):
        even.append([Float64(i % 2)])
    with assert_raises(contains="no more than Poisson"):
        _ = negative_binomial_regression(
            [10, 10, 11, 9, 10, 10, 10, 11, 9, 10], _years(10), even
        )
    with assert_raises(contains="0 or more"):
        _ = negative_binomial_regression(
            [1, -1, 2], _years(3), [[0.0], [1.0], [0.0]]
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
