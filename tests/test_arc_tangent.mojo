# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.arc_tangent`: the arc tangent a GPU kernel can call."""

from math.arc_tangent import atan2_float32, atan_float32
from std.math import atan, atan2, inf, nan, pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)


def test_the_arc_tangent_agrees_with_libm() raises:
    # Each of the three folds: below tan(pi / 8), up to tan(3 pi / 8), and
    # beyond, on both sides of zero.
    var xs: List[Float32] = [0, 0.1, 0.4, 0.5, 1, 2, 2.5, 100, -0.3, -1, -7]
    for x in xs:
        assert_almost_equal(atan_float32(x), atan(x), atol=1e-6)
    assert_almost_equal(atan_float32(inf[DType.float32]()), Float32(pi) / 2)


def test_the_angle_of_a_point_agrees_with_libm() raises:
    # Every quadrant, and every axis.
    var ys: List[Float32] = [1, 1, -1, -1, 0, 0, 1, -1, 0.3, -0.3]
    var xs: List[Float32] = [1, -1, 1, -1, 1, -1, 0, 0, -5, -5]
    for at in range(len(ys)):
        assert_almost_equal(
            atan2_float32(ys[at], xs[at]), atan2(ys[at], xs[at]), atol=1e-6
        )


def test_the_origin_and_nan() raises:
    assert_equal(atan2_float32(0, 0), 0)
    var nothing = nan[DType.float32]()
    var got = atan2_float32(nothing, 1)
    assert_true(got != got)
    got = atan2_float32(1, nothing)
    assert_true(got != got)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
