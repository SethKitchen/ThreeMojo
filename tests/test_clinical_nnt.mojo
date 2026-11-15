# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The difference of two survival curves at a time, and the number needed
to treat.

`assets/survival/nnt_expected.txt` holds the values of lifelines and numpy
for the 6-MP trial. See `assets/survival/make_nnt.py`.
"""

from extensions.clinical.nnt import SurvivalDifference, survival_difference
from extensions.clinical.survival import kaplan_meier
from std.math import inf, isinf, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import WEEK64, Duration64


def _group(text: String) raises -> Tuple[List[Duration64], List[Bool]]:
    var times = List[Duration64]()
    var events = List[Bool]()
    for part in text.split(" "):
        var word = String(part)
        var censored = word.endswith("+")
        var number = String(word.removesuffix("+"))
        times.append(Duration64(atof(number), WEEK64))
        events.append(not censored)
    return (times^, events^)


def _close(a: Float64, b: Float64, tolerance: Float64) raises:
    assert_almost_equal(a, b, atol=tolerance * abs(b), rtol=0)


def test_against_lifelines() raises:
    var drug = _group(
        "6 6 6 6+ 7 9+ 10 10+ 11+ 13 16 17+ 19+ 20+ 22 23 25+ 32+ 32+ 34+ 35+"
    )
    var placebo = _group("1 1 2 2 3 4 4 5 5 8 8 8 8 11 11 12 12 15 17 22 23")
    var treated = kaplan_meier(drug[0], drug[1])
    var control = kaplan_meier(placebo[0], placebo[1])
    var text = open("assets/survival/nnt_expected.txt", "r").read()
    var checked = 0
    for line in text.splitlines():
        var parts = line.split(" ")
        var row = List[Float64]()
        for at in range(1, len(parts)):
            row.append(atof(String(parts[at])))
        var result = survival_difference(
            treated, control, Duration64(row[0], WEEK64)
        )
        _close(result.treated, row[1], 1e-14)
        _close(result.control, row[2], 1e-14)
        _close(result.difference, row[3], 1e-14)
        _close(result.standard_error, row[4], 1e-13)
        _close(result.lower, row[5], 1e-13)
        _close(result.upper, row[6], 1e-13)
        _close(result.nnt(), row[7], 1e-14)
        var band = result.nnt_interval()
        _close(band[0], 1.0 / row[6], 1e-13)
        _close(band[1], 1.0 / row[5], 1e-12)
        checked += 1
    assert_equal(checked, 3)


def test_by_hand() raises:
    # Before any event, both groups survive whole, with no error.
    var a = kaplan_meier(
        [Duration64(5.0, WEEK64), Duration64(9.0, WEEK64)], [True, True]
    )
    var b = kaplan_meier(
        [Duration64(2.0, WEEK64), Duration64(3.0, WEEK64)], [True, False]
    )
    var early = survival_difference(a, b, Duration64(1.0, WEEK64))
    assert_equal(early.difference, 0)
    assert_equal(early.standard_error, 0)
    with assert_raises(contains="infinite number to treat"):
        _ = early.nnt()
    # After the last event of a, its survival is 0 with no variance. b has
    # lost one of two: a difference of -1/2 with b's variance 1/4 * 1/2.
    var late = survival_difference(a, b, Duration64(10.0, WEEK64))
    assert_equal(late.treated, 0)
    _close(late.difference, -0.5, 1e-15)
    _close(late.standard_error, sqrt(0.125), 1e-15)
    _close(late.nnt(), -2.0, 1e-15)
    # A group with no event keeps a survival of 1 with no error.
    var none = kaplan_meier([Duration64(4.0, WEEK64)], [False])
    var censored = survival_difference(none, b, Duration64(10.0, WEEK64))
    assert_equal(censored.treated, 1.0)
    _close(censored.difference, 0.5, 1e-15)
    # An interval that holds 0 runs from a benefit to a harm.
    var manual = SurvivalDifference(Duration64(1.0, WEEK64), 0.6, 0.5, 0.1)
    var band = manual.nnt_interval()
    assert_true(band[0] > 0)
    assert_true(band[1] < 0)
    with assert_raises(contains="0 or more"):
        _ = survival_difference(a, b, Duration64(-1.0, WEEK64))
    with assert_raises(contains="0 or more"):
        _ = survival_difference(a, b, Duration64(inf[DType.float64](), WEEK64))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
