# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Cox proportional hazards regression.

`assets/survival/cox_expected.txt` holds the results of lifelines 0.30.3 on
the synthetic cohort `assets/survival/cox_cohort.txt` and on the trial of
Freireich and others (1963). See `assets/survival/make_cox.py`.
"""

from extensions.clinical.cox import (
    CoxModel,
    chi_square_p_value,
    cox_regression,
)
from extensions.clinical.survival import WEEK64
from std.math import erfc, exp, inf, log, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Duration64

comptime DRUG = (
    "6 6 6 6+ 7 9+ 10 10+ 11+ 13 16 17+ 19+ 20+ 22 23 25+ 32+ 32+ 34+ 35+"
)
comptime PLACEBO = "1 1 2 2 3 4 4 5 5 8 8 8 8 11 11 12 12 15 17 22 23"


def _weeks(values: List[Float64]) -> List[Duration64]:
    var out = List[Duration64]()
    for v in values:
        out.append(Duration64(v, WEEK64))
    return out^


def _column(values: List[Float64]) -> List[List[Float64]]:
    var out = List[List[Float64]]()
    for v in values:
        out.append([v])
    return out^


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
    var text = open("assets/survival/cox_expected.txt", "r").read()
    for line in text.splitlines():
        out.append(_numbers(String(line)))
    return out^


def test_cohort() raises:
    var times = List[Duration64]()
    var events = List[Bool]()
    var rows = List[List[Float64]]()
    var text = open("assets/survival/cox_cohort.txt", "r").read()
    for line in text.splitlines():
        var words = String(line).split(" ")
        times.append(Duration64(atof(String(words[0])), WEEK64))
        events.append(String(words[1]) == "1")
        rows.append(
            [
                atof(String(words[2])),
                atof(String(words[3])),
                atof(String(words[4])),
            ]
        )
    var model = cox_regression(times, events, rows, 1e-10, 50)
    assert_true(model.converged)
    var expected = _expected()
    ref cohort = expected[0]
    for a in range(3):
        assert_almost_equal(
            model.coefficients[a], cohort[6 * a], atol=1e-12, rtol=0
        )
        assert_almost_equal(
            model.standard_errors[a], cohort[6 * a + 1], rtol=1e-11
        )
        assert_almost_equal(model.z(a), cohort[6 * a + 2], rtol=1e-11)
        assert_almost_equal(model.p_value(a), cohort[6 * a + 3], rtol=1e-10)
        var band = model.interval(a)
        assert_almost_equal(band[0], cohort[6 * a + 4], rtol=1e-11)
        assert_almost_equal(band[1], cohort[6 * a + 5], rtol=1e-11)
        assert_almost_equal(
            model.hazard_ratio(a), exp(cohort[6 * a]), rtol=1e-11
        )
    ref fit = expected[1]
    assert_almost_equal(model.log_likelihood, fit[0], rtol=1e-14)
    assert_almost_equal(model.null_log_likelihood, fit[1], rtol=1e-14)
    var test = model.likelihood_ratio()
    assert_almost_equal(test[0], fit[2], rtol=1e-11)
    assert_almost_equal(test[1], fit[3], rtol=1e-10)
    assert_equal(model.concordance, fit[4])
    ref curves = expected[2]
    var patients: List[List[Float64]] = [
        [5.0, 1.0, 0.5],
        [6.5, 0.0, 1.0],
        [8.0, 0.0, 2.0],
    ]
    var at: List[Float64] = [5.0, 20.0, 60.0]
    for r in range(3):
        for t in range(3):
            assert_almost_equal(
                model.survival(patients[r], Duration64(at[t], WEEK64)),
                curves[3 * r + t],
                rtol=1e-11,
            )


def _group(text: String) raises -> List[Tuple[Float64, Bool]]:
    var out = List[Tuple[Float64, Bool]]()
    for part in text.split(" "):
        var word = String(part)
        var censored = word.endswith("+")
        var number = word
        if censored:
            number = String(word[byte = 0 : word.byte_length() - 1])
        out.append((atof(number), not censored))
    return out^


def test_freireich() raises:
    var times = List[Duration64]()
    var events = List[Bool]()
    var rows = List[List[Float64]]()
    var texts: List[String] = [DRUG, PLACEBO]
    for g in range(2):
        for patient in _group(texts[g]):
            times.append(Duration64(patient[0], WEEK64))
            events.append(patient[1])
            rows.append([Float64(g)])
    var model = cox_regression(times, events, rows, 1e-10, 50)
    var expected = _expected()[3].copy()
    assert_almost_equal(model.coefficients[0], expected[0], rtol=1e-12)
    assert_almost_equal(model.standard_errors[0], expected[1], rtol=1e-11)
    assert_almost_equal(model.p_value(0), expected[2], rtol=1e-10)


def test_by_hand() raises:
    # A (1) has the event at 1 week, B (0) at 2 weeks; C (1) and D (0) are
    # censored at 3 weeks. The score is 1 - u/(u + 1) - u/(u + 2) with
    # u = exp(b), 0 at u = sqrt(2). The information is 6 sqrt(2) - 8.
    var times = _weeks([1.0, 2.0, 3.0, 3.0])
    var events: List[Bool] = [True, True, False, False]
    var model = cox_regression(
        times, events, _column([1.0, 0.0, 1.0, 0.0]), 1e-12, 50
    )
    assert_almost_equal(model.coefficients[0], log(2.0) / 2, rtol=1e-14)
    assert_almost_equal(model.hazard_ratio(0), sqrt(2.0), rtol=1e-14)
    assert_almost_equal(
        model.standard_errors[0], 1 / sqrt(6 * sqrt(2.0) - 8), rtol=1e-12
    )
    # A beats B and D, ties C; B loses to C and ties D: 3 of 5.
    assert_almost_equal(model.concordance, 0.6, rtol=1e-15)
    # Breslow: 1/(2u + 2) at 1 week and 1/(u + 2) at 2 weeks, for x = 0.
    var hazard = 1 / (2 * sqrt(2.0) + 2) + 1 / (sqrt(2.0) + 2)
    var zero: List[Float64] = [0.0]
    assert_almost_equal(
        model.survival(zero, Duration64(9, WEEK64)), exp(-hazard), rtol=1e-12
    )
    assert_equal(model.survival(zero, Duration64(0.5, WEEK64)), 1.0)
    assert_equal(len(model.times), 2)
    assert_almost_equal(model.relative_hazard([0.5]), 1.0, rtol=1e-15)
    # Efron's ties. A (1) and B (0) both have the event at 1 week; C (0) is
    # censored at 2. The log-likelihood is b - ln(u + 2) - ln((u + 3)/2):
    # its score is 0 at u = sqrt(6). Breslow's method would give u = 2.
    var tied = cox_regression(
        _weeks([1.0, 1.0, 2.0]),
        [True, True, False],
        _column([1.0, 0.0, 0.0]),
        1e-12,
        50,
    )
    assert_almost_equal(tied.coefficients[0], log(6.0) / 2, rtol=1e-14)


def test_steps() raises:
    # Here the first full Newton step loses likelihood, and is halved.
    var times = _weeks([1.0, 5.0, 4.0, 5.0, 7.0, 2.0])
    var events: List[Bool] = [True, True, False, True, False, True]
    var model = cox_regression(
        times, events, _column([10.0, 1.0, 0.0, 0.0, 1.0, 0.0]), 1e-10, 50
    )
    assert_true(model.converged)
    assert_almost_equal(model.coefficients[0], 0.38608225, atol=1e-8)
    # A covariate that separates the patients: b grows at each step.
    var apart = cox_regression(
        _weeks([1.0, 2.0]), [True, False], _column([1.0, 0.0]), 1e-10, 5
    )
    assert_false(apart.converged)
    assert_equal(apart.steps, 5)
    assert_true(apart.coefficients[0] > 4)
    # Three patients with the event at one time: no pair can be compared,
    # and the fit stays at 0.
    var together = cox_regression(
        _weeks([1.0, 1.0, 1.0]),
        [True, True, True],
        _column([0.0, 1.0, 3.0]),
        1e-10,
        50,
    )
    assert_equal(together.concordance, 0.5)
    assert_almost_equal(together.coefficients[0], 0.0, atol=1e-12)
    assert_true(together.likelihood_ratio()[1] > 0.999)


def test_chi_square() raises:
    # One degree: erfc(sqrt(x / 2)). Two degrees: exp(-x / 2).
    assert_equal(chi_square_p_value(3.0, 1), erfc(sqrt(1.5)))
    assert_almost_equal(chi_square_p_value(3.0, 2), exp(-1.5), rtol=1e-15)
    # Three degrees, and four: chi2.sf of scipy.
    assert_almost_equal(
        chi_square_p_value(7.0, 3), 0.07189777249646509, rtol=1e-12
    )
    assert_almost_equal(
        chi_square_p_value(7.0, 4), 0.13588822540043327, rtol=1e-12
    )
    # Many degrees, odd and even.
    assert_almost_equal(
        chi_square_p_value(250.0, 201), 0.010663859138751904, rtol=1e-10
    )
    assert_almost_equal(
        chi_square_p_value(250.0, 200), 0.009379131668826098, rtol=1e-10
    )
    assert_equal(chi_square_p_value(0.0, 5), 1.0)
    assert_equal(chi_square_p_value(inf[DType.float64](), 5), 0.0)
    var freedoms: List[Int] = [0, 1001]
    for f in freedoms:
        with assert_raises(contains="degrees of freedom"):
            _ = chi_square_p_value(1.0, f)
    var bad: List[Float64] = [-1.0, nan[DType.float64]()]
    for b in bad:
        with assert_raises(contains="0 or more"):
            _ = chi_square_p_value(b, 1)


def test_refusals() raises:
    var times = _weeks([1.0, 2.0, 3.0])
    var events: List[Bool] = [True, True, False]
    var good = _column([0.0, 1.0, 2.0])
    with assert_raises(contains="one patient or more"):
        _ = cox_regression(times, [True], good, 1e-10, 50)
    with assert_raises(contains="one row of covariates"):
        _ = cox_regression(times, events, _column([0.0, 1.0]), 1e-10, 50)
    var wide = List[List[Float64]]()
    var empty = List[List[Float64]]()
    for _ in range(3):
        wide.append(List[Float64](length=33, fill=0.0))
        empty.append(List[Float64]())
    with assert_raises(contains="from 1 to 32 covariates"):
        _ = cox_regression(times, events, wide, 1e-10, 50)
    with assert_raises(contains="from 1 to 32 covariates"):
        _ = cox_regression(times, events, empty, 1e-10, 50)
    var ragged: List[List[Float64]] = [[0.0], [1.0, 2.0], [3.0]]
    with assert_raises(contains="same count"):
        _ = cox_regression(times, events, ragged, 1e-10, 50)
    with assert_raises(contains="must be finite"):
        _ = cox_regression(
            times, events, _column([0.0, inf[DType.float64](), 1.0]), 1e-10, 50
        )
    var tolerances: List[Float64] = [0.0, 1.0, nan[DType.float64]()]
    for t in tolerances:
        with assert_raises(contains="between 0 and 1"):
            _ = cox_regression(times, events, good, t, 50)
    var counts: List[Int] = [0, 1001]
    for c in counts:
        with assert_raises(contains="Newton steps"):
            _ = cox_regression(times, events, good, 1e-10, c)
    with assert_raises(contains="one event or more"):
        _ = cox_regression(times, [False, False, False], good, 1e-10, 50)
    with assert_raises(contains="not positive definite"):
        _ = cox_regression(times, events, _column([2.0, 2.0, 2.0]), 1e-10, 50)
    var model = cox_regression(times, events, good, 1e-10, 50)
    var indices: List[Int] = [-1, 1]
    for i in indices:
        with assert_raises(contains="no covariate of that index"):
            _ = model.z(i)
        with assert_raises(contains="no covariate of that index"):
            _ = model.hazard_ratio(i)
        with assert_raises(contains="no covariate of that index"):
            _ = model.interval(i)
    with assert_raises(contains="one value for each covariate"):
        _ = model.relative_hazard([1.0, 2.0])
    with assert_raises(contains="must be finite"):
        _ = model.relative_hazard([nan[DType.float64]()])
    var at: List[Float64] = [-1.0, inf[DType.float64]()]
    for t in at:
        with assert_raises(contains="0 or more, and finite"):
            _ = model.survival([1.0], Duration64(t, WEEK64))
    with assert_raises(contains="degrees of freedom"):
        _ = CoxModel(0).likelihood_ratio()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
