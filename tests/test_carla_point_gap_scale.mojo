# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact bit controls for the common power-of-two point-gap scale."""

from extensions.carla.curve_distance import _point_gap_scale
from std.math import inf
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def test_gap_scale_distinguishes_coincidence_and_small_nonzero_components() raises:
    var zero: Array[Float64, 3] = [0.0, 0.0, 0.0]
    assert_equal(_point_gap_scale(zero, zero), 0.0)
    assert_equal(_point_gap_scale([3.5, 0.0, 0.0], [-3.5, 0.0, 0.0]), 4.0)
    var tiny = Float64(1e-200)
    assert_equal(tiny * tiny, 0.0)
    assert_true(_point_gap_scale([0.0, tiny, 0.0], zero) > 0.0)


def test_gap_scale_handles_overflowed_subtraction_and_subnormal_bit_counts() raises:
    var limit = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    var zero: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var scale = _point_gap_scale([limit, 0.0, 0.0], [-limit, 0.0, 0.0])
    assert_equal(bitcast[DType.uint64](scale), UInt64(0x7FE0000000000000))
    assert_equal(
        _point_gap_scale([0.0, 0.0, bitcast[DType.float64](UInt64(1))], zero),
        bitcast[DType.float64](UInt64(1)),
    )
    assert_equal(
        _point_gap_scale([0.0, bitcast[DType.float64](UInt64(7)), 0.0], zero),
        bitcast[DType.float64](UInt64(4)),
    )


def test_gap_scale_refuses_nonfinite_points_and_queries() raises:
    var zero: Array[Float64, 3] = [0.0, 0.0, 0.0]
    with assert_raises(contains="finite coordinates"):
        _ = _point_gap_scale([inf[DType.float64](), 0.0, 0.0], zero)
    with assert_raises(contains="finite coordinates"):
        _ = _point_gap_scale(
            zero, [0.0, 0.0, bitcast[DType.float64](UInt64(0x7FF8000000000001))]
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
