# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The Aalen-Johansen cumulative incidence of competing causes.

`assets/competing/competing_expected.txt` holds the values of lifelines
for a synthetic cohort of 80 patients. See
`assets/competing/make_competing.py`.
"""

from extensions.clinical.competing import (
    CumulativeIncidence,
    cumulative_incidence,
    incidence_image,
)
from extensions.clinical.survival import kaplan_meier
from extensions.imaging.overlay import draw_line
from extensions.imaging.transfer import Rgba
from render.framebuffer import Color, Framebuffer
from std.math import inf, isnan, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DAY64, YEAR64, Duration64

comptime BLUE = Rgba(0.2, 0.4, 0.8, 1)
comptime RED = Rgba(0.8, 0.2, 0.2, 1)


def _rows() raises -> Dict[String, List[Float64]]:
    var out = Dict[String, List[Float64]]()
    var text = open("assets/competing/competing_expected.txt", "r").read()
    for line in text.splitlines():
        var parts = line.split(" ")
        var values = List[Float64]()
        for at in range(1, len(parts)):
            var part = String(parts[at])
            values.append(nan[DType.float64]() if part == "nan" else atof(part))
        out[String(parts[0])] = values^
    return out^


def _years(values: List[Float64]) -> List[Duration64]:
    var out = List[Duration64]()
    for v in values:
        out.append(Duration64(v, YEAR64))
    return out^


def _days(values: List[Float64]) -> List[Duration64]:
    var out = List[Duration64]()
    for v in values:
        out.append(Duration64(v, DAY64))
    return out^


def _close(a: Float64, b: Float64, tolerance: Float64) raises:
    assert_almost_equal(a, b, atol=tolerance * abs(b), rtol=0)


def _is(image: Framebuffer, x: Int, y: Int, color: Rgba) raises:
    var probe = Framebuffer(1, 1, Color(0, 0, 0))
    draw_line(probe, 0, 0, 0, 0, color)
    var at = (y * image.width + x) * 4
    for k in range(3):
        assert_equal(image.pixels[at + k], probe.pixels[k])


def test_against_lifelines() raises:
    var rows = _rows()
    var times = _years(rows["times"])
    var relapse = List[Bool]()
    var death = List[Bool]()
    for c in rows["causes"]:
        relapse.append(c == 1.0)
        death.append(c == 2.0)
    var causes: List[Tuple[String, CumulativeIncidence]] = [
        ("1", cumulative_incidence(times, relapse, death)),
        ("2", cumulative_incidence(times, death, relapse)),
    ]
    for cause in causes:
        var name = cause[0]
        ref curve = cause[1]
        ref expected = rows[name + "_times"]
        assert_equal(len(curve.times), len(expected))
        assert_equal(len(curve.times), 42)
        assert_equal(curve.patients, 80)
        for i in range(len(expected)):
            _close(curve.times[i].to(YEAR64), expected[i], 1e-15)
            _close(curve.incidence[i], rows[name + "_incidence"][i], 1e-14)
            _close(curve.variance[i], rows[name + "_variance"][i], 1e-12)
            var band = curve.interval(i)
            var low = rows[name + "_lower"][i]
            if isnan(low):
                assert_equal(curve.incidence[i], 0)
                assert_equal(band[0], 0)
                assert_equal(band[1], 0)
                continue
            _close(band[0], low, 1e-12)
            _close(band[1], rows[name + "_upper"][i], 1e-12)


def test_without_competing_events() raises:
    # With no competing event, F is 1 - S and its variance is Greenwood's.
    var rows = _rows()
    var times = _years(rows["times"])
    var events = List[Bool]()
    var none = List[Bool]()
    for c in rows["causes"]:
        events.append(c == 1.0)
        none.append(False)
    var curve = cumulative_incidence(times, events, none)
    var km = kaplan_meier(times, events)
    assert_equal(len(curve.times), len(km.times))
    for i in range(len(km.times)):
        assert_equal(curve.times[i].to(YEAR64), km.times[i].to(YEAR64))
        _close(curve.incidence[i], 1.0 - km.survival[i], 1e-14)
        var s = km.survival[i]
        _close(curve.variance[i], s * s * km.greenwood[i], 1e-12)
        assert_equal(curve.at_risk[i], km.at_risk[i])


def test_by_hand() raises:
    # A relapse at 1 of 4, a death at 2 of 3, a censoring at 3 and a
    # relapse at 4 of the last patient.
    var curve = cumulative_incidence(
        _days([1.0, 2.0, 3.0, 4.0]),
        [True, False, False, True],
        [False, True, False, False],
    )
    assert_equal(len(curve.times), 3)
    assert_equal(curve.incidence[0], 0.25)
    assert_equal(curve.incidence[1], 0.25)
    assert_equal(curve.incidence[2], 0.75)
    assert_equal(curve.competing[1], 1)
    # The variance of a share of 1 in 4 is p (1 - p) / n.
    _close(curve.variance[0], 3.0 / 64.0, 1e-15)
    assert_equal(curve.at(Duration64(0.5, DAY64)), 0)
    assert_equal(curve.at(Duration64(3.0, DAY64)), 0.25)
    assert_equal(curve.at(Duration64(9.0, DAY64)), 0.75)
    var deaths = cumulative_incidence(
        _days([1.0, 2.0, 3.0, 4.0]),
        [False, True, False, False],
        [True, False, False, True],
    )
    # Every cause and the survival sum to 1 once no patient is left.
    _close(curve.incidence[2] + deaths.incidence[2], 1.0, 1e-15)
    # A single patient with the event reaches an incidence of 1.
    var one = cumulative_incidence(_days([2.0]), [True], [False])
    assert_equal(one.incidence[0], 1)
    assert_equal(one.variance[0], 0)
    var band = one.interval(0)
    assert_equal(band[0], 1)
    assert_equal(band[1], 1)
    var inside = curve.interval(0)
    assert_true(inside[0] < 0.25 and 0.25 < inside[1])
    with assert_raises(contains="no time of that index"):
        _ = curve.interval(3)
    with assert_raises(contains="no time of that index"):
        _ = curve.interval(-1)


def test_ties_between_causes() raises:
    # A relapse and a death at one time count at once.
    var curve = cumulative_incidence(
        _days([1.0, 1.0, 2.0]), [True, False, False], [False, True, False]
    )
    assert_equal(len(curve.times), 1)
    _close(curve.incidence[0], 1.0 / 3.0, 1e-15)
    assert_equal(curve.events[0], 1)
    assert_equal(curve.competing[0], 1)
    # All censored: no time.
    var empty = cumulative_incidence(
        _days([1.0, 2.0]), [False, False], [False, False]
    )
    assert_equal(len(empty.times), 0)
    assert_equal(empty.at(Duration64(5.0, DAY64)), 0)


def test_image() raises:
    var curve = cumulative_incidence(
        _days([1.0, 2.0, 3.0, 4.0]),
        [True, False, False, True],
        [False, True, False, False],
    )
    var empty = cumulative_incidence(_days([1.0]), [False], [False])
    var image = incidence_image(
        [curve.copy(), empty.copy()],
        [BLUE, RED],
        Duration64(4.0, DAY64),
        Duration64(1.0, DAY64),
        1.0,
        101,
        101,
    )
    # Up at day 1 to 0.25, and at day 4 to 0.75.
    _is(image, 25, 90, BLUE)
    _is(image, 40, 75, BLUE)
    _is(image, 100, 40, BLUE)
    _is(image, 60, 65, Rgba(1, 1, 1, 1))
    _is(image, 25, 55, Rgba(0.84, 0.84, 0.86, 1))
    # The empty curve runs along the bottom edge.
    _is(image, 10, 100, RED)
    # A ceiling of a half doubles the rise, and times past the top leave the
    # image.
    var half = incidence_image(
        [curve.copy()],
        [BLUE],
        Duration64(2.0, DAY64),
        Duration64(1.0, DAY64),
        0.5,
        101,
        101,
    )
    _is(half, 50, 50, BLUE)
    _is(half, 75, 50, BLUE)
    # A grid wider than the plot draws no line of time.
    var wide = incidence_image(
        [empty.copy()],
        [RED],
        Duration64(1.0, DAY64),
        Duration64(2.0, DAY64),
        1.0,
        101,
        101,
    )
    _is(wide, 50, 5, Rgba(1, 1, 1, 1))


def test_errors() raises:
    var times = _days([1.0, 2.0])
    with assert_raises(contains="one competing event per patient"):
        _ = cumulative_incidence(times, [True, False], [False])
    with assert_raises(contains="one first event at most"):
        _ = cumulative_incidence(times, [True, False], [True, False])
    with assert_raises(contains="one patient or more"):
        _ = cumulative_incidence(List[Duration64](), List[Bool](), List[Bool]())
    var curve = cumulative_incidence(times, [True, False], [False, True])
    var day = Duration64(1.0, DAY64)
    with assert_raises(contains="one color for each"):
        _ = incidence_image(
            List[CumulativeIncidence](), List[Rgba](), day, day, 1.0, 100, 100
        )
    with assert_raises(contains="one color for each"):
        _ = incidence_image(
            [curve.copy()], [BLUE, RED], day, day, 1.0, 100, 100
        )
    var sides: List[Tuple[Int, Int]] = [
        (63, 100),
        (4097, 100),
        (100, 63),
        (100, 4097),
    ]
    for side in sides:
        with assert_raises(contains="64 to 4096"):
            _ = incidence_image(
                [curve.copy()], [BLUE], day, day, 1.0, side[0], side[1]
            )
    var bad: List[Float64] = [0.0, inf[DType.float64]()]
    for value in bad:
        with assert_raises(contains="top time"):
            _ = incidence_image(
                [curve.copy()],
                [BLUE],
                Duration64(value, DAY64),
                day,
                1.0,
                100,
                100,
            )
        with assert_raises(contains="positive grid"):
            _ = incidence_image(
                [curve.copy()],
                [BLUE],
                day,
                Duration64(value, DAY64),
                1.0,
                100,
                100,
            )
    with assert_raises(contains="positive grid"):
        _ = incidence_image(
            [curve.copy()], [BLUE], Duration64(200.0, DAY64), day, 1.0, 100, 100
        )
    var ceilings: List[Float64] = [0.0, 1.5, nan[DType.float64]()]
    for ceiling in ceilings:
        with assert_raises(contains="ceiling"):
            _ = incidence_image(
                [curve.copy()], [BLUE], day, day, ceiling, 100, 100
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
