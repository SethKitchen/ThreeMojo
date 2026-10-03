# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact half-subnormal controls at the smallest normal power result."""

from extensions.carla.curve_interval import (
    _Interval,
    _power_product_bound,
    _power_quotient_bound,
)
from std.memory import bitcast
from std.testing import TestSuite, assert_true


def _check_half_ulp_enclosure(bound: _Interval, positive: Bool) raises:
    # The exact magnitude is 2^-1022 - 2^-1075, halfway between these
    # adjacent stored values. A singleton at the even upper endpoint fails.
    var below = bitcast[DType.float64](UInt64(0x000FFFFFFFFFFFFF))
    var normal = bitcast[DType.float64](UInt64(0x0010000000000000))
    if positive:
        assert_true(bound.low <= below)
        assert_true(bound.high >= normal)
    else:
        assert_true(bound.low <= -normal)
        assert_true(bound.high >= -below)


def test_signed_product_min_normal_boundary() raises:
    var original = bitcast[DType.float64](UInt64(0x001FFFFFFFFFFFFF))
    for i in range(2):
        var sign = Float64(2 * i - 1)
        var point = _Interval.point(sign * original)
        _check_half_ulp_enclosure(
            _power_product_bound(point, _Interval.point(0.5)), sign > 0.0
        )
        _check_half_ulp_enclosure(
            _power_product_bound(_Interval.point(0.5), point), sign > 0.0
        )
        _check_half_ulp_enclosure(
            _power_product_bound(point, _Interval.point(-0.5)), sign < 0.0
        )


def test_signed_quotient_min_normal_boundary() raises:
    var original = bitcast[DType.float64](UInt64(0x001FFFFFFFFFFFFF))
    for i in range(2):
        var sign = Float64(2 * i - 1)
        var point = _Interval.point(sign * original)
        _check_half_ulp_enclosure(
            _power_quotient_bound(point, _Interval.point(2.0)), sign > 0.0
        )
        _check_half_ulp_enclosure(
            _power_quotient_bound(point, _Interval.point(-2.0)), sign < 0.0
        )


def test_subnormal_power_min_normal_boundary() raises:
    var eta = bitcast[DType.float64](UInt64(1))
    var original = bitcast[DType.float64](UInt64(0x432FFFFFFFFFFFFF))
    for i in range(2):
        var sign = Float64(2 * i - 1)
        var point = _Interval.point(sign * original)
        _check_half_ulp_enclosure(
            _power_product_bound(point, _Interval.point(eta)), sign > 0.0
        )
        _check_half_ulp_enclosure(
            _power_product_bound(_Interval.point(-eta), point), sign < 0.0
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
