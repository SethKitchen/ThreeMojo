# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact stored half-scaling with full-domain and inherited-error guards."""

from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _stored_half,
    _without_derivatives,
    _next_down,
    _next_up,
)
from std.math import inf, isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


@no_inline
def _scalar_half(value: Float64) -> Float64:
    return value * 0.5


def test_stored_half_matches_exact_binary_exponent_shift() raises:
    for exponent in [-400, -300, -1, 0, 1, 300, 399, 400]:
        var word = UInt64(exponent + 1023) << UInt64(52)
        for sign in [UInt64(0), UInt64(1) << UInt64(63)]:
            var operand = bitcast[DType.float64](word | sign)
            var expected = (word - (UInt64(1) << UInt64(52))) | sign
            assert_equal(bitcast[DType.uint64](_scalar_half(operand)), expected)
            var jet = _Jet.variable(operand, operand)
            var result = _stored_half(jet)
            var ordinary = jet * _Jet.constant(0.5)
            assert_equal(result.error, 0.0)
            assert_equal(result.value.low, ordinary.value.low)
            assert_equal(result.value.high, ordinary.value.high)
            assert_equal(result.first.low, ordinary.first.low)
            assert_equal(result.first.high, ordinary.first.high)
            assert_equal(result.second.low, ordinary.second.low)
            assert_equal(result.second.high, ordinary.second.high)
            var value = _stored_half(_without_derivatives(jet))
            assert_equal(value.error, result.error)
            assert_equal(value.value.low, result.value.low)
            assert_equal(value.value.high, result.value.high)


def test_stored_half_retains_scaled_inherited_error() raises:
    for sign in [-1.0, 1.0]:
        var jet = _Jet.variable(1.25 * sign, 1.25 * sign)
        jet.error = 1e-12
        var result = _stored_half(jet)
        var expected = (_Interval.point(jet.error) * _Interval.point(0.5)).high
        assert_equal(result.error, expected)
        assert_true(result.error >= jet.error * 0.5)
        assert_true(result.error < (jet * _Jet.constant(0.5)).error)
        assert_equal(
            _stored_half(_without_derivatives(jet)).error, result.error
        )


def test_stored_half_checks_entire_range_and_has_safe_fallback() raises:
    var low = bitcast[DType.float64](UInt64(623) << UInt64(52))
    var high = bitcast[DType.float64](UInt64(1423) << UInt64(52))
    for a, b in [
        (-1.0, 1.0),
        (0.0, 1.0),
        (_next_down(low), 1.0),
        (1.0, _next_up(high)),
        (bitcast[DType.float64](UInt64(1)), bitcast[DType.float64](UInt64(1))),
    ]:
        var jet = _Jet.variable(a, b)
        assert_equal(_stored_half(jet).error, (jet * _Jet.constant(0.5)).error)
    assert_equal(_stored_half(_Jet.constant(0.0)).error, 0.0)
    var unknown = _Jet(
        _Interval.whole(),
        _Interval.whole(),
        _Interval.whole(),
        inf[DType.float64](),
    )
    assert_true(not isfinite(_stored_half(unknown).error))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
