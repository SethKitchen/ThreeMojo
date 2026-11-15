# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Kaplan-Meier curves and the log-rank test.

`assets/survival/freireich_expected.txt` holds the results of lifelines
0.30.3 on the trial of Freireich and others (1963). See
`assets/survival/make_survival.py`.
"""

from extensions.clinical.survival import (
    LogRank,
    SurvivalCurve,
    WEEK64,
    kaplan_meier,
    log_rank_test,
    survival_image,
)
from extensions.imaging.transfer import Rgba
from render.framebuffer import Framebuffer
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Duration64, SECOND

comptime DRUG = (
    "6 6 6 6+ 7 9+ 10 10+ 11+ 13 16 17+ 19+ 20+ 22 23 25+ 32+ 32+ 34+ 35+"
)
comptime PLACEBO = "1 1 2 2 3 4 4 5 5 8 8 8 8 11 11 12 12 15 17 22 23"


def _group(text: String) raises -> Tuple[List[Duration64], List[Bool]]:
    var times = List[Duration64]()
    var events = List[Bool]()
    for part in text.split(" "):
        var text = String(part)
        var censored = text.endswith("+")
        var word = text
        if censored:
            word = String(text[byte = 0 : text.byte_length() - 1])
        times.append(Duration64(atof(word), WEEK64))
        events.append(not censored)
    return (times^, events^)


def _expected() raises -> List[List[String]]:
    var out = List[List[String]]()
    var text = open("assets/survival/freireich_expected.txt", "r").read()
    for line in text.splitlines():
        var words = List[String]()
        for part in line.split(" "):
            words.append(String(part))
        out.append(words^)
    return out^


def test_freireich() raises:
    var lines = _expected()
    var texts: List[String] = [DRUG, PLACEBO]
    for g in range(2):
        var group = _group(texts[g])
        var curve = kaplan_meier(group[0], group[1])
        ref row = lines[2 * g]
        var count = atol(row[1])
        assert_equal(len(curve.times), count)
        for i in range(count):
            assert_equal(curve.times[i].to(WEEK64), atof(row[2 + 4 * i]))
            assert_almost_equal(
                curve.survival[i], atof(row[3 + 4 * i]), atol=1e-14
            )
            var band = curve.interval(i)
            assert_almost_equal(band[0], atof(row[4 + 4 * i]), atol=1e-11)
            assert_almost_equal(band[1], atof(row[5 + 4 * i]), atol=1e-11)
        var median = curve.median()
        assert_true(median[0])
        assert_equal(median[1].to(WEEK64), atof(lines[2 * g + 1][1]))
    var drug = _group(DRUG)
    var placebo = _group(PLACEBO)
    var test = log_rank_test(drug[0], drug[1], placebo[0], placebo[1])
    assert_almost_equal(test.statistic, atof(lines[4][1]), rtol=1e-12)
    assert_almost_equal(test.p_value, atof(lines[4][2]), rtol=1e-11)
    assert_equal(test.observed[0], 9)
    assert_equal(test.observed[1], 21)
    assert_almost_equal(test.expected[0] + test.expected[1], 30.0)


def _weeks(values: List[Float64]) -> List[Duration64]:
    var out = List[Duration64]()
    for v in values:
        out.append(Duration64(v, WEEK64))
    return out^


def test_small_group() raises:
    # Five patients: events at 1, 2, 2 and 4, and one censored at 3.
    var times = _weeks([2.0, 1.0, 4.0, 3.0, 2.0])
    var events: List[Bool] = [True, True, True, False, True]
    var curve = kaplan_meier(times, events)
    assert_equal(len(curve.times), 3)
    assert_almost_equal(curve.survival[0], 0.8)
    assert_almost_equal(curve.survival[1], 0.4)
    assert_equal(curve.survival[2], 0.0)
    assert_equal(curve.at_risk[1], 4)
    assert_equal(curve.events[1], 2)
    assert_equal(curve.censored[0].to(WEEK64), 3.0)
    assert_equal(curve.patients, 5)
    assert_equal(curve.at(Duration64(0.5, WEEK64)), 1.0)
    assert_almost_equal(curve.at(Duration64(3.0, WEEK64)), 0.4)
    assert_equal(curve.at(Duration64(9.0, WEEK64)), 0.0)
    assert_equal(curve.median()[1].to(WEEK64), 2.0)
    var last = curve.interval(2)
    assert_equal(last[0], 0.0)
    assert_equal(last[1], 0.0)
    with assert_raises(contains="no time of that index"):
        _ = curve.interval(3)
    with assert_raises(contains="no time of that index"):
        _ = curve.interval(-1)
    # A group whose survival stays above a half has no median.
    var long = kaplan_meier(_weeks([1.0, 5.0, 6.0]), [True, False, False])
    assert_false(long.median()[0])
    # Two groups of one survival.
    var same = log_rank_test(times, events, times, events)
    assert_equal(same.statistic, 0.0)
    assert_equal(same.p_value, 1.0)
    # At 5 weeks one patient alone is at risk, and adds no variance.
    var alone = log_rank_test(
        _weeks([1.0, 5.0]), [True, True], _weeks([2.0]), [True]
    )
    assert_equal(alone.observed[0], 2)
    assert_true(alone.p_value > 0.1)
    with assert_raises(contains="change the risk"):
        _ = log_rank_test(_weeks([1.0]), [False], _weeks([2.0]), [False])
    # A group of censored patients has no time of an event.
    var censored = kaplan_meier(_weeks([2.0, 3.0]), [False, False])
    assert_equal(len(censored.times), 0)
    assert_equal(censored.at(Duration64(5.0, WEEK64)), 1.0)
    assert_false(censored.median()[0])
    # Group b is censored, once at the time of an event of group a. At 1
    # week, 2 of 4 are in a: a expects 1/2, with a variance of 1/4. At 2
    # weeks, 1 of 2: 1/2 and 1/4 again. So (2 - 1)^2 / (1/2) = 2.
    var relapse = _weeks([1.0, 2.0])
    var lost = _weeks([1.0, 3.0])
    var first = log_rank_test(relapse, [True, True], lost, [False, False])
    assert_equal(first.statistic, 2.0)
    assert_equal(first.observed[0], 2)
    assert_equal(first.observed[1], 0)
    assert_equal(first.expected[0], 1.0)
    var second = log_rank_test(lost, [False, False], relapse, [True, True])
    assert_equal(second.statistic, 2.0)
    assert_equal(second.observed[0], 0)
    assert_equal(second.expected[1], 1.0)


def test_refusals() raises:
    var times = _weeks([1.0, 2.0])
    with assert_raises(contains="one patient or more"):
        _ = kaplan_meier(List[Duration64](), List[Bool]())
    with assert_raises(contains="one patient or more"):
        _ = kaplan_meier(times, [True])
    var bad: List[Float64] = [-1.0, inf[DType.float64](), nan[DType.float64]()]
    for b in bad:
        with assert_raises(contains="0 or more, and finite"):
            _ = kaplan_meier(_weeks([b]), [True])
    with assert_raises(contains="one patient or more"):
        _ = log_rank_test(times, [True, True], times, [True])


def _rgb(image: Framebuffer, x: Int, y: Int) -> Tuple[Int, Int, Int]:
    var at = (y * image.width + x) * 4
    return (
        Int(image.pixels[at]),
        Int(image.pixels[at + 1]),
        Int(image.pixels[at + 2]),
    )


def test_survival_image() raises:
    var curves = List[SurvivalCurve]()
    curves.append(
        kaplan_meier(
            _weeks([2.0, 1.0, 4.0, 3.0, 2.0]),
            [True, True, True, False, True],
        )
    )
    var red = Rgba(1, 0, 0, 1)
    # Ten weeks over 100 pixels, and the survival over 100 pixels.
    var image = survival_image(
        curves,
        [red],
        Duration64(10, WEEK64),
        Duration64(5, WEEK64),
        101,
        101,
    )
    var white = (255, 255, 255)
    var gray = (214, 214, 219)
    assert_true(_rgb(image, 50, 33) == gray)
    assert_true(_rgb(image, 33, 70) == gray)
    assert_true(_rgb(image, 33, 33) == white)
    # At 1 week the survival falls from 1 to 0.8: 20 pixels down at x 10.
    assert_true(_rgb(image, 10, 15) == (255, 0, 0))
    assert_true(_rgb(image, 15, 20) == (255, 0, 0))
    # The censored patient at 3 weeks has a tick at a survival of 0.4.
    assert_true(_rgb(image, 30, 57) == (255, 0, 0))
    # From 4 weeks the survival is 0, along the bottom.
    assert_true(_rgb(image, 80, 100) == (255, 0, 0))
    # A curve without censoring, and a curve without an event: a drop to 0
    # at 1 week, and a tick at the top at 2 weeks.
    var pair = List[SurvivalCurve]()
    pair.append(kaplan_meier(_weeks([1.0]), [True]))
    pair.append(kaplan_meier(_weeks([2.0]), [False]))
    var blue = Rgba(0, 0, 1, 1)
    var both = survival_image(
        pair,
        [red, blue],
        Duration64(10, WEEK64),
        Duration64(5, WEEK64),
        101,
        101,
    )
    assert_true(_rgb(both, 10, 33) == (255, 0, 0))
    assert_true(_rgb(both, 20, 3) == (0, 0, 255))
    # A grid past the top time draws no line of time.
    var bare = survival_image(
        curves, [red], Duration64(1, WEEK64), Duration64(2, WEEK64), 64, 64
    )
    assert_true(_rgb(bare, 32, 3) == white)
    var none = List[SurvivalCurve]()
    with assert_raises(contains="one color for each"):
        _ = survival_image(
            none,
            List[Rgba](),
            Duration64(1, WEEK64),
            Duration64(1, WEEK64),
            64,
            64,
        )
    with assert_raises(contains="one color for each"):
        _ = survival_image(
            curves,
            List[Rgba](),
            Duration64(1, WEEK64),
            Duration64(1, WEEK64),
            64,
            64,
        )
    var sizes: List[Int] = [63, 4097, 64, 64]
    var heights: List[Int] = [64, 64, 63, 4097]
    for n in range(4):
        with assert_raises(contains="pixels on each side"):
            _ = survival_image(
                curves,
                [red],
                Duration64(1, WEEK64),
                Duration64(1, WEEK64),
                sizes[n],
                heights[n],
            )
    var tops: List[Float64] = [0.0, inf[DType.float64]()]
    for t in tops:
        with assert_raises(contains="top time"):
            _ = survival_image(
                curves,
                [red],
                Duration64(t, WEEK64),
                Duration64(1, WEEK64),
                64,
                64,
            )
    var grids: List[Float64] = [0.0, inf[DType.float64](), 0.009]
    for g in grids:
        with assert_raises(contains="at most 100 lines"):
            _ = survival_image(
                curves,
                [red],
                Duration64(1, WEEK64),
                Duration64(g, WEEK64),
                64,
                64,
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
