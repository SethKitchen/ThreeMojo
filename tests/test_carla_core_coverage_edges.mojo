# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Additive direct controls motivated by the historical coverage gaps.

SOURCE ONLY: not compiled or run. These controls do not replace, shorten, or
relax any original suite, workload, assertion, tolerance, or five-second gate.
"""

from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _power_product_bound,
    _power_quotient_bound,
    _roundoff,
)
from extensions.carla.curve_trig import (
    _atan2_derivative,
    _atan2_jet,
    _atan_derivative,
    _atan_jet,
    _curve_atan2,
    _curve_sinc,
    _sinc_derivative,
    _sinc_jet,
    _sincos_derivative,
)
from std.math import inf, isfinite, isnan
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def _assert_whole(value: _Interval) raises:
    assert_equal(value.low, -inf[DType.float64]())
    assert_equal(value.high, inf[DType.float64]())


def test_nan_construction_and_each_indeterminate_endpoint_pair() raises:
    var infinity = inf[DType.float64]()
    var nan = bitcast[DType.float64](UInt64(0x7FF8000000000001))
    _assert_whole(_Interval.point(nan))
    _assert_whole(_Interval.rounded(nan, 1.0))
    _assert_whole(_Interval.rounded(1.0, nan))
    assert_true(_Interval.rounded(1.0, 2.0).is_finite())
    # Each row makes only the named a/b/c/d product indeterminate; all
    # intervals are ordered and neither interval is the 0 or 1 shortcut.
    _assert_whole(_Interval(-infinity, -2.0) * _Interval(0.0, 1.0))  # a
    _assert_whole(_Interval(-infinity, -2.0) * _Interval(-1.0, 0.0))  # b
    _assert_whole(_Interval(2.0, infinity) * _Interval(0.0, 1.0))  # c
    _assert_whole(_Interval(2.0, infinity) * _Interval(-1.0, 0.0))  # d
    assert_true((_Interval(2.0, 3.0) * _Interval(4.0, 5.0)).is_finite())
    # Independent inf/inf corners, with no zero-containing denominator.
    _assert_whole(_Interval(-infinity, -2.0) / _Interval(-infinity, -3.0))  # a
    _assert_whole(_Interval(-infinity, -2.0) / _Interval(3.0, infinity))  # b
    _assert_whole(_Interval(2.0, infinity) / _Interval(-infinity, -3.0))  # c
    _assert_whole(_Interval(2.0, infinity) / _Interval(3.0, infinity))  # d
    assert_true((_Interval(2.0, 3.0) / _Interval(4.0, 5.0)).is_finite())
    assert_true(
        (_Interval.point(0.0) / _Interval.point(infinity)).contains(0.0)
    )
    assert_true((_Interval.point(0.0) / _Interval.point(2.0)).is_point(0.0))


def test_nonsingleton_power_scaling_and_each_zero_endpoint() raises:
    var one = _Interval(-2.0, 3.0)
    var two = _Interval(2.0, 4.0)
    var product = _power_product_bound(one, two)
    assert_true(product.contains(-8.0))
    assert_true(product.contains(12.0))
    var quotient = _power_quotient_bound(one, two)
    assert_true(quotient.contains(-1.0))
    assert_true(quotient.contains(1.5))
    for box in [
        _Interval(0.0, 2.0),
        _Interval(-2.0, 0.0),
        _Interval(-0.0, 0.0),
    ]:
        var p = _power_product_bound(box, _Interval.point(2.0))
        assert_equal(p.low, box.low * 2.0)
        assert_equal(p.high, box.high * 2.0)
        var q = _power_quotient_bound(box, _Interval.point(2.0))
        assert_equal(q.low, box.low / 2.0)
        assert_equal(q.high, box.high / 2.0)


def test_zero_jet_root_requires_zero_error_and_both_derivatives() raises:
    var zero = _Interval.point(0.0)
    var unit = _Interval.point(1.0)
    var with_first = _Jet(zero, unit, zero, 0.0).sqrt()
    var with_second = _Jet(zero, zero, unit, 0.0).sqrt()
    var with_error = _Jet(zero, zero, zero, 0.125).sqrt()
    assert_false(with_first.first.is_finite())
    assert_false(with_second.second.is_finite())
    assert_false(with_error.first.is_finite())
    assert_true(_Jet(zero, zero, zero, 0.0).sqrt().first.is_point(0.0))
    assert_true(_Jet.variable(1.0, 4.0).sqrt().first.is_finite())
    assert_equal(_roundoff(-1.0), inf[DType.float64]())
    assert_equal(_roundoff(inf[DType.float64]()), inf[DType.float64]())
    # Exponent field 2 selects the subnormal half-spacing branch.
    assert_equal(
        bitcast[DType.uint64](
            _roundoff(bitcast[DType.float64](UInt64(0x0020000000000000)))
        ),
        UInt64(2),
    )
    assert_true(_roundoff(1.0) > 0.0)


def test_scalar_derivative_modes_guards_and_zero_axes() raises:
    var derivative = _sincos_derivative(0.0)
    assert_equal(derivative[0], 1.0)
    assert_equal(derivative[1], 0.0)
    for angle in [-6.0, -4.0, -2.0, 0.2, 2.0, 4.0, 6.0, 1048577.0]:
        var pair = _sincos_derivative(angle)
        assert_true(isfinite(pair[0]))
        assert_true(isfinite(pair[1]))
    var unsupported = _sincos_derivative(inf[DType.float64]())
    assert_true(isnan(unsupported[0]))
    assert_true(isnan(unsupported[1]))
    assert_equal(_atan_derivative(0.0), 1.0)
    assert_equal(_atan_derivative(1.0), 0.5)
    for value in [-10.0, -2.0, -0.5, 0.3, 0.5, 2.0, 10.0]:
        assert_true(_atan_derivative(value) > 0.0)
    assert_equal(_atan2_derivative(0.0, 0.0, 1.0, 1.0), 0.0)
    assert_equal(_atan2_derivative(0.0, 1.0, 1.0, 0.0), 1.0)
    assert_equal(_atan2_derivative(1.0, 0.0, 0.0, 1.0), -1.0)
    assert_true(isfinite(_atan2_derivative(2.0, 1.0, 1.0, 0.0)))
    assert_equal(_curve_atan2(1.0, inf[DType.float64]()), 0.0)
    assert_equal(_curve_atan2(inf[DType.float64](), 1.0), 1.5707963267948966)


def test_sinc_small_large_and_threshold_crossing_recipes() raises:
    assert_equal(_curve_sinc(0.0), 1.0)
    assert_equal(_sinc_derivative(0.0), 0.0)
    for value in [-2.0, -0.2, 0.2, 2.0]:
        assert_true(isfinite(_curve_sinc(value)))
        assert_true(isfinite(_sinc_derivative(value)))
    for domain in [
        _Interval(0.1, 0.2),
        _Interval(1.0, 1.1),
        _Interval(0.7, 0.9),
        _Interval(-0.9, -0.7),
    ]:
        var result = _sinc_jet(_Jet.variable(domain.low, domain.high))
        assert_true(result.rounded_value().contains(_curve_sinc(domain.low)))
        assert_true(result.rounded_value().contains(_curve_sinc(domain.high)))
    assert_false(_sinc_jet(_Jet.variable(0.7, 0.9)).first.is_finite())


def test_atan_nonfinite_axes_and_stationary_tangent_controls() raises:
    var infinity = inf[DType.float64]()
    var unknown = _atan_jet(_Jet.constant(infinity))
    assert_true(unknown.value.contains(-1.5707963267948966))
    assert_true(unknown.value.contains(1.5707963267948966))
    assert_false(unknown.first.is_finite())
    var finite = _Jet.constant(1.0)
    var nonfinite = _Jet.constant(infinity)
    var nonfinite_cases: List[Tuple[_Jet, _Jet]] = [
        (nonfinite, finite),
        (finite, nonfinite),
    ]
    for pair in nonfinite_cases:
        var result = _atan2_jet(pair[0], pair[1])
        assert_true(result.value.contains(-3.141592653589793))
        assert_true(result.value.contains(3.141592653589793))
    var stationary_cases: List[Tuple[_Jet, _Jet]] = [
        (_Jet.variable(-1.0, 1.0), _Jet.constant(0.0)),
        (_Jet.variable(0.5, 2.0), _Jet.variable(-1.0, 1.0)),
        (_Jet.variable(-1.0, 1.0), _Jet.variable(0.5, 2.0)),
    ]
    for pair in stationary_cases:
        var result = _atan2_jet(pair[0], pair[1])
        assert_true(result.value.contains(-3.141592653589793))
        assert_true(result.value.contains(3.141592653589793))
        assert_false(result.first.is_finite())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
