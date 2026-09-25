# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.sine`: the sine the CPU and a GPU kernel share."""

from math.sine import fraction, noise_scale, sin_float32
from std.math import inf, nan, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)


def test_the_sine_agrees_with_libm() raises:
    # Every octant, both signs, and the large angles the noise hashes
    # take, up to a few thousand radians.
    var angles: List[Float32] = [
        0,
        0.3,
        0.8,
        1.2,
        1.9,
        2.6,
        3.0,
        3.6,
        4.4,
        5.1,
        5.9,
        6.5,
        -0.4,
        -2.2,
        -4.9,
        12.9898,
        91.479,
        578.25,
        3141.7,
    ]
    for x in angles:
        assert_almost_equal(sin_float32(x), sin(x), atol=2e-6)


def test_an_angle_that_is_not_finite_has_no_sine() raises:
    for x in [
        inf[DType.float32](),
        -inf[DType.float32](),
        nan[DType.float32](),
    ]:
        var s = sin_float32(x)
        assert_true(s != s)


def test_the_noise_is_the_fraction_of_the_scaled_sine() raises:
    assert_equal(noise_scale(1), Float32(43758.5453))
    assert_equal(fraction(Float32(2.25)), Float32(0.25))
    assert_equal(fraction(Float32(-0.25)), Float32(0.75))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
