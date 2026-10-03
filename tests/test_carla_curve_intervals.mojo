# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent arithmetic and branch controls for bounded lane expressions."""

from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _next_down,
    _next_up,
    _roundoff,
)
from extensions.carla.curve_trig import (
    _atan2_jet,
    _atan_jet,
    _curve_atan,
    _curve_atan2,
    _curve_cos,
    _curve_sin,
    _curve_sincos,
    _sign_bit,
    _sincos_jet,
)
from std.math import inf, isnan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)


def test_adjacent_rounding_covers_zero_subnormals_and_finite_limit() raises:
    var tiny = bitcast[DType.float64](UInt64(1))
    var largest = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    var infinity = inf[DType.float64]()
    var quiet_nan = bitcast[DType.float64](UInt64(0x7FF8000000000000))
    assert_equal(_next_up(0.0), tiny)
    assert_equal(_next_up(-0.0), tiny)
    assert_equal(_next_down(0.0), -tiny)
    assert_equal(_next_up(-tiny), -0.0)
    assert_equal(_next_down(tiny), 0.0)
    assert_equal(_next_up(largest), infinity)
    assert_equal(_next_down(-largest), -infinity)
    assert_equal(_next_down(infinity), largest)
    assert_equal(_next_up(-infinity), -largest)
    assert_equal(_next_up(infinity), infinity)
    assert_true(isnan(_next_up(quiet_nan)))
    assert_true(_roundoff(0.0) >= tiny)
    assert_true(_roundoff(1.0) > 1.1102230246251565e-16)


def test_interval_arithmetic_contains_exact_rational_controls() raises:
    var one = _Interval.point(1.0)
    var zero = _Interval.point(0.0)
    var third = one / _Interval.point(3.0)
    assert_true(third.low < 0.333333333333333333333333333333333333)
    assert_true(third.high > 0.333333333333333333333333333333333333)
    var product = _Interval(-2.0, 3.0) * _Interval(-4.0, 5.0)
    assert_true(product.low <= -12.0)
    assert_true(product.high >= 15.0)
    assert_true((_Interval(-2.0, -1.0) / _Interval(2.0, 4.0)).contains(-1.0))
    assert_true((_Interval(-2.0, -1.0) / _Interval(2.0, 4.0)).contains(-0.25))
    assert_true((_Interval(-2.0, 3.0).square()).contains(0.0))
    assert_true((_Interval(-2.0, 3.0).square()).contains(9.0))
    assert_true(_Interval(4.0, 9.0).sqrt().contains(2.0))
    assert_true(_Interval(4.0, 9.0).sqrt().contains(3.0))
    assert_false(_Interval(-1.0, 2.0).sqrt().is_finite())
    assert_true((zero + one).is_point(1.0))
    assert_true((one + zero).is_point(1.0))
    assert_true((one * zero).is_point(0.0))
    assert_true((zero * one).is_point(0.0))
    assert_true((zero / one).is_point(0.0))
    assert_true(zero.square().is_point(0.0))
    assert_true(zero.sqrt().is_point(0.0))
    assert_false((one / _Interval(-1.0, 1.0)).is_finite())
    assert_false((zero * _Interval.whole()).is_finite())
    assert_false(
        (
            _Interval.point(inf[DType.float64]())
            - _Interval.point(inf[DType.float64]())
        ).is_finite()
    )
    assert_equal(_Interval(-3.0, 2.0).absolute().low, 0.0)
    assert_equal(_Interval(-3.0, -2.0).absolute().low, 2.0)
    assert_equal(_Interval(-3.0, -2.0).magnitude(), 3.0)
    assert_true(_Interval(-3.0, -2.0).width() >= 1.0)
    assert_true(_Interval(1.0, 2.0).hull(_Interval(-2.0, -1.0)).contains(0.0))
    assert_equal(_Interval(1.0, 4.0).minimum(_Interval(2.0, 3.0)).high, 3.0)
    assert_equal(_Interval(1.0, 4.0).maximum(_Interval(2.0, 3.0)).low, 2.0)


