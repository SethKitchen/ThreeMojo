# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

from extensions.carla.curve_distance import (
    _wide_distance_upper,
    _exact_plan_width,
    _exact_point_order,
    _wide_plan_contains,
    _wide_point_order,
)
from std.math import inf
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _point(x: Float64, y: Float64 = 0, z: Float64 = 0) -> Array[Float64, 3]:
    return [x, y, z]


def test_scaled_order_retains_nonzero_underflowed_gaps() raises:
    var tiny = Float64(1e-200)
    var zero = _point(0)
    assert_equal((2.0 * tiny) * (2.0 * tiny), 0.0)
    assert_equal(_wide_point_order(_point(2.0 * tiny), zero, zero), 1)
    assert_equal(_wide_point_order(zero, _point(2.0 * tiny), zero), -1)
    assert_equal(_wide_point_order(zero, zero, zero), 0)
    assert_false(_wide_plan_contains(_point(2.0 * tiny), zero, 2.0 * tiny))
    assert_true(_wide_plan_contains(zero, zero, 2.0 * tiny))


def test_strict_width_uses_the_wide_center() raises:
    assert_false(
        _wide_plan_contains(_point(1000000001.0), _point(1000000000.0), 0.0002)
    )
    assert_true(_wide_plan_contains(_point(1), _point(1), 0.0002))
    assert_false(_wide_plan_contains(_point(0), _point(0), 0.0))
    assert_false(_wide_plan_contains(_point(0), _point(0), -1.0))


def test_exact_boundary_and_subnormal_half_width() raises:
    var eta = bitcast[DType.float64](UInt64(1))
    assert_false(_wide_plan_contains(_point(3, 4), _point(0), 10))
    assert_false(_wide_plan_contains(_point(eta), _point(0), 2.0 * eta))
    assert_true(_wide_plan_contains(_point(0), _point(0), eta))
    assert_false(_wide_plan_contains(_point(eta), _point(0), eta))
    assert_equal(
        _wide_point_order(_point(eta), _point(2.0 * eta), _point(0)), -1
    )
    assert_equal(_exact_plan_width(_point(eta), _point(0), 2.0 * eta), 0)


def test_exact_fallback_keeps_tiny_perturbations_of_equal_distances() raises:
    var small = Float64(bitcast[DType.float32](UInt32(1)))
    # Squared distances are 25-8q+q^2 and 25-10q+q^2. A positive
    # representable Float32 q makes the second point strictly closer.
    assert_equal(
        _wide_point_order(_point(3, 4), _point(0, 5), _point(0, small)), 1
    )
    assert_equal(
        _wide_point_order(_point(0, 5), _point(3, 4), _point(0, small)), -1
    )
    assert_equal(_wide_point_order(_point(3, 4), _point(0, 5), _point(0)), 0)
    assert_true(_wide_plan_contains(_point(3, 4), _point(0, small), 10))
    assert_false(_wide_plan_contains(_point(3, 4), _point(0, -small), 10))


def test_finite_limit_products_and_subtraction_overflow() raises:
    var limit = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    assert_equal(_wide_point_order(_point(-limit), _point(0), _point(limit)), 1)
    assert_equal(
        _wide_point_order(_point(0), _point(-limit), _point(limit)), -1
    )
    assert_equal(_wide_point_order(_point(limit), _point(-limit), _point(0)), 0)
    assert_false(_wide_plan_contains(_point(-limit), _point(limit), limit))
    assert_true(_wide_plan_contains(_point(0), _point(0), limit))
    assert_false(_wide_plan_contains(_point(limit, limit), _point(0), limit))


def test_exact_arithmetic_agrees_with_integer_geometry() raises:
    # Integer arithmetic supplies independent expectations for these cases.
    var x = -5
    while x <= 5:
        var y = -5
        while y <= 5:
            var a = _point(Float64(x), Float64(y), 2)
            var b = _point(3, -1, -2)
            var query = _point(1, 2, 0)
            var da = (x - 1) * (x - 1) + (y - 2) * (y - 2) + 4
            var db = 4 + 9 + 4
            var order = Int(da > db) - Int(da < db)
            assert_equal(_wide_point_order(a, b, query), order)
            assert_equal(_exact_point_order(a, b, query), order)
            var plan = 4 * ((x - 1) * (x - 1) + (y - 2) * (y - 2)) - 25
            assert_equal(_wide_plan_contains(a, query, 5), plan < 0)
            assert_equal(
                _exact_plan_width(a, query, 5), Int(plan > 0) - Int(plan < 0)
            )
            y += 1
        x += 1


def test_nonfinite_points_and_width_raise() raises:
    with assert_raises(contains="finite coordinates"):
        _ = _wide_point_order(
            _point(inf[DType.float64]()), _point(0), _point(0)
        )
    with assert_raises(contains="finite width"):
        _ = _wide_plan_contains(_point(0), _point(0), inf[DType.float64]())


def test_distance_upper_retains_scale_and_overflow() raises:
    var eta = bitcast[DType.float64](UInt64(1))
    var limit = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    assert_equal(_wide_distance_upper(_point(0), _point(0)), 0.0)
    assert_true(_wide_distance_upper(_point(eta), _point(0)) >= eta)
    assert_true(_wide_distance_upper(_point(1e-200), _point(0)) >= 1e-200)
    var upper = _wide_distance_upper(_point(3, 4), _point(0))
    assert_true(upper >= 5.0)
    assert_true(upper < 5.00000000000001)
    assert_equal(
        _wide_distance_upper(_point(-limit), _point(limit)),
        inf[DType.float64](),
    )
    with assert_raises(contains="finite coordinates"):
        _ = _wide_distance_upper(_point(inf[DType.float64]()), _point(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
