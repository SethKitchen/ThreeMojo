# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Weibull accelerated failure time regression.

`assets/aft/aft_expected.txt` holds numpy fits of four groups, checked
against lifelines. See `assets/aft/make_aft.py`.
"""

from extensions.clinical.aft import WeibullRegression, weibull_regression
from extensions.clinical.parametric import DurationUnit64
from extensions.clinical.survival import DAY64, WEEK64
from extensions.clinical.distributions import precise_exp
from std.math import inf, log, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Duration64, SECOND


def _close(a: Float64, b: Float64, tolerance: Float64) raises:
    assert_almost_equal(a, b, atol=tolerance * max(abs(b), 1.0), rtol=0)


struct _Group(Copyable, Movable):
    var times: List[Duration64]
    var events: List[Bool]
    var rows: List[List[Float64]]

    def __init__(out self):
        self.times = List[Duration64]()
        self.events = List[Bool]()
        self.rows = List[List[Float64]]()


def _unit(name: String) -> DurationUnit64:
    if name == "trial":
        return WEEK64
    return DAY64


def _group(name: String) raises -> _Group:
    var out = _Group()
    var text = open("assets/aft/aft_cohort.txt", "r").read()
    for line in text.splitlines():
        var parts = line.split(" ")
        if String(parts[0]) != name:
            continue
        out.times.append(Duration64(atof(String(parts[1])), _unit(name)))
        out.events.append(atof(String(parts[2])) == 1.0)
        var row = List[Float64]()
        for at in range(3, len(parts)):
            row.append(atof(String(parts[at])))
        out.rows.append(row^)
    return out^


def _expected(name: String, kind: String) raises -> List[List[Float64]]:
    var out = List[List[Float64]]()
    var text = open("assets/aft/aft_expected.txt", "r").read()
    for line in text.splitlines():
        var parts = line.split(" ")
        if String(parts[0]) != name or String(parts[1]) != kind:
            continue
        var row = List[Float64]()
        for at in range(2, len(parts)):
            row.append(atof(String(parts[at])))
        out.append(row^)
    return out^


def _check(name: String, count: Int, steps: Int) raises:
    var group = _group(name)
    var unit = _unit(name)
    var model = weibull_regression(
        group.times, group.events, group.rows, 1e-12, 100
    )
    assert_true(model.converged)
    assert_true(model.steps <= steps)
    var b = _expected(name, "coefficients")[0].copy()
    var e = _expected(name, "errors")[0].copy()
    var fit = _expected(name, "fit")[0].copy()
    _close(model.intercept(unit), b[0], 1e-12)
    _close(model.intercept_error, e[0], 1e-10)
    for a in range(count):
        _close(model.coefficients[a], b[a + 1], 1e-12)
        _close(model.standard_errors[a], e[a + 1], 1e-10)
        _close(model.time_ratio(a), precise_exp(b[a + 1]), 1e-12)
        var band = model.interval(a)
        _close(
            band[0], precise_exp(b[a + 1] - 1.959963984540054 * e[a + 1]), 1e-10
        )
        _close(
            band[1], precise_exp(b[a + 1] + 1.959963984540054 * e[a + 1]), 1e-10
        )
    _close(log(model.shape), b[count + 1], 1e-12)
    _close(model.log_shape_error, e[count + 1], 1e-10)
    _close(model.shape, fit[0], 1e-12)
    _close(model.log_likelihood(unit), fit[1], 1e-13)
    var test = model.likelihood_ratio()
    _close(test[0], fit[2], 1e-10)
    _close(test[1], fit[3], 1e-9)
    for probe in _expected(name, "median"):
        var row = List[Float64](probe[0:count])
        _close(model.median(row).to(unit), probe[count], 1e-12)
        var t = Duration64(probe[count + 1], unit)
        _close(model.survival(row, t), probe[count + 2], 1e-12)


def test_against_lifelines() raises:
    _check("trial", 1, 12)
    _check("cohort", 3, 12)


def test_halved_steps() raises:
    # The first step of each would make the shape negative, or lose
    # log-likelihood, so it is halved.
    _check("spread", 1, 20)
    _check("tiny", 1, 20)


def test_by_hand() raises:
    var group = _group("trial")
    var model = weibull_regression(
        group.times, group.events, group.rows, 1e-12, 100
    )
    # The scale of a patient, and the median, `scale (ln 2)^(1 / rho)`.
    var row: List[Float64] = [1.0]
    var scale = model.scale(row).to(WEEK64)
    _close(
        model.median(row).to(WEEK64),
        scale * precise_exp(log(log(2.0)) / model.shape),
        1e-14,
    )
    _close(model.survival(row, model.scale(row)), precise_exp(-1.0), 1e-14)
    assert_equal(model.survival(row, Duration64(0, WEEK64)), 1.0)
    # The intercept moves by ln 7 from weeks to days.
    _close(model.intercept(DAY64) - model.intercept(WEEK64), log(7.0), 1e-14)
    assert_true(model.p_value(0) < 1e-3)
    # One step does not converge.
    var short = weibull_regression(
        group.times, group.events, group.rows, 1e-12, 1
    )
    assert_false(short.converged)
    assert_equal(short.steps, 1)
    # A patient censored at 0 adds nothing.
    var times = group.times.copy()
    var events = group.events.copy()
    var rows = group.rows.copy()
    times.append(Duration64(0, WEEK64))
    events.append(False)
    rows.append([0.0])
    var again = weibull_regression(times, events, rows, 1e-12, 100)
    _close(again.coefficients[0], model.coefficients[0], 1e-12)


def test_errors() raises:
    var group = _group("trial")
    var t = group.times.copy()
    var e = group.events.copy()
    with assert_raises(contains="one row of covariates"):
        _ = weibull_regression(t, e, [[1.0]], 1e-9, 10)
    var empty = List[List[Float64]]()
    for _ in range(len(t)):
        empty.append(List[Float64]())
    with assert_raises(contains="from 1 to 32"):
        _ = weibull_regression(t, e, empty, 1e-9, 10)
    var wide = List[List[Float64]]()
    for _ in range(len(t)):
        wide.append(List[Float64](length=33, fill=1.0))
    with assert_raises(contains="from 1 to 32"):
        _ = weibull_regression(t, e, wide, 1e-9, 10)
    var ragged = group.rows.copy()
    ragged[3] = [1.0, 2.0]
    with assert_raises(contains="same count"):
        _ = weibull_regression(t, e, ragged, 1e-9, 10)
    var bad = group.rows.copy()
    bad[3] = [nan[DType.float64]()]
    with assert_raises(contains="must be finite"):
        _ = weibull_regression(t, e, bad, 1e-9, 10)
    var zero = t.copy()
    zero[0] = Duration64(0, WEEK64)
    with assert_raises(contains="each event after 0"):
        _ = weibull_regression(zero, e, group.rows, 1e-9, 10)
    var tolerances: List[Float64] = [0.0, 1.0]
    for tol in tolerances:
        with assert_raises(contains="tolerance"):
            _ = weibull_regression(t, e, group.rows, tol, 10)
    var counts: List[Int] = [0, 1001]
    for c in counts:
        with assert_raises(contains="Newton steps"):
            _ = weibull_regression(t, e, group.rows, 1e-9, c)
    var flat = List[List[Float64]]()
    for _ in range(len(t)):
        flat.append([1.0])
    with assert_raises(contains="positive definite"):
        _ = weibull_regression(t, e, flat, 1e-9, 10)
    var model = weibull_regression(t, e, group.rows, 1e-9, 100)
    var indices: List[Int] = [-1, 1]
    for i in indices:
        with assert_raises(contains="no covariate of that index"):
            _ = model.time_ratio(i)
        with assert_raises(contains="no covariate of that index"):
            _ = model.interval(i)
        with assert_raises(contains="no covariate of that index"):
            _ = model.p_value(i)
    with assert_raises(contains="one value for each covariate"):
        _ = model.median([1.0, 2.0])
    with assert_raises(contains="must be finite"):
        _ = model.scale([inf[DType.float64]()])
    var times: List[Float64] = [-1.0, inf[DType.float64]()]
    for v in times:
        with assert_raises(contains="0 or more"):
            _ = model.survival([1.0], Duration64(v, WEEK64))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
