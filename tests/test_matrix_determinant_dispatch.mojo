# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""All four compile-time determinant dispatch leaves preserve their values."""

from math.matrix_determinant import _determinant_f32
from std.memory import bitcast
from std.testing import TestSuite, assert_equal


def test_order_one_preserves_finite_float32_values() raises:
    var values = [
        Float32(0),
        Float32(-2),
        bitcast[DType.float32](UInt32(1)),
        bitcast[DType.float32](UInt32(0x7F7FFFFF)),
    ]
    for value in values:
        var a = Array[Float32, 1](fill=value)
        assert_equal(_determinant_f32[1](a), Float64(value))


def test_order_two_dispatch_preserves_orientation() raises:
    var a: Array[Float32, 4] = [1, 3, 2, 4]
    assert_equal(_determinant_f32[2](a), Float64(-2))
    var singular: Array[Float32, 4] = [1, 2, 2, 4]
    assert_equal(_determinant_f32[2](singular), Float64(0))


def test_order_three_dispatch_preserves_a_dense_determinant() raises:
    # Laplace expansion of the transpose: 3*(-29) - 1*(-13) + 4*(-4).
    var a: Array[Float32, 9] = [3, 1, 4, 1, 5, 9, 2, 6, 5]
    assert_equal(_determinant_f32[3](a), Float64(-90))
    var singular = Array[Float32, 9](fill=1)
    assert_equal(_determinant_f32[3](singular), Float64(0))


def test_order_four_dispatch_preserves_orientation_and_rank() raises:
    # The 24-term signed permutation sum of these integers is exactly 72.
    var a: Array[Float32, 16] = [1, 2, 3, 4, 5, 6, 7, 8, 2, 6, 4, 8, 3, 1, 1, 2]
    assert_equal(_determinant_f32[4](a), Float64(72))
    for i in range(4):
        var value = a[i]
        a[i] = a[i + 4]
        a[i + 4] = value
    assert_equal(_determinant_f32[4](a), Float64(-72))
    var singular = Array[Float32, 16](fill=1)
    assert_equal(_determinant_f32[4](singular), Float64(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
