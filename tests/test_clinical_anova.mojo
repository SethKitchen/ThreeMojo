# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One-way analysis of variance and the Kruskal-Wallis test.

`assets/hypothesis/anova_expected.txt` holds the results of scipy 1.18.1
on the synthetic groups of `assets/hypothesis/three_groups.txt`. See
`tools/make_anova.mojo` and `assets/hypothesis/make_anova.py`.
"""

from extensions.clinical.anova import kruskal_wallis, one_way_anova
from extensions.clinical.hypothesis import student_t_test
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)


def _row(line: String) raises -> List[Float64]:
    var out = List[Float64]()
    for part in line.split(" "):
        out.append(atof(String(part)))
    return out^


def _numbers(line: String) raises -> List[Float64]:
    var out = List[Float64]()
    var first = True
    for part in line.split(" "):
        if first:
            first = False
            continue
        out.append(atof(String(part)))
    return out^


def test_against_scipy() raises:
    var groups = List[List[Float64]]()
    for line in (
        open("assets/hypothesis/three_groups.txt", "r").read().splitlines()
    ):
        groups.append(_row(String(line)))
    var lines = (
        open("assets/hypothesis/anova_expected.txt", "r").read().splitlines()
    )
    var a = _numbers(String(lines[0]))
    var f = one_way_anova(groups)
    assert_almost_equal(f.statistic, a[0], rtol=1e-13)
    assert_equal(f.freedom, Int(a[1]))
    assert_equal(f.residual, Int(a[2]))
    assert_almost_equal(f.p_value, a[3], rtol=1e-10)
    var k = _numbers(String(lines[1]))
    var h = kruskal_wallis(groups)
    assert_almost_equal(h.statistic, k[0], rtol=1e-13)
    assert_equal(h.freedom, Int(k[1]))
    assert_almost_equal(h.p_value, k[2], rtol=1e-11)


def test_by_hand() raises:
    # With two groups, F is the square of Student's t.
    var first: List[Float64] = [1.0, 2.0, 3.0, 5.0]
    var second: List[Float64] = [4.0, 6.0, 7.0]
    var groups = List[List[Float64]]()
    groups.append(first.copy())
    groups.append(second.copy())
    var t = student_t_test(first, second)
    var f = one_way_anova(groups)
    assert_almost_equal(f.statistic, t.statistic * t.statistic, rtol=1e-13)
    assert_almost_equal(f.p_value, t.p_value, rtol=1e-12)
    # Groups of equal means: F is 0 and p is 1.
    var level = one_way_anova([[1.0, 3.0], [2.0, 2.0]])
    assert_equal(level.statistic, 0.0)
    assert_equal(level.p_value, 1.0)
    # Ranks 1, 2 against 3, 4: H = 12/20 x (9/2 + 49/2) - 15 = 2.4.
    var apart = kruskal_wallis([[1.0, 2.0], [3.0, 4.0]])
    assert_almost_equal(apart.statistic, 2.4, rtol=1e-14)


def test_refusals() raises:
    var one = List[List[Float64]]()
    one.append([1.0, 2.0])
    with assert_raises(contains="2 to 1000 groups"):
        _ = one_way_anova(one)
    var many = List[List[Float64]]()
    for _ in range(1001):
        many.append([1.0])
    with assert_raises(contains="2 to 1000 groups"):
        _ = kruskal_wallis(many)
    with assert_raises(contains="enough values"):
        _ = one_way_anova([[1.0, 2.0], List[Float64]()])
    with assert_raises(contains="must be finite"):
        _ = kruskal_wallis([[1.0, nan[DType.float64]()], [2.0]])
    with assert_raises(contains="more values than groups"):
        _ = one_way_anova([[1.0], [2.0]])
    with assert_raises(contains="vary in a group"):
        _ = one_way_anova([[1.0, 1.0], [2.0, 2.0]])
    with assert_raises(contains="do not all tie"):
        _ = kruskal_wallis([[2.0, 2.0], [2.0]])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