def test_jets_bound_actual_polynomial_derivatives_and_roundoff() raises:
    var x = _Jet.variable(0.25, 0.5)
    var cubic = x * x * x
    assert_true(cubic.value.contains(0.015625))
    assert_true(cubic.value.contains(0.125))
    assert_true(cubic.first.contains(0.1875))
    assert_true(cubic.first.contains(0.75))
    assert_true(cubic.second.contains(1.5))
    assert_true(cubic.second.contains(3.0))
    var quotient = _Jet.constant(1.0) / x
    assert_true(quotient.value.contains(2.0))
    assert_true(quotient.first.contains(-16.0))
    assert_true(quotient.second.contains(128.0))
    var root = _Jet.variable(1.0, 4.0).sqrt()
    assert_true(root.value.contains(2.0))
    assert_true(root.first.contains(0.25))
    assert_true(root.second.contains(-0.25))
    assert_true((_Jet.constant(0.0) * x).rounded_value().is_point(0.0))
    assert_true((x * _Jet.constant(0.0)).rounded_value().is_point(0.0))
    assert_true((_Jet.constant(1.0) * x).rounded_value().contains(0.25))
    assert_true((x * _Jet.constant(1.0)).rounded_value().contains(0.5))
    assert_true((_Jet.constant(0.0) + x).value.contains(0.25))
    assert_true((x + _Jet.constant(0.0)).value.contains(0.5))
    assert_true(_Jet.constant(0.0).sqrt().value.is_point(0.0))
    assert_false(
        (_Jet.constant(1.0) / _Jet.variable(-1.0, 1.0)).value.is_finite()
    )
    assert_false(_Jet.variable(0.0, 1.0).sqrt().first.is_finite())


def test_local_trig_matches_independent_high_precision_values() raises:
    # Decimal values are independently rounded high-precision constants.
    assert_almost_equal(
        _curve_sin(0.3), 0.295520206661339575105320745685, atol=4e-15
    )
    assert_almost_equal(
        _curve_cos(0.3), 0.955336489125606019642310227568, atol=4e-15
    )
    assert_almost_equal(
        _curve_atan(0.3), 0.291456794477867091995604621433, atol=8e-15
    )
    assert_almost_equal(
        _curve_sin(1000000.0), -0.349993502171292952117652486781, atol=4e-15
    )
    assert_almost_equal(
        _curve_cos(1000000.0), 0.936752127533144786938532535075, atol=4e-15
    )
    assert_almost_equal(
        _curve_atan(10.0), 1.471127674303734591852875571762, atol=8e-15
    )
    assert_almost_equal(
        _curve_atan(-10.0), -1.471127674303734591852875571762, atol=8e-15
    )
    assert_almost_equal(
        _curve_atan2(1.0, -1.0), 2.356194490192344928846982537460, atol=8e-15
    )
    assert_almost_equal(
        _curve_atan2(-1.0, -1.0), -2.356194490192344928846982537460, atol=8e-15
    )


def test_signed_zero_infinity_quadrants_and_winding_are_explicit() raises:
    var pi = Float64(3.141592653589793)
    var half_pi = Float64(1.5707963267948966)
    var infinity = inf[DType.float64]()
    var quiet_nan = bitcast[DType.float64](UInt64(0x7FF8000000000000))
    assert_true(_sign_bit(_curve_sin(-0.0)))
    assert_true(_sign_bit(_curve_atan(-0.0)))
    assert_true(_sign_bit(_curve_atan2(-0.0, 0.0)))
    assert_false(_sign_bit(_curve_atan2(0.0, 0.0)))
    assert_equal(_curve_atan2(0.0, -0.0), pi)
    assert_equal(_curve_atan2(-0.0, -0.0), -pi)
    assert_equal(_curve_atan2(1.0, 0.0), half_pi)
    assert_equal(_curve_atan2(-1.0, -0.0), -half_pi)
    assert_equal(_curve_atan(infinity), half_pi)
    assert_equal(_curve_atan(-infinity), -half_pi)
    assert_equal(_curve_atan2(infinity, infinity), pi * 0.25)
    assert_equal(_curve_atan2(infinity, -infinity), pi * 0.75)
    assert_equal(_curve_atan2(-infinity, -infinity), -pi * 0.75)
    assert_true(isnan(_curve_atan(quiet_nan)))
    assert_true(isnan(_curve_atan2(quiet_nan, 1.0)))
    assert_true(isnan(_curve_atan2(1.0, quiet_nan)))
    assert_true(isnan(_curve_sin(infinity)))
    assert_true(isnan(_curve_cos(quiet_nan)))
    for angle in [-6.0, -4.0, -2.0, 0.2, 2.0, 4.0, 6.0, 1048577.0]:
        var values = _curve_sincos(angle)
        assert_true(abs(values[0]) <= 1.000000000000004)
        assert_true(abs(values[1]) <= 1.000000000000004)


