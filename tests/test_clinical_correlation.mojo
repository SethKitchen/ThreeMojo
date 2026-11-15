# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Pearson's, Spearman's and Kendall's correlations.

`assets/hypothesis/correlation_expected.txt` holds the results of scipy
1.18.1 on the synthetic pairs of `assets/hypothesis/pairs.txt`. See
`assets/hypothesis/make_correlation.py`.
"""

from extensions.clinical.correlation import kendall, pearson, spearman
from std.math import inf
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


def _negated(values: List[Float64]) -> List[Float64]:
    var out = List[Float64]()
    for v in values:
        out.append(-v)
    return out^


def test_against_scipy() raises:
    var pairs = open("assets/hypothesis/pairs.txt", "r").read().splitlines()
    var x = _row(String(pairs[0]))
    var y = _row(String(pairs[1]))
    var lines = (
        open("assets/hypothesis/correlation_expected.txt", "r")
        .read()
        .splitlines()
    )
    var p = _numbers(String(lines[0]))
    var r = pearson(x, y)
    assert_almost_equal(r.value, p[0], rtol=1e-14)
    assert_almost_equal(r.p_value, p[1], rtol=1e-11)
    assert_almost_equal(r.lower, p[2], rtol=1e-13)
    assert_almost_equal(r.upper, p[3], rtol=1e-13)
    # A negative correlation mirrors the interval.
    var mirror = pearson(x, _negated(y))
    assert_almost_equal(mirror.value, -p[0], rtol=1e-14)
    assert_almost_equal(mirror.lower, -p[3], rtol=1e-13)
    assert_almost_equal(mirror.upper, -p[2], rtol=1e-13)
    var s = _numbers(String(lines[1]))
    var rho = spearman(x, y)
    assert_almost_equal(rho.value, s[0], rtol=1e-14)
    assert_almost_equal(rho.p_value, s[1], rtol=1e-11)
    var k = _numbers(String(lines[2]))
    var tau = kendall(x, y)
    assert_almost_equal(tau.value, k[0], rtol=1e-14)
    assert_almost_equal(tau.p_value, k[1], rtol=1e-11)


def test_by_hand() raises:
    # A straight line: r is 1, with no chance and no width.
    var line = pearson([1.0, 2.0, 3.0, 4.0], [3.0, 5.0, 7.0, 9.0])
    assert_equal(line.value, 1.0)
    assert_equal(line.p_value, 0.0)
    assert_equal(line.lower, 1.0)
    # A curve that only rises: rho is 1.
    var rising = spearman(
        [1.0, 2.0, 3.0, 4.0, 5.0], [1.0, 8.0, 27.0, 64.0, 125.0]
    )
    assert_almost_equal(rising.value, 1.0, rtol=1e-15)
    # Kendall: two concordant pairs and one discordant of three.
    var tau = kendall([1.0, 2.0, 3.0], [1.0, 3.0, 2.0])
    assert_almost_equal(tau.value, 1.0 / 3.0, rtol=1e-15)
    assert_true(tau.p_value > 0.5)


def test_refusals() raises:
    var three: List[Float64] = [1.0, 2.0, 3.0]
    with assert_raises(contains="pairs of values"):
        _ = pearson(three, three)
    with assert_raises(contains="pairs of values"):
        _ = spearman(three, [1.0, 2.0])
    with assert_raises(contains="pairs of values"):
        _ = kendall([1.0, 2.0], [1.0, 2.0])
    with assert_raises(contains="must be finite"):
        _ = spearman([1.0, inf[DType.float64](), 3.0], three)
    with assert_raises(contains="must be finite"):
        _ = spearman(three, [1.0, 2.0, inf[DType.float64]()])
    var flat: List[Float64] = [2.0, 2.0, 2.0]
    with assert_raises(contains="values that vary"):
        _ = spearman(flat, three)
    with assert_raises(contains="values that vary"):
        _ = spearman(three, flat)
    with assert_raises(contains="values that vary"):
        _ = kendall(flat, three)
    with assert_raises(contains="values that vary"):
        _ = kendall(three, flat)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
