# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.sine`: the sine the CPU and a GPU kernel share."""

from math.sine import _complement_fraction, fraction, noise_scale, sin_float32
from std.math import inf, isfinite, nan, sin
from std.memory import bitcast
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
        var actual = sin_float32(x)
        assert_true(isfinite(actual))
        assert_almost_equal(actual, sin(x), atol=2e-6)


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


def test_large_finite_angles_agree_with_libm() raises:
    var samples: List[Float32] = [
        8191.99951171875,
        8192,
        8192.0009765625,
        1e8,
        1e9,
        1e10,
        1e15,
        1e30,
        3e38,
    ]
    for x in samples:
        for angle in [x, -x]:
            var actual = sin_float32(angle)
            assert_true(isfinite(actual))
            assert_almost_equal(actual, sin(angle), atol=2e-6)
    # Stratify the whole finite exponent range and vary the significand.
    var state = UInt32(42)
    for exponent in range(1, 255):
        for _ in range(16):
            state = state * 1664525 + 1013904223
            var bits = (UInt32(exponent) << 23) | (state & 0x7FFFFF)
            var x = bitcast[DType.float32](bits)
            var actual = sin_float32(x)
            assert_true(isfinite(actual))
            assert_true(abs(actual) <= 1)
            assert_almost_equal(actual, sin(x), atol=2e-6)
            var negative = sin_float32(-x)
            assert_true(isfinite(negative))
            assert_almost_equal(negative, sin(-x), atol=2e-6)


def test_sine_preserves_signed_zero_and_subnormal_angles() raises:
    for bits in [UInt32(0), UInt32(0x80000000), UInt32(1), UInt32(0x80000001)]:
        var x = bitcast[DType.float32](bits)
        assert_equal(bitcast[DType.uint32](sin_float32(x)), bits)


def test_fraction_complement_preserves_low_word_carry() raises:
    # Negating a zero low word carries into the high word; a nonzero low
    # word does not. These exact words test both arithmetic cases even
    # though a zero low word does not occur in Float32 angle reduction.
    var carry = _complement_fraction(0x81234567, 0)
    assert_equal(carry[0], UInt32(0x7EDCBA99))
    assert_equal(carry[1], UInt32(0))
    var no_carry = _complement_fraction(0x81234567, 1)
    assert_equal(no_carry[0], UInt32(0x7EDCBA98))
    assert_equal(no_carry[1], UInt32(0xFFFFFFFF))
    var all_bits = _complement_fraction(0xFFFFFFFF, 0xFFFFFFFF)
    assert_equal(all_bits[0], UInt32(0))
    assert_equal(all_bits[1], UInt32(1))
    var zero = _complement_fraction(0, 0)
    assert_equal(zero[0], UInt32(0))
    assert_equal(zero[1], UInt32(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
