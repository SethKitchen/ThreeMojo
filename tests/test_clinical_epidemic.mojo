# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""SIR and SEIR epidemics.

`assets/epidemic/epidemic_expected.txt` holds epidemics integrated by
scipy 1.18.1 to a relative 1e-13. See `assets/epidemic/make_epidemic.py`.
"""

from extensions.clinical.epidemic import (
    EpidemicCurve,
    epidemic_image,
    final_susceptible,
    herd_immunity,
    seir,
    sir,
)
from extensions.clinical.survival import DAY64
from extensions.imaging.transfer import Rgba
from render.framebuffer import Framebuffer
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Duration64


def _days(value: Float64) -> Duration64:
    return Duration64(value, DAY64)


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
    var text = open("assets/epidemic/epidemic_expected.txt", "r").read()
    for line in text.splitlines():
        out.append(_numbers(String(line)))
    return out^


def test_against_scipy() raises:
    var expected = _expected()
    var days: List[Int] = [10, 30, 60, 90, 150]
    var first = seir(
        2.5, _days(3), _days(5), 1e-4, 0.0, _days(0.05), _days(150)
    )
    assert_equal(len(first.times), 3001)
    for d in range(5):
        var k = days[d] * 20
        assert_almost_equal(
            first.times[k].to(DAY64), Float64(days[d]), rtol=1e-14
        )
        ref row = expected[0]
        assert_almost_equal(first.susceptible[k], row[4 * d], atol=1e-10)
        assert_almost_equal(first.exposed[k], row[4 * d + 1], atol=1e-10)
        assert_almost_equal(first.infectious[k], row[4 * d + 2], atol=1e-10)
        assert_almost_equal(first.removed[k], row[4 * d + 3], atol=1e-10)
    var second = sir(1.8, _days(4), 1e-3, 0.2, _days(0.05), _days(150))
    for d in range(5):
        var k = days[d] * 20
        ref row = expected[1]
        assert_almost_equal(second.susceptible[k], row[3 * d], atol=1e-10)
        assert_equal(second.exposed[k], 0.0)
        assert_almost_equal(second.infectious[k], row[3 * d + 1], atol=1e-10)
        assert_almost_equal(second.removed[k], row[3 * d + 2], atol=1e-10)
    # The four fractions always sum to 1.
    var last = len(first.times) - 1
    assert_almost_equal(
        first.susceptible[last]
        + first.exposed[last]
        + first.infectious[last]
        + first.removed[last],
        1.0,
        atol=1e-14,
    )
    # The final size relation, against brentq.
    ref final = expected[2]
    assert_almost_equal(final_susceptible(2.5, 1e-4, 0.0), final[0], rtol=1e-14)
    assert_almost_equal(final_susceptible(1.8, 1e-3, 0.2), final[1], rtol=1e-14)


def test_epidemic_shape() raises:
    # An SIR epidemic peaks when S falls to 1 / R0, and ends at the final
    # size.
    var long = sir(2.0, _days(5), 1e-4, 0.0, _days(0.1), _days(1500))
    var peak = long.peak()
    var k = Int(peak[0].to(DAY64) / 0.1 + 0.5)
    assert_almost_equal(long.susceptible[k], 0.5, atol=2e-3)
    assert_true(peak[1] > 0.15)
    var end = len(long.times) - 1
    assert_almost_equal(
        long.susceptible[end], final_susceptible(2.0, 1e-4, 0.0), atol=1e-9
    )
    # Immunity above 1 - 1 / R0 stops the growth: the peak is at the start.
    assert_almost_equal(herd_immunity(2.5), 0.6, rtol=1e-15)
    assert_equal(herd_immunity(0.8), 0.0)
    var held = seir(2.5, _days(3), _days(5), 1e-3, 0.65, _days(0.5), _days(60))
    var top = held.peak()
    assert_equal(top[0].to(DAY64), 0.0)
    assert_equal(top[1], 1e-3)
    # A step that does not divide the end is shortened to one that does.
    var odd = sir(2.0, _days(5), 1e-3, 0.0, _days(0.3), _days(1))
    assert_equal(len(odd.times), 4)
    assert_almost_equal(odd.times[1].to(DAY64), 1.0 / 3.0, rtol=1e-15)
    # Everyone infected or immune: none left to infect.
    assert_equal(final_susceptible(3.0, 0.5, 0.5), 0.0)
    # A curve of one record peaks at it.
    var one = EpidemicCurve()
    one.times.append(_days(2))
    one.infectious.append(0.25)
    assert_equal(one.peak()[1], 0.25)
    with assert_raises(contains="no record has no peak"):
        _ = EpidemicCurve().peak()


def test_refusals() raises:
    var bad_r0: List[Float64] = [
        0.0,
        inf[DType.float64](),
        nan[DType.float64](),
    ]
    for r in bad_r0:
        with assert_raises(contains="R0 must be positive"):
            _ = sir(r, _days(5), 1e-3, 0.0, _days(1), _days(10))
        with assert_raises(contains="R0 must be positive"):
            _ = herd_immunity(r)
    var bad_infected: List[Float64] = [0.0, 1.5, nan[DType.float64]()]
    for f in bad_infected:
        with assert_raises(contains="infected fraction"):
            _ = final_susceptible(2.0, f, 0.0)
    var bad_immune: List[Float64] = [-0.1, 0.95, nan[DType.float64]()]
    for p in bad_immune:
        with assert_raises(contains="sum to 1 or less"):
            _ = sir(2.0, _days(5), 0.1, p, _days(1), _days(10))
    var bad_periods: List[Float64] = [0.0, -1.0, inf[DType.float64]()]
    for d in bad_periods:
        with assert_raises(contains="positive and finite"):
            _ = seir(2.0, _days(d), _days(5), 1e-3, 0.0, _days(1), _days(10))
        with assert_raises(contains="positive and finite"):
            _ = seir(2.0, _days(3), _days(d), 1e-3, 0.0, _days(1), _days(10))
        with assert_raises(contains="positive and finite"):
            _ = sir(2.0, _days(5), 1e-3, 0.0, _days(d), _days(10))
        with assert_raises(contains="positive and finite"):
            _ = sir(2.0, _days(5), 1e-3, 0.0, _days(1), _days(d))
    with assert_raises(contains="at most 1000000 steps"):
        _ = sir(2.0, _days(5), 1e-3, 0.0, _days(1e-4), _days(1000))


def _rgb(image: Framebuffer, x: Int, y: Int) -> Tuple[Int, Int, Int]:
    var at = (y * image.width + x) * 4
    return (
        Int(image.pixels[at]),
        Int(image.pixels[at + 1]),
        Int(image.pixels[at + 2]),
    )


def test_epidemic_image() raises:
    # A made curve: an infectious fraction of 0.05 for 10 days, on a top
    # of 0.1, so along the middle row.
    var flat = EpidemicCurve()
    for d in range(11):
        flat.times.append(_days(Float64(d)))
        flat.infectious.append(0.05)
    var curves = List[EpidemicCurve]()
    curves.append(flat^)
    curves.append(EpidemicCurve())
    var red = Rgba(1, 0, 0, 1)
    var image = epidemic_image(
        curves, [red, red], _days(10), _days(5), 0.1, 101, 101
    )
    assert_true(_rgb(image, 25, 50) == (255, 0, 0))
    assert_true(_rgb(image, 50, 25) == (214, 214, 219))
    assert_true(_rgb(image, 25, 25) == (255, 255, 255))
    # A grid past the end draws no line of time.
    var bare = epidemic_image(
        curves, [red, red], _days(1), _days(2), 0.1, 64, 64
    )
    assert_true(_rgb(bare, 32, 3) == (255, 255, 255))
    var none = List[EpidemicCurve]()
    with assert_raises(contains="one color for each"):
        _ = epidemic_image(none, List[Rgba](), _days(1), _days(1), 0.1, 64, 64)
    with assert_raises(contains="one color for each"):
        _ = epidemic_image(curves, [red], _days(1), _days(1), 0.1, 64, 64)
    var sizes: List[Int] = [63, 4097, 64, 64]
    var heights: List[Int] = [64, 64, 63, 4097]
    for n in range(4):
        with assert_raises(contains="pixels on each side"):
            _ = epidemic_image(
                curves,
                [red, red],
                _days(1),
                _days(1),
                0.1,
                sizes[n],
                heights[n],
            )
    with assert_raises(contains="positive and finite"):
        _ = epidemic_image(curves, [red, red], _days(0), _days(1), 0.1, 64, 64)
    with assert_raises(contains="at most 100 lines"):
        _ = epidemic_image(
            curves, [red, red], _days(10), _days(0.01), 0.1, 64, 64
        )
    var tops: List[Float64] = [0.0, 1.5, nan[DType.float64]()]
    for t in tops:
        with assert_raises(contains="top of an epidemic plot"):
            _ = epidemic_image(
                curves, [red, red], _days(1), _days(1), t, 64, 64
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
