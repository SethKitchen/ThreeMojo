# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Additive direct witnesses for the exact first interval/trig capture gaps.

This does not replace or shorten the original SPIRAL value-only suite. Its
failed interval-instrumented stream must remain excluded from coverage.
"""

from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _ValueJet,
    _directed_endpoint_sum,
    _tight_square_bound,
    _without_derivatives,
)
from extensions.carla.curve_trig import (
    _curve_sincos,
    _sincos_branch,
    _sincos_derivative,
)
from std.math import inf, isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def _same_interval_bits(actual: _Interval, expected: _Interval) raises:
    assert_equal(
        bitcast[DType.uint64](actual.low), bitcast[DType.uint64](expected.low)
    )
    assert_equal(
        bitcast[DType.uint64](actual.high), bitcast[DType.uint64](expected.high)
    )


def _same_value_error(actual: _ValueJet, expected: _Jet) raises:
    _same_interval_bits(actual.value, expected.value)
    assert_equal(
        bitcast[DType.uint64](actual.error),
        bitcast[DType.uint64](expected.error),
    )
    _same_interval_bits(actual.rounded_value(), expected.rounded_value())
    _same_interval_bits(actual.first, _Interval.whole())
    _same_interval_bits(actual.second, _Interval.whole())


def _arithmetic_pair(one: _Jet, two: _Jet) raises:
    var a = _without_derivatives(one)
    var b = _without_derivatives(two)
    _same_value_error(a, one)
    _same_value_error(b, two)
    _same_value_error(-a, -one)
    _same_value_error(a + b, one + two)
    _same_value_error(a - b, one - two)
    _same_value_error(a * b, one * two)
    _same_value_error(a / b, one / two)


def test_second_operand_sum_fallback_and_tight_square_domains() raises:
    # First exact-range predicate true, second false: missing condition 1
    # at curve_interval:241. The finite fallback must still enclose the sum.
    var fallback = _directed_endpoint_sum(1.0, 1e308)
    assert_true(fallback.contains(1e308))
    assert_true(_directed_endpoint_sum(1.0, 2.0).is_point(3.0))
    var crossing = _tight_square_bound(_Interval(-2.0, 3.0))
    assert_equal(crossing.low, 0.0)
    assert_true(crossing.contains(9.0))
    var positive = _tight_square_bound(_Interval(2.0, 3.0))
    assert_equal(positive.low, 4.0)
    assert_equal(positive.high, 9.0)
    var negative = _tight_square_bound(_Interval(-3.0, -2.0))
    assert_equal(negative.low, 4.0)
    assert_equal(negative.high, 9.0)


def test_value_only_constructor_conversion_and_negation_fields() raises:
    _same_value_error(_ValueJet.constant(1.25), _Jet.constant(1.25))
    _same_value_error(_ValueJet.variable(-2.0, 3.0), _Jet.variable(-2.0, 3.0))
    var full = _Jet.variable(-2.0, 3.0)
    full.error = 0.125
    var light = _without_derivatives(full)
    _same_value_error(light, full)
    _same_value_error(-light, -full)
    assert_equal(light.error, 0.125)
    assert_equal(light.value.low, -2.0)
    assert_equal(light.value.high, 3.0)


def test_zero_and_unit_shortcuts_require_zero_error_and_finite_partner() raises:
    var zero = _Jet.constant(0.0)
    var two = _Jet.constant(2.0)
    var one = _Jet.constant(1.0)
    var uncertain_zero = _Jet.constant(0.0)
    uncertain_zero.error = 0.125
    var uncertain_one = _Jet.constant(1.0)
    uncertain_one.error = 0.125
    var unbounded = _Jet.constant(inf[DType.float64]())
    var cases: List[Tuple[_Jet, _Jet]] = [
        (zero, two),
        (uncertain_zero, two),
        (two, uncertain_zero),
        (uncertain_zero, zero),
        (two, zero),
        (one, two),
        (two, one),
        (uncertain_one, two),
        (two, uncertain_one),
        (zero, unbounded),
        (unbounded, zero),
        (two, two),
    ]
    for pair in cases:
        _arithmetic_pair(pair[0], pair[1])
    # The right-zero addition shortcut must retain left-side error even
    # when both ideal values are zero (curve_interval:407-408).
    var retained = uncertain_zero + zero
    assert_equal(retained.error, 0.125)
    assert_equal(
        bitcast[DType.uint64](retained.value.low), UInt64(0x8000000000000000)
    )
    assert_equal(bitcast[DType.uint64](retained.value.high), UInt64(0))
    assert_true((uncertain_zero + two).error >= 0.125)
    assert_true((two + uncertain_zero).error >= 0.125)
    assert_true((uncertain_zero * two).error >= 0.25)
    assert_true((two * uncertain_zero).error >= 0.25)
    assert_true((uncertain_one * two).error >= 0.25)
    assert_true((two * uncertain_one).error >= 0.25)
    assert_false(isfinite((zero * unbounded).error))
    assert_false(isfinite((unbounded * zero).error))


def test_sincos_derivative_mode_two_and_full_jet_branch_wrapper() raises:
    # floor(pi * INV_HALF_PI + 0.5) is 2. Earlier direct phase controls
    # covered modes 0, 1 and 3 but missed this derivative return.
    var derivative = _sincos_derivative(3.141592653589793)
    assert_true(derivative[0] < -0.999999999999)
    assert_true(abs(derivative[1]) < 1e-14)
    var bounded = _sincos_branch(_Jet.variable(3.0, 3.1), 2)
    assert_true(bounded[0].first.is_finite())
    assert_true(bounded[1].second.is_finite())
    for angle in [3.0, 3.1]:
        var scalar = _curve_sincos(angle)
        assert_true(bounded[0].rounded_value().contains(scalar[0]))
        assert_true(bounded[1].rounded_value().contains(scalar[1]))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
