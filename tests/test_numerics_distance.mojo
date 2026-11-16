# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The exact Euclidean distance transform, with its nearest seeds."""

from extensions.numerics.distance import NO_SEED, distance_transform
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)


def test_distance_transform_is_exact() raises:
    # One seed in a 5 by 4 by 3 grid: the squared distance is i^2 + j^2 + k^2
    # from it, and every point names it.
    var seeds = List[Bool](length=60, fill=False)
    seeds[0] = True
    var result = distance_transform(seeds, 5, 4, 3)
    var worst = 0.0
    var named = True
    for k in range(3):
        for j in range(4):
            for i in range(5):
                var at = i + 5 * (j + 4 * k)
                worst = max(
                    worst, abs(result[0][at] - Float64(i * i + j * j + k * k))
                )
                named = named and result[1][at] == 0
    assert_equal(worst, 0)
    assert_true(named)
    # Two seeds on a line split it between them.
    var line: List[Bool] = [True, False, False, False, False, False, True]
    var split = distance_transform(line, 7, 1, 1)
    assert_equal(split[0][3], 9)
    assert_equal(split[1][2], 0)
    assert_equal(split[1][4], 6)
    # No seed at all.
    var none = distance_transform(List[Bool](length=4, fill=False), 2, 2, 1)
    assert_equal(none[0][3], NO_SEED)
    assert_equal(none[1][3], -1)
    with assert_raises(contains="at least one point"):
        _ = distance_transform(List[Bool](), 0, 1, 1)
    with assert_raises(contains="at least one point"):
        _ = distance_transform(List[Bool](), 1, 0, 1)
    with assert_raises(contains="at least one point"):
        _ = distance_transform(List[Bool](), 1, 1, 0)
    with assert_raises(contains="fill the grid"):
        _ = distance_transform(List[Bool](length=3, fill=True), 2, 2, 1)


def test_spacing_of_each_axis() raises:
    # One seed in a 3 by 2 by 2 grid, with steps of 2, 3 and 5.
    var seeds = List[Bool](length=12, fill=False)
    seeds[0] = True
    var result = distance_transform(seeds, 3, 2, 2, 2.0, 3.0, 5.0)
    for k in range(2):
        for j in range(2):
            for i in range(3):
                var at = i + 3 * (j + 2 * k)
                var x = 2.0 * Float64(i)
                var y = 3.0 * Float64(j)
                var z = 5.0 * Float64(k)
                assert_equal(result[0][at], x * x + y * y + z * z)
                assert_equal(result[1][at], 0)
    var bad: List[Float64] = [
        0.0,
        -1.0,
        inf[DType.float64](),
        nan[DType.float64](),
    ]
    for s in bad:
        with assert_raises(contains="spacing must be positive"):
            _ = distance_transform(seeds, 3, 2, 2, s, 1.0, 1.0)
        with assert_raises(contains="spacing must be positive"):
            _ = distance_transform(seeds, 3, 2, 2, 1.0, s, 1.0)
        with assert_raises(contains="spacing must be positive"):
            _ = distance_transform(seeds, 3, 2, 2, 1.0, 1.0, s)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
