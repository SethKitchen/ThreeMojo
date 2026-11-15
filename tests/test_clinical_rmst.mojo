# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Nelson-Aalen hazards and restricted mean survival times.

`assets/survival/rmst_expected.txt` holds the results of lifelines 0.30.3
and numpy on the trial of Freireich and others (1963). See
`assets/survival/make_rmst.py`.
"""

from extensions.clinical.rmst import (
    CumulativeHazard,
    compare_restricted_means,
    nelson_aalen,
    restricted_mean,
)
from extensions.clinical.survival import WEEK64, kaplan_meier
from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import Duration64

comptime DRUG = (
    "6 6 6 6+ 7 9+ 10 10+ 11+ 13 16 17+ 19+ 20+ 22 23 25+ 32+ 32+ 34+ 35+"
)
comptime PLACEBO = "1 1 2 2 3 4 4 5 5 8 8 8 8 11 11 12 12 15 17 22 23"


def _group(text: String) raises -> Tuple[List[Duration64], List[Bool]]:
    var times = List[Duration64]()
    var events = List[Bool]()
    for part in text.split(" "):
        var word = String(part)
        var censored = word.endswith("+")
        var number = word
        if censored:
            number = String(word[byte = 0 : word.byte_length() - 1])
        times.append(Duration64(atof(number), WEEK64))
        events.append(not censored)
    return (times^, events^)


def _numbers(line: String) raises -> List[Float64]:
    var out = List[Float64]()
    var first = True
    for part in line.split(" "):
        if first:
            first = False
            continue
        out.append(atof(String(part)))
    return out^


def _weeks(values: List[Float64]) -> List[Duration64]:
    var out = List[Duration64]()
    for v in values:
        out.append(Duration64(v, WEEK64))
    return out^


def test_freireich() raises:
    var lines = (
        open("assets/survival/rmst_expected.txt", "r").read().splitlines()
    )
    var texts: List[String] = [DRUG, PLACEBO]
    var horizon = Duration64(23, WEEK64)
    for g in range(2):
        var group = _group(texts[g])
        var curve = kaplan_meier(group[0], group[1])
        var hazard = nelson_aalen(curve)
        var row = _numbers(String(lines[2 * g]))
        var count = Int(row[0])
        assert_equal(len(hazard.times), count)
        for i in range(count):
            assert_equal(hazard.times[i].to(WEEK64), row[1 + 4 * i])
            assert_almost_equal(hazard.hazard[i], row[2 + 4 * i], rtol=1e-14)
            var band = hazard.interval(i)
            assert_almost_equal(band[0], row[3 + 4 * i], rtol=1e-13)
            assert_almost_equal(band[1], row[4 + 4 * i], rtol=1e-13)
        var mean = restricted_mean(curve, horizon)
        var expected = _numbers(String(lines[2 * g + 1]))
        assert_almost_equal(mean.mean.to(WEEK64), expected[0], rtol=1e-14)
        assert_almost_equal(
            mean.standard_error.to(WEEK64), expected[1], rtol=1e-13
        )
        var band = mean.interval()
        assert_almost_equal(
            band[1].to(WEEK64) - band[0].to(WEEK64),
            2 * 1.959963984540054 * expected[1],
            rtol=1e-13,
        )
    var drug = _group(DRUG)
    var placebo = _group(PLACEBO)
    var test = compare_restricted_means(
        kaplan_meier(drug[0], drug[1]),
        kaplan_meier(placebo[0], placebo[1]),
        horizon,
    )
    var gap = _numbers(String(lines[4]))
    assert_almost_equal(test.difference.to(WEEK64), gap[0], rtol=1e-14)
    assert_almost_equal(test.standard_error.to(WEEK64), gap[1], rtol=1e-13)
    assert_almost_equal(test.z, gap[2], rtol=1e-13)
    assert_almost_equal(test.p_value, gap[3], rtol=1e-11)
    var band = test.interval()
    assert_almost_equal(
        band[0].to(WEEK64), gap[0] - 1.959963984540054 * gap[1], rtol=1e-13
    )


def test_by_hand() raises:
    # Events at 1 and 2 weeks, one censored at 3, of three patients: the
    # survival is 2/3 after 1 week and 1/3 after 2 weeks. To 4 weeks the
    # area is 1 + 2/3 + 2 x 1/3 = 7/3.
    var curve = kaplan_meier(_weeks([1.0, 2.0, 3.0]), [True, True, False])
    var mean = restricted_mean(curve, Duration64(4, WEEK64))
    assert_almost_equal(mean.mean.to(WEEK64), 7.0 / 3.0, rtol=1e-14)
    # A_1 = 2/3 + 2/3 = 4/3 with 1 of 3, A_2 = 2/3 with 1 of 2:
    # (16/9) / 6 + (4/9) / 2.
    assert_almost_equal(
        mean.standard_error.to(WEEK64),
        sqrt(16.0 / 54.0 + 4.0 / 18.0),
        rtol=1e-14,
    )
    # A horizon inside the curve: to 1.5 weeks, 1 + 0.5 x 2/3.
    var early = restricted_mean(curve, Duration64(1.5, WEEK64))
    assert_almost_equal(early.mean.to(WEEK64), 4.0 / 3.0, rtol=1e-14)
    # The hazard: 1/3, then 1/3 + 1/2.
    var hazard = nelson_aalen(curve)
    assert_almost_equal(hazard.hazard[1], 5.0 / 6.0, rtol=1e-15)
    assert_almost_equal(hazard.variance[1], 2.0 / 27.0 + 1.0 / 8.0, rtol=1e-15)
    with assert_raises(contains="no time of that index"):
        _ = hazard.interval(2)
    with assert_raises(contains="no time of that index"):
        _ = hazard.interval(-1)
    # A group with no event: no hazard, and an RMST of the whole horizon.
    var none = kaplan_meier(_weeks([5.0, 6.0]), [False, False])
    assert_equal(len(nelson_aalen(none).times), 0)
    var full = restricted_mean(none, Duration64(4, WEEK64))
    assert_almost_equal(full.mean.to(WEEK64), 4.0, rtol=1e-15)
    assert_equal(full.standard_error.to(WEEK64), 0.0)
    # Two groups with no event before the horizon: no difference.
    var same = compare_restricted_means(none, none, Duration64(4, WEEK64))
    assert_equal(same.z, 0.0)
    assert_equal(same.p_value, 1.0)


def test_refusals() raises:
    var curve = kaplan_meier(_weeks([1.0, 2.0]), [True, False])
    var horizons: List[Float64] = [
        0.0,
        -1.0,
        inf[DType.float64](),
        nan[DType.float64](),
    ]
    for h in horizons:
        with assert_raises(contains="horizon of a restricted mean"):
            _ = restricted_mean(curve, Duration64(h, WEEK64))
        with assert_raises(contains="horizon of a restricted mean"):
            _ = compare_restricted_means(curve, curve, Duration64(h, WEEK64))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
