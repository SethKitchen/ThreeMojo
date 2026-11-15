# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Student, Welch and paired t tests, and rank tests of two groups.

`assets/hypothesis/hypothesis_expected.txt` holds the results of scipy
1.18.1 on the synthetic groups of `assets/hypothesis/groups.txt`. See
`assets/hypothesis/make_hypothesis.py`.
"""

from extensions.clinical.hypothesis import (
    TTest,
    mann_whitney,
    midranks,
    paired_t_test,
    student_t_test,
    welch_t_test,
    wilcoxon,
)
from std.math import erfc, inf, nan, sqrt
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


def _row(line: String) raises -> List[Float64]:
    var out = List[Float64]()
    for part in line.split(" "):
        out.append(atof(String(part)))
    return out^


def _check(test: TTest, row: List[Float64]) raises:
    assert_almost_equal(test.statistic, row[0], rtol=1e-13)
    assert_almost_equal(test.freedom, row[1], rtol=1e-13)
    assert_almost_equal(test.p_value, row[2], rtol=1e-11)
    assert_almost_equal(test.lower, row[3], rtol=1e-12)
    assert_almost_equal(test.upper, row[4], rtol=1e-12)


def test_against_scipy() raises:
    var groups = open("assets/hypothesis/groups.txt", "r").read().splitlines()
    var treated = _row(String(groups[0]))
    var control = _row(String(groups[1]))
    var before = _row(String(groups[2]))
    var after = _row(String(groups[3]))
    var lines = (
        open("assets/hypothesis/hypothesis_expected.txt", "r")
        .read()
        .splitlines()
    )
    _check(student_t_test(treated, control), _numbers(String(lines[0])))
    _check(welch_t_test(treated, control), _numbers(String(lines[1])))
    _check(paired_t_test(before, after), _numbers(String(lines[2])))
    var u = mann_whitney(treated, control)
    var mw = _numbers(String(lines[3]))
    assert_equal(u.statistic, mw[0])
    assert_almost_equal(u.p_value, mw[1], rtol=1e-12)
    var w = wilcoxon(before, after)
    var wx = _numbers(String(lines[4]))
    assert_equal(w.statistic, wx[0])
    assert_almost_equal(w.z, wx[1], rtol=1e-13)
    assert_almost_equal(w.p_value, wx[2], rtol=1e-11)


def test_by_hand() raises:
    # Ranks with a tie: 10 is first, the two 20s share 2 and 3.
    var ranks = midranks([20.0, 10.0, 20.0, 30.0])
    assert_equal(ranks[0], 2.5)
    assert_equal(ranks[1], 1.0)
    assert_equal(ranks[3], 4.0)
    assert_equal(len(midranks(List[Float64]())), 0)
    # Means 2 and 5 of variance 1 each, three values a group: t is
    # -3 / sqrt(2/3), on 4 degrees of freedom.
    var test = student_t_test([1.0, 2.0, 3.0], [4.0, 5.0, 6.0])
    assert_almost_equal(test.statistic, -3.0 / sqrt(2.0 / 3.0), rtol=1e-15)
    assert_equal(test.freedom, 4.0)
    # Equal variances and sizes: Welch has the same t and freedom.
    var welch = welch_t_test([1.0, 2.0, 3.0], [4.0, 5.0, 6.0])
    assert_almost_equal(welch.statistic, test.statistic, rtol=1e-15)
    assert_almost_equal(welch.freedom, 4.0, rtol=1e-15)
    # Two groups apart: U of the lower group is 0.
    var apart = mann_whitney([1.0, 2.0], [3.0, 4.0, 5.0])
    assert_equal(apart.statistic, 0.0)
    # U at its mean has no continuity step: z is 0 and p is 1.
    var even = mann_whitney([1.0, 4.0], [2.0, 3.0])
    assert_equal(even.z, 0.0)
    assert_equal(even.p_value, 1.0)
    # Zero differences drop out: the pairs that differ are +1, +2, -3.
    var signed = wilcoxon([5.0, 6.0, 7.0, 8.0, 9.0], [5.0, 5.0, 5.0, 11.0, 9.0])
    assert_equal(signed.statistic, 3.0)
    # n = 3: mean 3, variance 3.5.
    assert_almost_equal(signed.z, 0.0, atol=1e-15)


def test_refusals() raises:
    var one: List[Float64] = [1.0]
    var good: List[Float64] = [1.0, 2.0]
    with assert_raises(contains="two values or more"):
        _ = student_t_test(one, good)
    with assert_raises(contains="two values or more"):
        _ = welch_t_test(good, one)
    with assert_raises(contains="must be finite"):
        _ = student_t_test([1.0, inf[DType.float64]()], good)
    var flat: List[Float64] = [3.0, 3.0]
    with assert_raises(contains="values that vary"):
        _ = student_t_test(flat, flat)
    with assert_raises(contains="values that vary"):
        _ = welch_t_test(flat, flat)
    with assert_raises(contains="one second value for each"):
        _ = paired_t_test(good, [1.0, 2.0, 3.0])
    with assert_raises(contains="values that vary"):
        _ = paired_t_test([1.0, 2.0], [0.0, 1.0])
    with assert_raises(contains="must be finite"):
        _ = paired_t_test(good, [1.0, nan[DType.float64]()])
    with assert_raises(contains="one value or more"):
        _ = mann_whitney(List[Float64](), good)
    with assert_raises(contains="one value or more"):
        _ = mann_whitney(good, List[Float64]())
    with assert_raises(contains="must be finite"):
        _ = mann_whitney(good, [nan[DType.float64]()])
    with assert_raises(contains="do not all tie"):
        _ = mann_whitney(flat, flat)
    with assert_raises(contains="not 0"):
        _ = wilcoxon(good, good)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
