# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Inverse probability weighted effects, covariate balance and E-values.

`assets/propensity/propensity_expected.txt` holds a synthetic study of 500
patients with the values of statsmodels and numpy. See
`tools/make_propensity.mojo` and `assets/propensity/make_propensity.py`.
"""

from extensions.clinical.propensity import (
    IpwEffect,
    e_value,
    e_value_bound,
    effective_sample_size,
    ipw_effect,
    standardized_difference,
)
from std.math import erfc, inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


struct _Study(Movable):
    var treated: List[Bool]
    var outcomes: List[Float64]
    var covariates: List[List[Float64]]
    var rows: Dict[String, List[List[Float64]]]

    def __init__(out self) raises:
        self.treated = List[Bool]()
        self.outcomes = List[Float64]()
        self.covariates = List[List[Float64]]()
        self.rows = Dict[String, List[List[Float64]]]()
        var text = open("assets/propensity/propensity_expected.txt", "r").read()
        for line in text.splitlines():
            var parts = line.split(" ")
            var name = String(parts[0])
            var values = List[Float64]()
            for at in range(1, len(parts)):
                values.append(atof(String(parts[at])))
            if name == "patient":
                self.treated.append(values[0] == 1.0)
                self.outcomes.append(values[1])
                self.covariates.append(List[Float64](values[2:5]))
                continue
            if name not in self.rows:
                self.rows[name] = List[List[Float64]]()
            self.rows[name].append(values^)


def _close(a: Float64, b: Float64, tolerance: Float64) raises:
    assert_almost_equal(a, b, atol=tolerance * abs(b), rtol=0)


def test_against_statsmodels() raises:
    var study = _Study()
    assert_equal(len(study.treated), 500)
    var effect = ipw_effect(study.treated, study.outcomes, study.covariates)
    assert_true(effect.converged)
    ref effects = study.rows["effect"][0]
    _close(effect.difference, effects[0], 1e-12)
    _close(effect.control_mean, effects[1], 1e-13)
    _close(effect.treated_mean, effects[2], 1e-13)
    # statsmodels takes the derivatives of its moments numerically.
    _close(effect.difference_error, effects[3], 1e-9)
    _close(effect.control_error, effects[4], 1e-9)
    _close(effect.treated_error, effects[5], 1e-9)
    # The covariance of the effect d and the control mean m0 of
    # statsmodels. The treated mean is d + m0.
    ref c = study.rows["covariance"][0]
    var treated_variance = c[0] + 2.0 * c[1] + c[2]
    var both = c[1] + c[2]
    _close(effect.covariance, both, 1e-8)
    # The ratio m1 / m0, with the variance of its log by the delta method.
    var m1 = effects[2]
    var m0 = effects[1]
    var log_variance = (
        treated_variance / (m1 * m1) + c[2] / (m0 * m0) - 2.0 * both / (m1 * m0)
    )
    var estimate = effect.ratio()
    _close(estimate.value, m1 / m0, 1e-13)
    _close(effect.ratio_error(), sqrt(log_variance), 1e-8)
    var ones = List[Float64](length=500, fill=1.0)
    for c in range(3):
        var values = List[Float64]()
        for row in study.covariates:
            values.append(row[c])
        ref balance = study.rows["balance"][c]
        _close(
            standardized_difference(values, study.treated, ones),
            balance[0],
            1e-12,
        )
        _close(
            standardized_difference(values, study.treated, effect.weights),
            balance[1],
            1e-9,
        )
    # Kish's effective size of each group: (sum w)^2 / sum w^2.
    var sums: List[Float64] = [0.0, 0.0]
    var squares: List[Float64] = [0.0, 0.0]
    var treated_weights = List[Float64]()
    var control_weights = List[Float64]()
    for i in range(500):
        var w = effect.weights[i]
        var g = 1 if study.treated[i] else 0
        sums[g] += w
        squares[g] += w * w
        if study.treated[i]:
            treated_weights.append(w)
        else:
            control_weights.append(w)
    _close(
        effective_sample_size(treated_weights),
        sums[1] * sums[1] / squares[1],
        1e-12,
    )
    _close(
        effective_sample_size(control_weights),
        sums[0] * sums[0] / squares[0],
        1e-12,
    )


def test_by_hand() raises:
    # The example of VanderWeele and Ding: a risk ratio of 3.9 with a low end
    # of 1.8.
    _close(e_value(3.9), 3.9 + sqrt(3.9 * 2.9), 1e-15)
    assert_true(abs(e_value(3.9) - 7.26) < 0.01)
    _close(e_value_bound(1.8, 8.5), 3.0, 1e-15)
    _close(e_value(1.0 / 3.9), e_value(3.9), 1e-14)
    assert_equal(e_value(1.0), 1.0)
    assert_equal(e_value_bound(0.8, 1.3), 1.0)
    _close(e_value_bound(0.2, 0.5), e_value(0.5), 1e-15)
    assert_equal(effective_sample_size([1.0, 1.0, 1.0, 1.0]), 4.0)
    _close(effective_sample_size([1.0, 3.0]), 1.6, 1e-15)
    # Means 1 and 2 with variances 2 and 2.
    _close(
        standardized_difference(
            [0.0, 2.0, 1.0, 3.0],
            [True, True, False, False],
            [1.0, 1.0, 1.0, 1.0],
        ),
        -1.0 / sqrt(2.0),
        1e-15,
    )
    # A covariate with the same mean in each group gives each patient a
    # propensity of a half and a weight of 2.
    var even = ipw_effect(
        [True, True, False, False],
        [1.0, 0.0, 0.0, 0.0],
        [[0.0], [1.0], [0.0], [1.0]],
    )
    assert_almost_equal(even.propensity[0], 0.5, atol=1e-15)
    assert_almost_equal(even.weights[3], 2.0, atol=1e-14)
    assert_almost_equal(even.treated_mean, 0.5, atol=1e-15)
    assert_almost_equal(even.control_mean, 0.0, atol=1e-15)
    with assert_raises(contains="means above 0"):
        _ = even.ratio()
    var manual = IpwEffect()
    manual.difference = 1.0
    manual.difference_error = 0.5
    var band = manual.interval()
    assert_almost_equal(band[0], 1.0 - 1.959963984540054 * 0.5, atol=1e-15)
    _close(manual.p_value(), erfc(2.0 / sqrt(2.0)), 1e-15)
    manual.control_mean = 0.4
    with assert_raises(contains="means above 0"):
        _ = manual.ratio_error()


def test_errors() raises:
    with assert_raises(contains="one outcome for each"):
        _ = ipw_effect([True, False], [1.0], [[0.0], [1.0]])
    with assert_raises(contains="finite"):
        _ = ipw_effect(
            [True, False], [1.0, nan[DType.float64]()], [[0.0], [1.0]]
        )
    with assert_raises(contains="with and without"):
        _ = ipw_effect([True, True], [1.0, 0.0], [[0.0], [1.0]])
    with assert_raises(contains="one weight or more"):
        _ = effective_sample_size(List[Float64]())
    with assert_raises(contains="positive and finite"):
        _ = effective_sample_size([1.0, 0.0])
    with assert_raises(contains="positive and finite"):
        _ = effective_sample_size([1.0, inf[DType.float64]()])
    var t: List[Bool] = [True, True, False, False]
    var w: List[Float64] = [1.0, 1.0, 1.0, 1.0]
    with assert_raises(contains="one value and weight"):
        _ = standardized_difference([1.0, 2.0, 3.0], t, w)
    with assert_raises(contains="one value and weight"):
        _ = standardized_difference([1.0, 2.0, 3.0, 4.0], [True, False], w)
    with assert_raises(contains="must be finite"):
        _ = standardized_difference([1.0, nan[DType.float64](), 3.0, 4.0], t, w)
    with assert_raises(contains="two patients in each group"):
        _ = standardized_difference(
            [1.0, 2.0, 3.0, 4.0], [True, False, False, False], w
        )
    with assert_raises(contains="two patients in each group"):
        _ = standardized_difference(
            [1.0, 2.0, 3.0, 4.0], [True, True, True, False], w
        )
    with assert_raises(contains="varies"):
        _ = standardized_difference([1.0, 1.0, 1.0, 1.0], t, w)
    var bad: List[Float64] = [0.0, -1.0, inf[DType.float64]()]
    for value in bad:
        with assert_raises(contains="positive, finite ratio"):
            _ = e_value(value)
    with assert_raises(contains="interval that rises"):
        _ = e_value_bound(0.0, 2.0)
    with assert_raises(contains="interval that rises"):
        _ = e_value_bound(3.0, 2.0)
    with assert_raises(contains="interval that rises"):
        _ = e_value_bound(1.0, inf[DType.float64]())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
