# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The calibration and decision curves of risk models.

`assets/calibration/calibration_expected.txt` holds the values of
scikit-learn, scipy, statsmodels and dcurves for a synthetic cohort. See
`assets/calibration/make_calibration.py`.
"""

from extensions.clinical.calibration import (
    CalibrationFit,
    DecisionCurve,
    RiskGroup,
    brier_score,
    calibration_fit,
    calibration_image,
    decision_curve,
    decision_curve_image,
    hosmer_lemeshow,
    net_benefit,
    recalibrate,
    risk_groups,
    scaled_brier_score,
)
from extensions.imaging.overlay import draw_line
from extensions.imaging.transfer import Rgba
from render.framebuffer import Color, Framebuffer
from std.math import inf, log, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

comptime BLUE = Rgba(0.2, 0.4, 0.8, 1)
comptime RED = Rgba(0.8, 0.2, 0.2, 1)


struct _Fixture(Movable):
    var risks: List[Float64]
    var outcomes: List[Bool]
    var rows: Dict[String, List[Float64]]
    var groups: List[List[Float64]]

    def __init__(out self) raises:
        self.risks = List[Float64]()
        self.outcomes = List[Bool]()
        self.rows = Dict[String, List[Float64]]()
        self.groups = List[List[Float64]]()
        var text = open(
            "assets/calibration/calibration_expected.txt", "r"
        ).read()
        for line in text.splitlines():
            var parts = line.split(" ")
            var name = String(parts[0])
            var values = List[Float64]()
            for at in range(1, len(parts)):
                values.append(atof(String(parts[at])))
            if name == "groups":
                self.groups.append(values^)
            else:
                self.rows[name] = values^
        self.risks = self.rows["risks"].copy()
        for v in self.rows["outcomes"]:
            self.outcomes.append(v == 1.0)


def _close(a: Float64, b: Float64, tolerance: Float64) raises:
    assert_almost_equal(a, b, atol=tolerance * abs(b), rtol=0)


def _color(image: Framebuffer, x: Int, y: Int) -> Tuple[UInt8, UInt8, UInt8]:
    var at = (y * image.width + x) * 4
    return (image.pixels[at], image.pixels[at + 1], image.pixels[at + 2])


def _is(image: Framebuffer, x: Int, y: Int, color: Rgba) raises:
    var c = _color(image, x, y)
    var probe = Framebuffer(1, 1, Color(0, 0, 0))
    draw_line(probe, 0, 0, 0, 0, color)
    assert_equal(c[0], probe.pixels[0])
    assert_equal(c[1], probe.pixels[1])
    assert_equal(c[2], probe.pixels[2])


def test_against_references() raises:
    var data = _Fixture()
    assert_equal(len(data.risks), 300)
    _close(brier_score(data.risks, data.outcomes), data.rows["brier"][0], 1e-14)
    _close(
        scaled_brier_score(data.risks, data.outcomes),
        data.rows["brier"][1],
        1e-13,
    )
    var groups = risk_groups(data.risks, data.outcomes, 10)
    assert_equal(len(groups), 10)
    for g in range(10):
        ref row = data.groups[g]
        assert_equal(groups[g].count, Int(row[0]))
        _close(groups[g].mean_risk(), row[1], 1e-14)
        assert_equal(groups[g].events, Int(row[2]))
        _close(groups[g].observed(), row[3], 1e-15)
    var test = hosmer_lemeshow(data.risks, data.outcomes, 10)
    _close(test.statistic, data.rows["hosmer"][0], 1e-12)
    assert_equal(test.freedom, 8)
    _close(test.p_value, data.rows["hosmer"][2], 1e-10)
    var fit = calibration_fit(data.risks, data.outcomes)
    ref slope = data.rows["slope"]
    _close(fit.intercept, slope[0], 1e-11)
    _close(fit.slope, slope[1], 1e-11)
    _close(fit.intercept_error, slope[2], 1e-11)
    _close(fit.slope_error, slope[3], 1e-11)
    ref large = data.rows["large"]
    _close(fit.in_the_large, large[0], 1e-12)
    _close(fit.in_the_large_error, large[1], 1e-12)
    _close(fit.expected_over_observed, large[2], 1e-14)
    var curve = decision_curve(
        data.risks, data.outcomes, data.rows["thresholds"]
    )
    var count = len(data.rows["thresholds"])
    assert_equal(count, 32)
    for i in range(count):
        assert_almost_equal(
            curve.model[i], data.rows["model"][i], atol=1e-15, rtol=0
        )
        assert_almost_equal(
            curve.treat_all[i], data.rows["all"][i], atol=1e-14, rtol=0
        )
        assert_almost_equal(
            curve.avoided[i], data.rows["avoided"][i], atol=1e-12, rtol=0
        )
        assert_equal(
            net_benefit(data.risks, data.outcomes, curve.thresholds[i]),
            curve.model[i],
        )
    _close(curve.prevalence, 100.0 / 300.0, 1e-15)


def test_by_hand() raises:
    var risks: List[Float64] = [0.2, 0.8]
    var outcomes: List[Bool] = [False, True]
    _close(brier_score(risks, outcomes), 0.04, 1e-15)
    _close(scaled_brier_score(risks, outcomes), 0.84, 1e-15)
    # Seven patients make groups of 3, 2 and 2, ties in their order.
    var seven: List[Float64] = [0.5, 0.1, 0.5, 0.3, 0.9, 0.5, 0.2]
    var marks: List[Bool] = [True, False, False, True, True, True, False]
    var groups = risk_groups(seven, marks, 3)
    assert_equal(groups[0].count, 3)
    assert_equal(groups[1].count, 2)
    assert_equal(groups[2].count, 2)
    _close(groups[0].expected, 0.6, 1e-15)
    assert_equal(groups[0].events, 1)
    # The first two of the three ties of 0.5.
    _close(groups[1].expected, 1.0, 1e-15)
    assert_equal(groups[1].events, 1)
    assert_equal(groups[2].events, 2)
    # Groups whose events are what the model expects give a statistic of 0.
    var even: List[Float64] = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
    var alternate: List[Bool] = [True, False, True, False, True, False]
    var none = hosmer_lemeshow(even, alternate, 3)
    assert_equal(none.statistic, 0)
    assert_equal(none.freedom, 1)
    assert_equal(none.p_value, 1)


def test_perfect_calibration() raises:
    # A quarter of the patients of risk 0.25 and three quarters of those of
    # 0.75 have the outcome: the risks are the fitted risks.
    var risks: List[Float64] = [0.25, 0.25, 0.25, 0.25, 0.75, 0.75, 0.75, 0.75]
    var outcomes: List[Bool] = [
        True,
        False,
        False,
        False,
        True,
        True,
        True,
        False,
    ]
    var fit = calibration_fit(risks, outcomes)
    assert_almost_equal(fit.intercept, 0.0, atol=1e-12)
    assert_almost_equal(fit.slope, 1.0, atol=1e-12)
    assert_almost_equal(fit.in_the_large, 0.0, atol=1e-15)
    assert_true(fit.converged)
    assert_equal(fit.expected_over_observed, 1.0)
    # The information is 8 * 3 / 16, so the error is sqrt(2 / 3).
    _close(fit.in_the_large_error, (2.0 / 3.0) ** 0.5, 1e-14)
    var same = recalibrate(risks, fit)
    for i in range(8):
        assert_almost_equal(same[i], risks[i], atol=1e-12)
    # An intercept of ln 3 turns a risk of a half into three quarters.
    var shift = CalibrationFit()
    shift.intercept = log(3.0)
    shift.slope = 1.0
    _close(recalibrate([0.5], shift)[0], 0.75, 1e-15)
    shift.slope = 2.0
    _close(recalibrate([0.25], shift)[0], 0.25, 1e-15)
    shift.intercept = -40.0
    assert_true(recalibrate([0.5], shift)[0] < 1e-17)


def test_net_benefit() raises:
    var risks: List[Float64] = [0.1, 0.3, 0.6, 0.9]
    var outcomes: List[Bool] = [False, False, True, True]
    # At 0.3: two true and one false positive, the false weighing 3 / 7.
    _close(net_benefit(risks, outcomes, 0.3), 0.5 - 0.25 * 3.0 / 7.0, 1e-15)
    var curve = decision_curve(risks, outcomes, [0.2, 0.5, 0.95])
    _close(curve.model[1], 0.5, 1e-15)
    assert_equal(curve.treat_all[1], 0)
    _close(curve.avoided[1], 0.5, 1e-15)
    _close(curve.treat_all[2], 0.5 - 0.5 * 19.0, 1e-14)


def test_images() raises:
    var size = 101
    # A group at (0.5, 0.5) and one at a risk of 0.25 with 3 of 4 events.
    var groups: List[RiskGroup] = [RiskGroup(4, 1.0, 3), RiskGroup(2, 1.0, 1)]
    var image = calibration_image([groups.copy()], [BLUE], size)
    assert_equal(image.width, 101)
    _is(image, 25, 25, BLUE)
    _is(image, 22, 25, BLUE)
    _is(image, 25, 28, BLUE)
    _is(image, 50, 50, BLUE)
    _is(image, 50, 47, BLUE)
    _is(image, 38, 38, BLUE)
    _is(image, 90, 10, Rgba(0.6, 0.6, 0.63, 1))
    _is(image, 10, 95, Rgba(0.84, 0.84, 0.86, 1))
    _is(image, 0, 60, Rgba(0.24, 0.24, 0.26, 1))
    # The net benefit of 0.5 at a threshold of 0.5 is the top edge, and 0
    # is 80 percent of the way down.
    var risks: List[Float64] = [0.2, 0.4, 0.6, 0.8]
    var outcomes: List[Bool] = [False, False, True, True]
    var curve = decision_curve(risks, outcomes, [0.1, 0.5])
    var chart = decision_curve_image([curve.copy()], [RED], 101, 101)
    _is(chart, 0, 9, RED)
    _is(chart, 100, 0, RED)
    _is(chart, 100, 80, Rgba(0.35, 0.35, 0.38, 1))
    _is(chart, 50, 80, Rgba(0.6, 0.6, 0.63, 1))
    # Light lines at the risks 0.2, 0.3 and 0.4, and at each tenth down.
    var light = Rgba(0.84, 0.84, 0.86, 1)
    _is(chart, 25, 95, light)
    _is(chart, 75, 95, light)
    _is(chart, 12, 90, light)
    _is(chart, 12, 95, Rgba(1, 1, 1, 1))
    _is(chart, 100, 95, Rgba(0.24, 0.24, 0.26, 1))
    # Two models, and a treat-all line far below the bottom edge.
    var steep = decision_curve(risks, outcomes, [0.5, 0.999])
    var both = decision_curve_image(
        [steep.copy(), steep.copy()], [RED, BLUE], 200, 80
    )
    assert_equal(both.height, 80)
    _is(both, 0, 0, BLUE)


def test_errors() raises:
    var risks: List[Float64] = [0.2, 0.4, 0.6, 0.8]
    var outcomes: List[Bool] = [False, True, False, True]
    with assert_raises(contains="one risk for each"):
        _ = brier_score(List[Float64](), List[Bool]())
    with assert_raises(contains="one risk for each"):
        _ = brier_score(risks, [True])
    with assert_raises(contains="not at either end"):
        _ = brier_score([0.0, 0.5], [True, False])
    with assert_raises(contains="not at either end"):
        _ = brier_score([1.0, 0.5], [True, False])
    with assert_raises(contains="not at either end"):
        _ = brier_score([nan[DType.float64](), 0.5], [True, False])
    with assert_raises(contains="with and without"):
        _ = scaled_brier_score(risks, [False, False, False, False])
    with assert_raises(contains="with and without"):
        _ = calibration_fit(risks, [True, True, True, True])
    with assert_raises(contains="from 2 to 100"):
        _ = risk_groups(risks, outcomes, 1)
    with assert_raises(contains="from 2 to 100"):
        _ = risk_groups(risks, outcomes, 5)
    var many = List[Float64]()
    var marks = List[Bool]()
    for i in range(202):
        many.append(Float64(i + 1) / 203.0)
        marks.append(i % 2 == 0)
    with assert_raises(contains="from 2 to 100"):
        _ = risk_groups(many, marks, 101)
    with assert_raises(contains="3 groups or more"):
        _ = hosmer_lemeshow(risks, outcomes, 2)
    with assert_raises(contains="separate"):
        _ = calibration_fit(risks, [False, False, True, True])
    with assert_raises(contains="constant"):
        _ = calibration_fit([0.3, 0.3, 0.3], [False, True, False])
    var fit = CalibrationFit()
    fit.intercept = nan[DType.float64]()
    with assert_raises(contains="finite intercept"):
        _ = recalibrate(risks, fit)
    fit.intercept = 0.0
    fit.slope = inf[DType.float64]()
    with assert_raises(contains="finite intercept"):
        _ = recalibrate(risks, fit)
    fit.slope = 1.0
    with assert_raises(contains="not at either end"):
        _ = recalibrate([1.5], fit)
    with assert_raises(contains="not at either end"):
        _ = recalibrate([-0.5], fit)
    with assert_raises(contains="between 0 and 1"):
        _ = net_benefit(risks, outcomes, 0.0)
    with assert_raises(contains="between 0 and 1"):
        _ = net_benefit(risks, outcomes, 1.0)
    with assert_raises(contains="one patient with"):
        _ = decision_curve(risks, [False, False, False, False], [0.1, 0.2])
    with assert_raises(contains="2 to 1000"):
        _ = decision_curve(risks, outcomes, [0.1])
    var fine = List[Float64]()
    for i in range(1001):
        fine.append(Float64(i + 1) / 1002.0)
    with assert_raises(contains="2 to 1000"):
        _ = decision_curve(risks, outcomes, fine)
    with assert_raises(contains="between 0 and 1"):
        _ = decision_curve(risks, outcomes, [0.1, 1.2])
    with assert_raises(contains="must rise"):
        _ = decision_curve(risks, outcomes, [0.2, 0.2])
    var groups = risk_groups(risks, outcomes, 2)
    with assert_raises(contains="one color for each"):
        _ = calibration_image(List[List[RiskGroup]](), List[Rgba](), 100)
    with assert_raises(contains="one color for each"):
        _ = calibration_image([groups.copy()], [BLUE, RED], 100)
    with assert_raises(contains="64 to 4096"):
        _ = calibration_image([groups.copy()], [BLUE], 63)
    with assert_raises(contains="64 to 4096"):
        _ = calibration_image([groups.copy()], [BLUE], 4097)
    with assert_raises(contains="groups for each"):
        _ = calibration_image([List[RiskGroup]()], [BLUE], 100)
    var curve = decision_curve(risks, outcomes, [0.1, 0.5])
    with assert_raises(contains="one color for each"):
        _ = decision_curve_image(List[DecisionCurve](), List[Rgba](), 100, 100)
    with assert_raises(contains="one color for each"):
        _ = decision_curve_image([curve.copy()], [BLUE, RED], 100, 100)
    var sides: List[Tuple[Int, Int]] = [
        (63, 100),
        (4097, 100),
        (100, 63),
        (100, 4097),
    ]
    for side in sides:
        with assert_raises(contains="64 to 4096"):
            _ = decision_curve_image([curve.copy()], [BLUE], side[0], side[1])
    var other = decision_curve(risks, outcomes, [0.1, 0.6])
    with assert_raises(contains="share thresholds"):
        _ = decision_curve_image([curve.copy(), other^], [BLUE, RED], 100, 100)
    var fewer = decision_curve(risks, [False, False, False, True], [0.1, 0.5])
    with assert_raises(contains="share thresholds"):
        _ = decision_curve_image([curve.copy(), fewer^], [BLUE, RED], 100, 100)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
