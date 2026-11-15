# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Adjusted p values for many tests.

`assets/hypothesis/multiple_expected.txt` holds the results of statsmodels
0.15.0. See `assets/hypothesis/make_multiple.py`.
"""

from extensions.clinical.multiple import (
    benjamini_hochberg,
    benjamini_yekutieli,
    bonferroni,
    holm,
)
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
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


def test_against_statsmodels() raises:
    var lines = (
        open("assets/hypothesis/multiple_expected.txt", "r").read().splitlines()
    )
    var p = _numbers(String(lines[0]))
    var results = [
        bonferroni(p),
        holm(p),
        benjamini_hochberg(p),
        benjamini_yekutieli(p),
    ]
    for m in range(4):
        var expected = _numbers(String(lines[m + 1]))
        for i in range(len(p)):
            assert_almost_equal(results[m][i], expected[i], rtol=1e-15)


def test_by_hand() raises:
    # One test: no change.
    var one: List[Float64] = [0.03]
    assert_equal(holm(one)[0], 0.03)
    assert_equal(benjamini_hochberg(one)[0], 0.03)
    # 0.01, 0.04, 0.03 of three tests: Holm gives 0.03, 0.06, 0.06;
    # Benjamini and Hochberg give 0.03, 0.04, 0.04.
    var three: List[Float64] = [0.01, 0.04, 0.03]
    var h = holm(three)
    assert_almost_equal(h[0], 0.03, rtol=1e-15)
    assert_almost_equal(h[1], 0.06, rtol=1e-15)
    assert_almost_equal(h[2], 0.06, rtol=1e-15)
    var b = benjamini_hochberg(three)
    assert_almost_equal(b[0], 0.03, rtol=1e-15)
    assert_almost_equal(b[1], 0.04, rtol=1e-15)
    assert_almost_equal(b[2], 0.04, rtol=1e-15)


def test_refusals() raises:
    with assert_raises(contains="one p value or more"):
        _ = bonferroni(List[Float64]())
    var bad: List[Float64] = [-0.1, 1.1, nan[DType.float64]()]
    for v in bad:
        with assert_raises(contains="from 0 to 1"):
            _ = holm([0.5, v])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