def test_trig_jets_enclose_scalar_values_and_keep_branch_uncertainty() raises:
    for low in [-3.2, -1.6, -0.8, -0.1, 0.1, 0.78, 1.56, 3.13]:
        var high = low + 0.03
        var bounds = _sincos_jet(_Jet.variable(low, high))
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
            var x = low + (high - low) * fraction
            var scalar = _curve_sincos(x)
            assert_true(bounds[0].rounded_value().contains(scalar[0]))
            assert_true(bounds[1].rounded_value().contains(scalar[1]))
    var point = _sincos_jet(_Jet.variable(0.0, 0.0))
    assert_true(point[0].first.contains(1.0))
    assert_true(point[1].second.contains(-1.0))
    var wide = _sincos_jet(_Jet.variable(-20.0, 20.0))
    assert_false(wide[0].first.is_finite())
    var outside = _sincos_jet(_Jet.variable(1048577.0, 1048578.0))
    assert_true(outside[0].value.contains(-1.0))
    assert_true(outside[0].value.contains(1.0))
    assert_false(outside[0].first.is_finite())
    var crossing = _sincos_jet(_Jet.variable(1048575.0, 1048577.0))
    assert_false(crossing[0].value.is_finite())
    for low in [-2.0, -0.5, -0.1, 0.3, 0.4, 0.9, 1.0, 2.4, 10.0]:
        var high = low + 0.2
        var bound = _atan_jet(_Jet.variable(low, high)).rounded_value()
        assert_true(bound.contains(_curve_atan(low)))
        assert_true(bound.contains(_curve_atan(high)))
    var zero = _Jet.constant(0.0)
    var positive = _Jet.constant(1.0)
    var negative = _Jet.constant(-1.0)
    assert_true(_atan2_jet(zero, positive).rounded_value().contains(0.0))
    assert_true(
        _atan2_jet(zero, negative).rounded_value().contains(3.141592653589793)
    )
    assert_true(
        _atan2_jet(positive, zero).rounded_value().contains(1.5707963267948966)
    )
    assert_true(
        _atan2_jet(negative, zero).rounded_value().contains(-1.5707963267948966)
    )
    for x in [-2.0, -0.5, 0.5, 2.0]:
        for y in [-2.0, -0.5, 0.5, 2.0]:
            var bound = _atan2_jet(
                _Jet.variable(y, y + 0.01), _Jet.variable(x, x + 0.01)
            )
            assert_true(bound.rounded_value().contains(_curve_atan2(y, x)))
    assert_false(
        _atan2_jet(_Jet.variable(-0.1, 0.1), negative).first.is_finite()
    )
    assert_false(
        _atan2_jet(
            _Jet.variable(-0.1, 0.1), _Jet.variable(-0.1, 0.1)
        ).first.is_finite()
    )


def _contains_zero_quadrant(bound: _Interval, scalar: Float64) raises:
    var angle = _atan2_jet(
        _Jet(bound, _Interval.point(0.0), _Interval.point(0.0), 0.0),
        _Jet.constant(-1.0),
    ).rounded_value()
    assert_true(angle.contains(_curve_atan2(scalar, -1.0)))


def test_signed_zero_arithmetic_and_hulls_keep_all_atan2_branches() raises:
    for left in [-0.0, 0.0]:
        for right in [-0.0, 0.0]:
            var a = _Interval.point(left)
            var b = _Interval.point(right)
            _contains_zero_quadrant(a + b, left + right)
            _contains_zero_quadrant(a - b, left - right)
            _contains_zero_quadrant(a * b, left * right)
            _contains_zero_quadrant(a.hull(b), left)
            _contains_zero_quadrant(a.hull(b), right)
            var x = _Jet.constant(left)
            var y = _Jet.constant(right)
            assert_true(
                _atan2_jet(x + y, _Jet.constant(-1.0))
                .rounded_value()
                .contains(_curve_atan2(left + right, -1.0))
            )
            assert_true(
                _atan2_jet(x - y, _Jet.constant(-1.0))
                .rounded_value()
                .contains(_curve_atan2(left - right, -1.0))
            )
            assert_true(
                _atan2_jet(x * y, _Jet.constant(-1.0))
                .rounded_value()
                .contains(_curve_atan2(left * right, -1.0))
            )
        for factor in [-2.0, -1.0, 1.0, 2.0]:
            var a = _Interval.point(left)
            var b = _Interval.point(factor)
            _contains_zero_quadrant(a * b, left * factor)
            _contains_zero_quadrant(b * a, factor * left)
            _contains_zero_quadrant(a / b, left / factor)
            _contains_zero_quadrant(-a, -left)
            _contains_zero_quadrant(a.square(), left * left)
            var x = _Jet.constant(left)
            var y = _Jet.constant(factor)
            assert_true(
                _atan2_jet(x * y, _Jet.constant(-1.0))
                .rounded_value()
                .contains(_curve_atan2(left * factor, -1.0))
            )
            assert_true(
                _atan2_jet(x / y, _Jet.constant(-1.0))
                .rounded_value()
                .contains(_curve_atan2(left / factor, -1.0))
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
