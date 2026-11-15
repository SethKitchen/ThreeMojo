# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The growth of case counts and the reproduction number.

`assets/incidence/incidence_expected.txt` holds the Poisson regression of
statsmodels 0.15.0 on the synthetic counts of
`assets/incidence/cases.txt`. See `assets/incidence/make_incidence.py`.
"""

from extensions.clinical.incidence import (
    GrowthFit,
    growth_rate,
    incidence_image,
    reproduction_number,
)
from render.framebuffer import Framebuffer
from std.math import inf, log, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DAY64, PER_DAY64, Duration64, Frequency64


def _days(value: Float64) -> Duration64:
    return Duration64(value, DAY64)


def _cases() raises -> List[Int]:
    var out = List[Int]()
    var text = open("assets/incidence/cases.txt", "r").read()
    for line in text.splitlines():
        out.append(atol(String(line)))
    return out^


def test_against_statsmodels() raises:
    var line = open("assets/incidence/incidence_expected.txt", "r").read()
    var words = String(line.splitlines()[0]).split(" ")
    var expected = List[Float64]()
    for k in range(1, len(words)):
        expected.append(atof(String(words[k])))
    var fit = growth_rate(_cases(), _days(1), 1e-12, 100)
    assert_true(fit.converged)
    assert_almost_equal(fit.intercept, expected[0], rtol=1e-12)
    assert_almost_equal(fit.rate.to(PER_DAY64), expected[1], rtol=1e-12)
    assert_almost_equal(fit.intercept_error, expected[2], rtol=1e-11)
    assert_almost_equal(fit.rate_error.to(PER_DAY64), expected[3], rtol=1e-11)
    assert_almost_equal(fit.dispersion, expected[4], rtol=1e-11)
    assert_almost_equal(fit.deviance, expected[5], rtol=1e-11)
    var band = fit.rate_interval()
    assert_almost_equal(
        band[1].to(PER_DAY64) - band[0].to(PER_DAY64),
        2 * 1.959963984540054 * expected[3],
        rtol=1e-11,
    )
    assert_almost_equal(
        fit.doubling_time().to(DAY64), log(2.0) / expected[1], rtol=1e-12
    )


def test_by_hand() raises:
    # Counts that double each day: a rate of ln 2 a day, no deviance and
    # no dispersion.
    var doubling: List[Int] = [1, 2, 4, 8, 16, 32]
    var fit = growth_rate(doubling, _days(1), 1e-12, 100)
    assert_almost_equal(fit.rate.to(PER_DAY64), log(2.0), rtol=1e-13)
    assert_almost_equal(fit.intercept, 0.0, atol=1e-13)
    assert_almost_equal(fit.doubling_time().to(DAY64), 1.0, rtol=1e-13)
    assert_almost_equal(fit.deviance, 0.0, atol=1e-12)
    assert_almost_equal(fit.expected(_days(3)), 8.0, rtol=1e-12)
    # The same counts two days apart: a doubling time of two days.
    var slow = growth_rate(doubling, _days(2), 1e-12, 100)
    assert_almost_equal(slow.doubling_time().to(DAY64), 2.0, rtol=1e-13)
    # A count of 0 adds no y log(y / mu) to the deviance.
    var gap: List[Int] = [0, 3, 5, 9]
    var with_zero = growth_rate(gap, _days(1), 1e-12, 100)
    assert_true(with_zero.converged)
    assert_true(with_zero.deviance > 0)
    # One step is not enough to converge.
    var short = growth_rate(gap, _days(1), 1e-12, 1)
    assert_false(short.converged)
    assert_equal(short.steps, 1)
    # Falling counts do not double.
    var falling: List[Int] = [40, 20, 10, 5]
    var decline = growth_rate(falling, _days(1), 1e-12, 100)
    assert_almost_equal(decline.rate.to(PER_DAY64), -log(2.0), rtol=1e-12)
    with assert_raises(contains="do not grow"):
        _ = decline.doubling_time()
    # SEIR: (1 + 0.1 x 3)(1 + 0.1 x 5) = 1.95; SIR: 1.5.
    var rate = Frequency64(0.1, PER_DAY64)
    assert_almost_equal(
        reproduction_number(rate, _days(3), _days(5)), 1.95, rtol=1e-14
    )
    assert_almost_equal(
        reproduction_number(rate, _days(0), _days(5)), 1.5, rtol=1e-14
    )
    # A falling epidemic has R below 1.
    assert_true(
        reproduction_number(Frequency64(-0.05, PER_DAY64), _days(3), _days(5))
        < 1.0
    )


def test_refusals() raises:
    var short: List[Int] = [1, 2]
    with assert_raises(contains="3 to 100000 counts"):
        _ = growth_rate(short, _days(1), 1e-12, 100)
    var long = List[Int](length=100001, fill=1)
    with assert_raises(contains="3 to 100000 counts"):
        _ = growth_rate(long, _days(1), 1e-12, 100)
    var negative: List[Int] = [1, -2, 3]
    with assert_raises(contains="0 or more"):
        _ = growth_rate(negative, _days(1), 1e-12, 100)
    var zeros: List[Int] = [0, 0, 0]
    with assert_raises(contains="one case or more"):
        _ = growth_rate(zeros, _days(1), 1e-12, 100)
    var good: List[Int] = [1, 2, 3]
    var steps: List[Float64] = [0.0, inf[DType.float64]()]
    for s in steps:
        with assert_raises(contains="step between counts"):
            _ = growth_rate(good, _days(s), 1e-12, 100)
    var tolerances: List[Float64] = [0.0, 1.0]
    for t in tolerances:
        with assert_raises(contains="between 0 and 1"):
            _ = growth_rate(good, _days(1), t, 100)
    var counts: List[Int] = [0, 1001]
    for c in counts:
        with assert_raises(contains="1 to 1000 steps"):
            _ = growth_rate(good, _days(1), 1e-12, c)
    var rate = Frequency64(0.1, PER_DAY64)
    with assert_raises(contains="must be finite"):
        _ = reproduction_number(
            Frequency64(nan[DType.float64](), PER_DAY64), _days(3), _days(5)
        )
    var latents: List[Float64] = [-1.0, inf[DType.float64]()]
    for l in latents:
        with assert_raises(contains="latent period"):
            _ = reproduction_number(rate, _days(l), _days(5))
    var infectious: List[Float64] = [0.0, inf[DType.float64]()]
    for d in infectious:
        with assert_raises(contains="latent period"):
            _ = reproduction_number(rate, _days(3), _days(d))
    with assert_raises(contains="this negative"):
        _ = reproduction_number(
            Frequency64(-0.5, PER_DAY64), _days(3), _days(1)
        )
    with assert_raises(contains="this negative"):
        _ = reproduction_number(
            Frequency64(-0.5, PER_DAY64), _days(1), _days(3)
        )


def _rgb(image: Framebuffer, x: Int, y: Int) -> Tuple[Int, Int, Int]:
    var at = (y * image.width + x) * 4
    return (
        Int(image.pixels[at]),
        Int(image.pixels[at + 1]),
        Int(image.pixels[at + 2]),
    )


def test_incidence_image() raises:
    # Four counts of 10 on a flat fit: bars to 10 / 11 of the height.
    var flat: List[Int] = [10, 10, 10, 10]
    var fit = growth_rate(flat, _days(1), 1e-12, 100)
    var image = incidence_image(flat, _days(1), fit, 100, 111)
    # A bar fills below its top and leaves the space above it.
    assert_true(_rgb(image, 5, 60) == (140, 179, 230))
    assert_true(_rgb(image, 5, 5) == (255, 255, 255))
    # The fitted line runs along the tops of the bars.
    var top = Int((1.0 - Float64(10) / 11.0) * 110.0 + 0.5)
    assert_true(_rgb(image, 50, top) == (217, 51, 51))
    var sizes: List[Int] = [63, 4097, 64, 64]
    var heights: List[Int] = [64, 64, 63, 4097]
    for n in range(4):
        with assert_raises(contains="pixels a side"):
            _ = incidence_image(flat, _days(1), fit, sizes[n], heights[n])
    var short: List[Int] = [1, 2]
    with assert_raises(contains="3 to 100000 counts"):
        _ = incidence_image(short, _days(1), fit, 64, 64)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
