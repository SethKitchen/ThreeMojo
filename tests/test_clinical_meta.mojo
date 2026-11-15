# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Meta-analysis and forest plots.

`assets/meta/meta_expected.txt` holds the results of statsmodels 0.15.0
and scipy 1.18.1 on the BCG vaccine trials of `assets/meta/bcg.txt`. See
`assets/meta/make_meta.py`. The test builds the prediction interval from
their tau^2, standard error and t point.
"""

from extensions.clinical.meta import (
    MetaAnalysis,
    egger_test,
    forest_image,
    funnel_image,
    log_odds_ratio,
    log_risk_ratio,
    meta_analysis,
)
from extensions.numerics.distributions import student_t_quantile
from render.framebuffer import Framebuffer
from std.math import inf, log, nan, sqrt
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


def _trials() raises -> Tuple[List[Float64], List[Float64]]:
    var effects = List[Float64]()
    var variances = List[Float64]()
    var text = open("assets/meta/bcg.txt", "r").read()
    for line in text.splitlines():
        var words = String(line).split(",")
        var study = log_risk_ratio(
            atol(String(words[1])),
            atol(String(words[1])) + atol(String(words[2])),
            atol(String(words[3])),
            atol(String(words[3])) + atol(String(words[4])),
        )
        effects.append(study[0])
        variances.append(study[1])
    return (effects^, variances^)


def test_bcg() raises:
    var trials = _trials()
    var expected = List[List[Float64]]()
    var text = open("assets/meta/meta_expected.txt", "r").read()
    for line in text.splitlines():
        expected.append(_numbers(String(line)))
    for i in range(13):
        assert_almost_equal(trials[0][i], expected[0][2 * i], rtol=1e-14)
        assert_almost_equal(trials[1][i], expected[0][2 * i + 1], rtol=1e-14)
    var result = meta_analysis(trials[0], trials[1])
    assert_equal(result.studies, 13)
    var pooled = [result.fixed.copy(), result.random.copy()]
    for m in range(2):
        ref row = expected[1 + m]
        assert_almost_equal(pooled[m].estimate, row[0], rtol=1e-12)
        assert_almost_equal(pooled[m].standard_error, row[1], rtol=1e-12)
        assert_almost_equal(pooled[m].lower, row[2], rtol=1e-12)
        assert_almost_equal(pooled[m].upper, row[3], rtol=1e-12)
        assert_almost_equal(pooled[m].z, row[0] / row[1], rtol=1e-12)
        assert_almost_equal(pooled[m].p_value, row[4], rtol=1e-10)
    ref spread = expected[3]
    assert_almost_equal(result.q, spread[0], rtol=1e-12)
    assert_almost_equal(result.q_p_value, spread[1], rtol=1e-10)
    assert_almost_equal(result.i_squared, spread[2], rtol=1e-12)
    assert_almost_equal(result.tau_squared, spread[3], rtol=1e-12)
    for i in range(13):
        assert_almost_equal(result.fixed_weights[i], expected[4][i], rtol=1e-12)
        assert_almost_equal(
            result.random_weights[i], expected[5][i], rtol=1e-12
        )
    # The prediction interval of Higgins and others (2009) is the random
    # effect -+ t sqrt(tau^2 + se^2), with scipy's t of 11 degrees of
    # freedom.
    var t = expected[6][0]
    assert_almost_equal(student_t_quantile(0.975, 11.0), t, rtol=1e-11)
    var se = expected[2][1]
    var half = t * sqrt(spread[3] + se * se)
    var band = result.prediction_interval()
    assert_almost_equal(band[0], expected[2][0] - half, rtol=1e-12)
    assert_almost_equal(band[1], expected[2][0] + half, rtol=1e-12)


def test_by_hand() raises:
    # Effects 0 and 2, each of variance 1: a fixed effect of 1 with a
    # standard error of sqrt(1/2), Q = 2, tau^2 = (2 - 1) / (2 - 1) = 1,
    # and I^2 = 1/2. The random weights are 1/2, so its error is 1.
    var two = meta_analysis([0.0, 2.0], [1.0, 1.0])
    assert_equal(two.fixed.estimate, 1.0)
    assert_almost_equal(two.fixed.standard_error, sqrt(0.5), rtol=1e-15)
    assert_equal(two.q, 2.0)
    assert_equal(two.tau_squared, 1.0)
    assert_equal(two.i_squared, 0.5)
    assert_equal(two.random.estimate, 1.0)
    assert_equal(two.random.standard_error, 1.0)
    assert_equal(two.fixed_weights[0], 0.5)
    with assert_raises(contains="three studies or more"):
        _ = two.prediction_interval()
    # Equal effects: no heterogeneity, and the two models agree.
    var same = meta_analysis([0.5, 0.5, 0.5], [0.1, 0.2, 0.4])
    assert_equal(same.q, 0.0)
    assert_equal(same.tau_squared, 0.0)
    assert_equal(same.i_squared, 0.0)
    assert_equal(same.q_p_value, 1.0)
    assert_almost_equal(same.random.estimate, 0.5, rtol=1e-15)
    # A risk ratio: 10 of 30 against 5 of 45 is 3. An odds ratio: 4, with
    # Woolf's variance.
    var risk = log_risk_ratio(10, 30, 5, 45)
    assert_almost_equal(risk[0], log(3.0), rtol=1e-15)
    assert_almost_equal(risk[1], 0.1 - 1.0 / 30 + 0.2 - 1.0 / 45, rtol=1e-14)
    var odds = log_odds_ratio(10, 30, 5, 45)
    assert_almost_equal(odds[0], log(4.0), rtol=1e-15)
    assert_almost_equal(odds[1], 0.375, rtol=1e-15)
    # A cell of 0 adds a half to each cell.
    var empty: List[List[Int]] = [
        [0, 10, 5, 10],
        [10, 10, 5, 10],
        [5, 10, 0, 10],
        [5, 10, 10, 10],
    ]
    var expected: List[Float64] = [
        log(0.5 * 5.5 / (10.5 * 5.5)),
        log(10.5 * 5.5 / (0.5 * 5.5)),
        log(5.5 * 10.5 / (5.5 * 0.5)),
        log(5.5 * 0.5 / (5.5 * 10.5)),
    ]
    for c in range(4):
        ref t = empty[c]
        assert_almost_equal(
            log_odds_ratio(t[0], t[1], t[2], t[3])[0], expected[c], rtol=1e-14
        )


def test_refusals() raises:
    with assert_raises(contains="2 to 160 studies"):
        _ = meta_analysis([1.0], [1.0])
    with assert_raises(contains="2 to 160 studies"):
        _ = meta_analysis([1.0, 2.0], [1.0])
    var many = List[Float64](length=161, fill=1.0)
    with assert_raises(contains="2 to 160 studies"):
        _ = meta_analysis(many, many)
    with assert_raises(contains="effects of a meta-analysis must be finite"):
        _ = meta_analysis([1.0, inf[DType.float64]()], [1.0, 1.0])
    var variances: List[Float64] = [
        0.0,
        inf[DType.float64](),
        nan[DType.float64](),
    ]
    for v in variances:
        with assert_raises(contains="must be positive"):
            _ = meta_analysis([1.0, 2.0], [1.0, v])
    var tables: List[List[Int]] = [
        [1, 0, 1, 5],
        [1, 5, 1, 0],
        [-1, 5, 1, 5],
        [1, 5, -1, 5],
        [6, 5, 1, 5],
        [1, 5, 6, 5],
    ]
    for t in tables:
        with assert_raises(contains="events from 0 to its count"):
            _ = log_risk_ratio(t[0], t[1], t[2], t[3])


def _rgb(image: Framebuffer, x: Int, y: Int) -> Tuple[Int, Int, Int]:
    var at = (y * image.width + x) * 4
    return (
        Int(image.pixels[at]),
        Int(image.pixels[at + 1]),
        Int(image.pixels[at + 2]),
    )


def test_forest_image() raises:
    # Effects 0 and 2 of variance 1: intervals from -1.96 to 3.96, so the
    # range is -2.258 to 4.258 with its margin.
    var effects: List[Float64] = [0.0, 2.0]
    var variances: List[Float64] = [1.0, 1.0]
    var result = meta_analysis(effects, variances)
    var image = forest_image(effects, variances, result, 201)
    assert_equal(image.height, 24 * 5)
    var low = -1.96 - 0.05 * 5.92
    var span = 5.92 * 1.1
    var zero = Int((0.0 - low) / span * 200 + 0.5)
    var two = Int((2.0 - low) / span * 200 + 0.5)
    var one = Int((1.0 - low) / span * 200 + 0.5)
    # The zero line, between the rows.
    assert_true(_rgb(image, zero, 12) == (153, 153, 161))
    # The square of the second study, and its interval line.
    assert_true(_rgb(image, two + 3, 48 + 3) == (61, 61, 66))
    assert_true(_rgb(image, two + 30, 48) == (61, 61, 66))
    # The random diamond at its center, and the fixed one.
    assert_true(_rgb(image, one, 96) == (38, 102, 217))
    assert_true(_rgb(image, one + 5, 72) == (153, 153, 161))
    with assert_raises(contains="its own studies"):
        _ = forest_image([0.0, 2.0, 1.0], [1.0, 1.0, 1.0], result, 201)
    var widths: List[Int] = [127, 4097]
    for w in widths:
        with assert_raises(contains="pixels wide"):
            _ = forest_image(effects, variances, result, w)


def test_egger() raises:
    var trials = _trials()
    var line = open("assets/meta/egger_expected.txt", "r").read()
    var expected = _numbers(String(line.splitlines()[0]))
    var test = egger_test(trials[0], trials[1])
    assert_almost_equal(test.intercept, expected[0], rtol=1e-12)
    assert_almost_equal(test.standard_error, expected[1], rtol=1e-12)
    assert_almost_equal(test.t, expected[2], rtol=1e-12)
    assert_almost_equal(test.p_value, expected[3], rtol=1e-11)
    assert_almost_equal(test.slope, expected[4], rtol=1e-12)
    with assert_raises(contains="three studies or more"):
        _ = egger_test([0.0, 1.0], [1.0, 1.0])
    with assert_raises(contains="constant or collinear"):
        _ = egger_test([0.0, 1.0, 2.0], [1.0, 1.0, 1.0])


def test_funnel_image() raises:
    # Effects 0, 2 and 1 of variances 1, 1 and 4: a fixed effect of 1 at
    # the middle column, and an error of 2.1 at the bottom.
    var effects: List[Float64] = [0.0, 2.0, 1.0]
    var variances: List[Float64] = [1.0, 1.0, 4.0]
    var result = meta_analysis(effects, variances)
    var image = funnel_image(effects, variances, result, 101, 101)
    assert_true(_rgb(image, 50, 30) == (38, 102, 217))
    # The first study: effect 0 at x = 39, error 1 at y = 48.
    assert_true(_rgb(image, 41, 48) == (61, 61, 66))
    with assert_raises(contains="its own studies"):
        _ = funnel_image([0.0, 2.0], [1.0, 1.0], result, 101, 101)
    var sizes: List[Int] = [63, 4097, 64, 64]
    var heights: List[Int] = [64, 64, 63, 4097]
    for n in range(4):
        with assert_raises(contains="pixels a side"):
            _ = funnel_image(effects, variances, result, sizes[n], heights[n])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
