# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The lower-first clamp preserves all three operands and their order."""

from math.utils import clamp, clamp_lower_first
from std.benchmark import black_box
from std.memory import bitcast
from std.testing import TestSuite, assert_equal


def test_float32_lower_first_clamp_preserves_operand_bits() raises:
    var words: List[UInt32] = [
        0x00000000,
        0x80000000,
        0x7F800000,
        0xFF800000,
        0x7FC00001,
        0xFFC00001,
        0x7FA00001,
        0xFFA00001,
        0x00000001,
        0x80000001,
        0x3F000000,
        0x3F7FFFFF,
        0x3F800000,
        0x3F800001,
        0xBF800000,
    ]
    for value_word in words:
        for low_word in words:
            for high_word in words:
                var value = black_box(bitcast[DType.float32](value_word))
                var low = black_box(bitcast[DType.float32](low_word))
                var high = black_box(bitcast[DType.float32](high_word))
                var expected = min(max(value, low), high)
                assert_equal(
                    bitcast[DType.uint32](clamp_lower_first(value, low, high)),
                    bitcast[DType.uint32](expected),
                )
    var nan = black_box(bitcast[DType.float32](UInt32(0x7FC00001)))
    assert_equal(clamp_lower_first(nan, 0, 1), Float32(0))
    assert_equal(clamp(nan, 0, 1), Float32(1))


def test_float64_lower_first_clamp_preserves_operand_bits() raises:
    var words: List[UInt64] = [
        0x0000000000000000,
        0x8000000000000000,
        0x7FF0000000000000,
        0xFFF0000000000000,
        0x7FF8000000000001,
        0xFFF8000000000001,
        0x7FF4000000000001,
        0xFFF4000000000001,
        0x0000000000000001,
        0x8000000000000001,
        0x3FE0000000000000,
        0x3FEFFFFFFFFFFFFF,
        0x3FF0000000000000,
        0x3FF0000000000001,
        0xBFF0000000000000,
    ]
    for value_word in words:
        for low_word in words:
            for high_word in words:
                var value = black_box(bitcast[DType.float64](value_word))
                var low = black_box(bitcast[DType.float64](low_word))
                var high = black_box(bitcast[DType.float64](high_word))
                var expected = min(max(value, low), high)
                assert_equal(
                    bitcast[DType.uint64](clamp_lower_first(value, low, high)),
                    bitcast[DType.uint64](expected),
                )
    var nan = black_box(bitcast[DType.float64](UInt64(0x7FF8000000000001)))
    assert_equal(clamp_lower_first(nan, 0, 1), Float64(0))
    assert_equal(clamp(nan, 0, 1), Float64(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
