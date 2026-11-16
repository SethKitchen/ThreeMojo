# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exponential and Weibull fits of censored times.

`assets/parametric/parametric_expected.txt` holds double-double fits of
four groups, from `tools/reference_parametric.mojo`.
`assets/parametric/parametric_lifelines.txt` holds the fits of lifelines
and the p values of scipy, from `assets/parametric/make_parametric.py`.
The reference must agree with lifelines to lifelines' own tolerance. See
`tools/make_parametric.mojo`.
"""

from extensions.clinical.parametric import (
    ParametricFit,
    constant_hazard_test,
    draw_fit,
    fit_exponential,
    fit_weibull,
)
from extensions.clinical.survival import (
    SurvivalCurve,
    kaplan_meier,
    survival_image,
)
from extensions.imaging.transfer import Rgba
from render.framebuffer import Color
from std.math import inf, log, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    DAY64,
    PER_SECOND,
    SECOND,
    WEEK64,
    Duration64,
    DurationUnit64,
)


def _close(a: Float64, b: Float64, tolerance: Float64) raises:
    assert_almost_equal(a, b, atol=tolerance * abs(b), rtol=0)


def _unit(word: String) -> DurationUnit64:
    if word == "wk":
        return WEEK64
    return DAY64


struct _Group(Copyable, Movable):
    var name: String
    var unit: DurationUnit64
    var times: List[Duration64]
    var events: List[Bool]

    def __init__(out self, line: String) raises:
        var parts = line.split(" ")
        self.name = String(parts[0])
        self.unit = _unit(String(parts[1]))
        self.times = List[Duration64]()
        self.events = List[Bool]()
        for at in range(2, len(parts)):
            var word = String(parts[at])
            var censored = word.endswith("+")
            var number = String(word.removesuffix("+"))
            self.times.append(Duration64(atof(number), self.unit))
            self.events.append(not censored)


def _groups() raises -> List[_Group]:
    var out = List[_Group]()
    var text = open("assets/parametric/parametric_data.txt", "r").read()
    for line in text.splitlines():
        out.append(_Group(String(line)))
    return out^


def _expected(
    name: String,
    kind: String,
    path: String = "assets/parametric/parametric_expected.txt",
) raises -> List[List[Float64]]:
    var out = List[List[Float64]]()
    var text = open(path, "r").read()
    for line in text.splitlines():
        var parts = line.split(" ")
        if String(parts[0]) != name or String(parts[1]) != kind:
            continue
        var row = List[Float64]()
        for at in range(2, len(parts)):
            row.append(atof(String(parts[at])))
        out.append(row^)
    return out^


def test_exponential() raises:
    var groups = _groups()
    assert_equal(len(groups), 4)
    for ref group in groups:
        var row = _expected(group.name, "exponential")[0].copy()
        var fit = fit_exponential(group.times, group.events)
        _close(fit.scale.to(group.unit), row[0], 1e-14)
        _close(fit.scale_error.to(group.unit), row[1], 1e-14)
        _close(fit.log_likelihood(group.unit), row[2], 1e-14)
        assert_equal(fit.shape, 1.0)
        assert_equal(fit.parameters, 1)
        _close(fit.aic(group.unit), 2.0 - 2.0 * row[2], 1e-14)


def test_weibull() raises:
    var groups = _groups()
    for ref group in groups:
        var row = _expected(group.name, "weibull")[0].copy()
        var fit = fit_weibull(group.times, group.events)
        var u = group.unit
        _close(fit.scale.to(u), row[0], 1e-13)
        _close(fit.shape, row[1], 1e-13)
        _close(fit.scale_error.to(u), row[2], 1e-12)
        _close(fit.shape_error, row[3], 1e-12)
        _close(fit.covariance.to(u), row[4], 1e-11)
        _close(fit.log_likelihood(u), row[5], 1e-14)
        assert_equal(fit.parameters, 2)
        var test = constant_hazard_test(group.times, group.events)
        var statistic = _expected(group.name, "test")[0][0]
        _close(test[0], statistic, 1e-11)
        var p = _expected(group.name, "test", LIFELINES)[0][0]
        _close(test[1], p, 1e-11)
        var median = _expected(group.name, "median")[0].copy()
        _close(fit.median().to(u), median[0], 1e-13)
        var band = fit.quantile_interval(0.5)
        _close(band[0].to(u), median[1], 1e-12)
        _close(band[1].to(u), median[2], 1e-12)
        var quantile = _expected(group.name, "quantile")[0].copy()
        _close(fit.quantile(0.2).to(u), quantile[0], 1e-13)
        band = fit.quantile_interval(0.2)
        _close(band[0].to(u), quantile[1], 1e-12)
        _close(band[1].to(u), quantile[2], 1e-12)
        var probes = _expected(group.name, "at")
        assert_equal(len(probes), 4)
        for p in probes:
            var t = Duration64(p[0], u)
            _close(fit.survival(t), p[1], 1e-13)
            _close(fit.survival_error(t), p[2], 1e-11)
            var interval = fit.survival_interval(t)
            _close(interval[0], p[3], 1e-11)
            _close(interval[1], p[4], 1e-11)
            # Events for each unit of the group's time.
            var seconds = Duration64(1.0, u).to(SECOND)
            _close(fit.hazard(t).to(PER_SECOND) * seconds, p[5], 1e-13)


comptime LIFELINES = "assets/parametric/parametric_lifelines.txt"


def test_reference_against_lifelines() raises:
    # lifelines fits by a search that stops early: the scales and shapes
    # agree to 1e-5, the errors to 1e-4 and the covariance to 1e-3.
    for name in ["drug", "placebo", "rising", "falling"]:
        var exponential = _expected(name, "exponential")[0].copy()
        var theirs = _expected(name, "exponential", LIFELINES)[0].copy()
        _close(theirs[0], exponential[0], 1e-5)
        _close(theirs[1], exponential[1], 1e-4)
        _close(theirs[2], exponential[2], 1e-10)
        var weibull = _expected(name, "weibull")[0].copy()
        var fit = _expected(name, "weibull", LIFELINES)[0].copy()
        _close(fit[0], weibull[0], 1e-5)
        _close(fit[1], weibull[1], 1e-5)
        _close(fit[2], weibull[2] * weibull[2], 1e-4)
        _close(fit[3], weibull[3] * weibull[3], 1e-4)
        _close(fit[4], weibull[4], 1e-3)
        _close(fit[5], weibull[5], 1e-10)
        _close(fit[6], _expected(name, "median")[0][0], 1e-5)
        var probes = _expected(name, "at")
        var points = _expected(name, "at", LIFELINES)
        assert_equal(len(points), 4)
        for i in range(4):
            assert_equal(points[i][0], probes[i][0])
            assert_almost_equal(points[i][1], probes[i][1], atol=1e-5)
            _close(points[i][2], probes[i][2], 1e-3)


def test_by_hand() raises:
    # Three events at 1, 2 and 3 weeks and one censored at 4: the
    # exponential scale is 10 / 3 weeks.
    var times: List[Duration64] = [
        Duration64(1, WEEK64),
        Duration64(2, WEEK64),
        Duration64(3, WEEK64),
        Duration64(4, WEEK64),
    ]
    var events: List[Bool] = [True, True, True, False]
    var fit = fit_exponential(times, events)
    _close(fit.scale.to(WEEK64), 10.0 / 3.0, 1e-15)
    _close(fit.median().to(WEEK64), 10.0 / 3.0 * log(2.0), 1e-15)
    _close(fit.quantile(0.5).to(WEEK64), 10.0 / 3.0 * log(2.0), 1e-15)
    # The hazard is constant, 3 / 10 for each week, and the survival at
    # the scale is 1 / e.
    _close(
        fit.hazard(Duration64(0, WEEK64)).to(PER_SECOND), 0.3 / 604800, 1e-15
    )
    _close(fit.survival(fit.scale), 0.36787944117144233, 1e-15)
    _close(fit.cumulative_hazard(fit.scale), 1.0, 1e-15)
    # At 0 the survival is 1 and has no error.
    var zero = Duration64(0, WEEK64)
    assert_equal(fit.survival(zero), 1.0)
    assert_equal(fit.survival_error(zero), 0.0)
    var at_zero = fit.survival_interval(zero)
    assert_equal(at_zero[0], 1.0)
    assert_equal(at_zero[1], 1.0)
    # The log-likelihood in weeks and in days differs by d ln 7.
    _close(
        fit.log_likelihood(DAY64) - fit.log_likelihood(WEEK64),
        -3.0 * log(7.0),
        1e-13,
    )
    # A patient censored at 0 adds nothing.
    var more = times.copy()
    more.append(Duration64(0, WEEK64))
    var flags = events.copy()
    flags.append(False)
    var again = fit_exponential(more, flags)
    assert_equal(again.scale.to(SECOND), fit.scale.to(SECOND))
    var weibull = fit_weibull(times, events)
    var also = fit_weibull(more, flags)
    _close(also.shape, weibull.shape, 1e-15)
    # A rising hazard is 0 at time 0, and a falling one infinite.
    assert_true(weibull.shape > 1)
    assert_equal(weibull.hazard(zero).to(PER_SECOND), 0.0)
    var falling = ParametricFit(
        Duration64(1, WEEK64),
        0.5,
        Duration64(0.1, WEEK64),
        0.05,
        Duration64(0, WEEK64),
        3,
        2,
        0.0,
    )
    assert_equal(falling.hazard(zero).to(PER_SECOND), inf[DType.float64]())
    assert_equal(falling.cumulative_hazard(zero), 0.0)
    # Far out, the survival is 0, but four patients leave its interval
    # wide.
    var far = Duration64(1e6, WEEK64)
    assert_equal(weibull.survival(far), 0.0)
    var tail = weibull.survival_interval(far)
    assert_equal(tail[0], 0.0)
    assert_true(tail[1] > 0.0 and tail[1] < 1.0)


def test_drawing() raises:
    var groups = _groups()
    var curves = List[SurvivalCurve]()
    curves.append(kaplan_meier(groups[0].times, groups[0].events))
    var top = Duration64(40, WEEK64)
    var image = survival_image(
        curves, [Rgba(0, 0, 1, 1)], top, Duration64(10, WEEK64), 200, 100
    )
    var before = image.get_pixel(3, 0)
    draw_fit(
        image,
        fit_weibull(groups[0].times, groups[0].events),
        Rgba(1, 0, 0, 1),
        top,
    )
    # The first dash starts at the top left, at a survival of 1.
    var red = image.get_pixel(3, 0)
    assert_false(red == before)
    assert_true(red == Color(255, 0, 0))
    # The dash is off from x = 6 to 11.
    var count = 0
    for y in range(100):
        if image.get_pixel(8, y) == Color(255, 0, 0):
            count += 1
    assert_equal(count, 0)


def test_errors() raises:
    var t: List[Duration64] = [Duration64(1, WEEK64), Duration64(2, WEEK64)]
    with assert_raises(contains="one event or more"):
        _ = fit_exponential(t, [False, False])
    with assert_raises(contains="each event after 0"):
        _ = fit_weibull(
            [Duration64(0, WEEK64), Duration64(2, WEEK64)], [True, True]
        )
    with assert_raises(contains="one patient or more"):
        _ = fit_weibull(t, [True])
    with assert_raises(contains="before the largest time"):
        _ = fit_weibull(t, [False, True])
    with assert_raises(contains="before the largest time"):
        _ = constant_hazard_test(
            [Duration64(2, WEEK64), Duration64(2, WEEK64)], [True, True]
        )
    var fit = fit_weibull(t, [True, True])
    var bad: List[Float64] = [-1.0, inf[DType.float64](), nan[DType.float64]()]
    for v in bad:
        with assert_raises(contains="0 or more"):
            _ = fit.survival(Duration64(v, WEEK64))
    var survivals: List[Float64] = [0.0, 1.0, nan[DType.float64]()]
    for s in survivals:
        with assert_raises(contains="above 0, below 1"):
            _ = fit.quantile(s)
        with assert_raises(contains="above 0, below 1"):
            _ = fit.quantile_interval(s)
    var groups = _groups()
    var curves = List[SurvivalCurve]()
    curves.append(kaplan_meier(groups[0].times, groups[0].events))
    var image = survival_image(
        curves,
        [Rgba(0, 0, 1, 1)],
        Duration64(40, WEEK64),
        Duration64(10, WEEK64),
        200,
        100,
    )
    var tops: List[Float64] = [0.0, inf[DType.float64]()]
    for v in tops:
        with assert_raises(contains="must be positive"):
            draw_fit(image, fit, Rgba(1, 0, 0, 1), Duration64(v, WEEK64))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
