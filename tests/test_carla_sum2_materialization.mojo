# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Portable CPU checks of Sum2 materialization and gradual underflow.

These controls call the actual non-inlined production helper. They must run
on each supported CPU target; an x86 assembly review does not qualify ARM.
"""

from extensions.carla.curve_sum2 import _sum2_update, _sum2_error
from extensions.carla.curve_interval import _next_up
from std.math import fma, inf, isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


@no_inline
def _materialized_product(a: Float64, b: Float64) -> Tuple[Float64, Float64]:
    # The product must round before entering the production helper.
    return _sum2_update(-1.0, 0.0, a * b)


def test_sum2_materializes_product_before_residual_recovery() raises:
    var a = bitcast[DType.float64](UInt64(0x3FF0000002000000))
    var b = bitcast[DType.float64](UInt64(0x3FEFFFFFFC000000))
    var result = _materialized_product(a, b)
    assert_equal(bitcast[DType.uint64](result[0]), UInt64(0))
    assert_equal(bitcast[DType.uint64](result[1]), UInt64(0))
    assert_equal(fma(a, b, -1.0), -5.551115123125783e-17)


def test_sum2_recovers_smallest_subnormal_residual() raises:
    var eta = bitcast[DType.float64](UInt64(1))
    var normal = bitcast[DType.float64](UInt64(1) << UInt64(52))
    for seed in [normal, 1.0]:
        var total = 0.0
        var correction = 0.0
        for term in [seed, eta, -seed]:
            var result = _sum2_update(total, correction, term)
            total = result[0]
            correction = result[1]
        # seed=1 forces eta into the exact residual and correction path.
        assert_equal(bitcast[DType.uint64](total + correction), UInt64(1))
    for term in [eta, -eta]:
        var result = _sum2_update(0.0, 0.0, term)
        assert_equal(
            bitcast[DType.uint64](result[0] + result[1]),
            bitcast[DType.uint64](term),
        )


def test_sum2_uses_nearest_even_rounding() raises:
    var half_ulp = bitcast[DType.float64](UInt64(0x3CA0000000000000))
    var even = _sum2_update(1.0, 0.0, half_ulp)
    assert_equal(bitcast[DType.uint64](even[0]), UInt64(0x3FF0000000000000))
    var odd = bitcast[DType.float64](UInt64(0x3FF0000000000001))
    var rounded = _sum2_update(odd, 0.0, half_ulp)
    assert_equal(bitcast[DType.uint64](rounded[0]), UInt64(0x3FF0000000000002))


def test_sum2_preserves_zero_initialization_and_cancellation() raises:
    for term in [0.0, -0.0]:
        var result = _sum2_update(0.0, 0.0, term)
        assert_equal(bitcast[DType.uint64](result[0] + result[1]), UInt64(0))
    var total = 0.0
    var correction = 0.0
    for term in [1e100, 1.0, -1e100]:
        var result = _sum2_update(total, correction, term)
        total = result[0]
        correction = result[1]
    assert_equal(total + correction, 1.0)


def test_sum2_bound_retains_inherited_error_and_range_guards() raises:
    assert_equal(_sum2_error(1.0, 1e-15, 1), 1e-15)
    assert_equal(_sum2_error(0.0, 1e-15, 100), 1e-15)
    var limit = bitcast[DType.float64](UInt64(1923) << UInt64(52))
    assert_true(isfinite(_sum2_error(limit, 0.0, 1073741824)))
    assert_true(not isfinite(_sum2_error(_next_up(limit), 0.0, 100)))
    for count in [0, -1, 1073741825]:
        assert_true(not isfinite(_sum2_error(1.0, 0.0, count)))
    assert_true(not isfinite(_sum2_error(inf[DType.float64](), 0.0, 100)))
    assert_true(not isfinite(_sum2_error(-1.0, 0.0, 100)))
    assert_true(not isfinite(_sum2_error(1.0, -1.0, 100)))
    assert_true(not isfinite(_sum2_error(1.0, inf[DType.float64](), 100)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
