# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Focused controls for the fixed-s stored-point arithmetic boundary."""

from extensions.carla.curve_distance import (
    _DistanceInterval,
    _exact_point_order,
    _next_down,
    _next_up,
    _wide_point_order,
)
from std.math import inf, isnan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_order_agrees_with_independent_integer_geometry() raises:
    for x in range(-5, 6):
        for y in range(-5, 6):
            var a: Array[Float64, 3] = [Float64(x), Float64(y), 2.0]
            var b: Array[Float64, 3] = [3.0, -1.0, -2.0]
            var query: Array[Float64, 3] = [1.0, 2.0, 0.0]
            var da = (x - 1) * (x - 1) + (y - 2) * (y - 2) + 4
            var order = Int(da > 17) - Int(da < 17)
            assert_equal(_wide_point_order(a, b, query), order)
            assert_equal(_exact_point_order(a, b, query), order)


def test_subnormal_and_zero_order_remains_exact() raises:
    var eta = bitcast[DType.float64](UInt64(1))
    var zero = Array[Float64, 3](fill=0.0)
    assert_equal(_wide_point_order(zero, zero, zero), 0)
    assert_equal(_wide_point_order([eta, 0.0, 0.0], zero, zero), 1)
    assert_equal(_wide_point_order(zero, [eta, 0.0, 0.0], zero), -1)
    assert_equal(_wide_point_order([eta, 0.0, 0.0], [-eta, 0.0, 0.0], zero), 0)


def test_finite_limit_subtraction_and_tiny_tie_break() raises:
    var limit = Float64(1.7976931348623157e308)
    var zero = Array[Float64, 3](fill=0.0)
    assert_equal(
        _wide_point_order([-limit, 0.0, 0.0], zero, [limit, 0.0, 0.0]), 1
    )
    assert_equal(
        _wide_point_order([limit, 0.0, 0.0], [-limit, 0.0, 0.0], zero), 0
    )
    var small = Float64(bitcast[DType.float32](UInt32(1)))
    assert_equal(
        _wide_point_order([3.0, 4.0, 0.0], [0.0, 5.0, 0.0], [0.0, small, 0.0]),
        1,
    )
    assert_equal(
        _wide_point_order([3.0, 4.0, 0.0], [0.0, 5.0, 0.0], [0.0, -small, 0.0]),
        -1,
    )
    assert_equal(_wide_point_order([3.0, 4.0, 0.0], [0.0, 5.0, 0.0], zero), 0)


def test_nonfinite_points_raise_in_each_argument() raises:
    var bad: Array[Float64, 3] = [inf[DType.float64](), 0.0, 0.0]
    var zero = Array[Float64, 3](fill=0.0)
    with assert_raises(contains="finite coordinates"):
        _ = _wide_point_order(bad, zero, zero)
    with assert_raises(contains="finite coordinates"):
        _ = _wide_point_order(zero, bad, zero)
    with assert_raises(contains="finite coordinates"):
        _ = _wide_point_order(zero, zero, bad)


def test_adjacent_bounds_include_signed_zero_and_infinity() raises:
    var eta = bitcast[DType.float64](UInt64(1))
    var nan = bitcast[DType.float64](UInt64(0x7FF8000000000000))
    assert_equal(_next_up(-0.0), eta)
    assert_equal(_next_down(0.0), -eta)
    assert_equal(_next_up(-eta), -0.0)
    assert_true(_next_up(1.0) > 1.0)
    assert_true(_next_up(-1.0) > -1.0)
    assert_equal(_next_up(inf[DType.float64]()), inf[DType.float64]())
    assert_equal(_next_down(-inf[DType.float64]()), -inf[DType.float64]())
    assert_true(isnan(_next_up(nan)))


def test_interval_points_and_indeterminate_operations() raises:
    var nan = bitcast[DType.float64](UInt64(0x7FF8000000000000))
    var whole = _DistanceInterval.whole()
    assert_false(whole.is_finite())
    assert_true(whole.contains(0))
    assert_equal(_DistanceInterval.point(nan).low, whole.low)
    assert_equal(_DistanceInterval.rounded(nan, 0).high, whole.high)
    assert_equal(_DistanceInterval.rounded(0, nan).low, whole.low)
    var zero = _DistanceInterval.point(0)
    var one = _DistanceInterval.point(1)
    assert_true((zero + zero).is_point(0))
    assert_true((zero + one).is_point(1))
    assert_true((one + zero).is_point(1))
    assert_true((one - one).contains(0))
    assert_true((one + one).contains(2))
    assert_equal((one / zero).low, whole.low)
    assert_true((one / one).is_point(1))
    assert_true((zero / _DistanceInterval.point(2)).is_point(0))
    var infinity = _DistanceInterval.point(inf[DType.float64]())
    assert_equal((infinity / infinity).low, whole.low)
    assert_true((one / _DistanceInterval.point(3)).contains(1.0 / 3.0))
    assert_true(zero.square().is_point(0))
    var crossed = _DistanceInterval(-1.0, 2.0).square()
    assert_equal(crossed.low, 0.0)
    assert_true(crossed.high >= 4.0)
    var positive = _DistanceInterval(2.0, 3.0).square()
    assert_true(positive.low <= 4.0)
    assert_true(positive.high >= 9.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
