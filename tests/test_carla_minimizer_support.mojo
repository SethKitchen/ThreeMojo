# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Rounded-minimizer support controls; scalar errors may attain both signs."""
from extensions.carla.curve_interval import _Interval, _Jet, _next_up
from extensions.carla.curve_minimizer_support import _minimizer_support
from std.math import inf, sqrt
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


def test_monotone_cutoff_retains_the_worst_error_tie() raises:
    var domain = _Jet(
        _Interval(0, 1), _Interval.point(1.0), _Interval.point(0.0), 0.01
    )
    var center = _Jet(
        _Interval.point(0.0),
        _Interval.point(1.0),
        _Interval.point(0.0),
        inf[DType.float64](),
    )
    var support = _minimizer_support(domain, center, 0.0, 0.0, 0.0, 1.0)
    assert_equal(support.low, 0.0)
    assert_true(support.contains(0.02))
    assert_true(support.high < 0.03)
    domain.first = _Interval.point(-2.0)
    domain.value = _Interval(-20, 0)
    domain.error = 0.1
    center.first = _Interval.point(-2.0)
    support = _minimizer_support(domain, center, 10.0, 10.0, 0.0, 10.0)
    assert_true(support.contains(9.9))
    assert_equal(support.high, 10.0)
    assert_true(support.low > 9.8)


def test_convex_nonstationary_incumbent_keeps_both_roots() raises:
    var domain = _Jet(
        _Interval(0, 4), _Interval(-4, 4), _Interval.point(2.0), 0.125
    )
    var center = _Jet(
        _Interval.point(0.25),
        _Interval.point(1.0),
        _Interval.point(2.0),
        inf[DType.float64](),
    )
    var support = _minimizer_support(domain, center, 0.5, 0.5, -2.0, 2.0)
    var radius = sqrt(0.5)
    assert_true(support.contains(-radius))
    assert_true(support.contains(radius))
    assert_true(support.low > -0.71 and support.high < 0.71)
    for i in range(4001):
        var s = -2.0 + Float64(i) / 1000.0
        # Worst actual errors: -E at s, +E at the incumbent.
        if s * s - 0.125 <= 0.25 + 0.125:
            assert_true(support.contains(s))
    center.error = 0.0
    var without_sentinel = _minimizer_support(
        domain, center, 0.5, 0.5, -2.0, 2.0
    )
    assert_equal(without_sentinel.low, support.low)
    assert_equal(without_sentinel.high, support.high)


def test_outside_witness_or_unknown_error_does_not_trim() raises:
    var domain = _Jet(
        _Interval(0, 1), _Interval.point(1.0), _Interval.point(0.0), 0.0
    )
    var center = _Jet.constant(0.0)
    var support = _minimizer_support(domain, center, 0.0, 2.0, 0.0, 1.0)
    assert_equal(support.low, 0.0)
    assert_equal(support.high, 1.0)
    domain.error = inf[DType.float64]()
    support = _minimizer_support(domain, center, 0.0, 0.0, 0.0, 1.0)
    assert_equal(support.high, 1.0)
    domain.error = -1.0
    support = _minimizer_support(domain, center, 0.0, 0.0, 0.0, 1.0)
    assert_equal(support.high, 1.0)


def test_zero_error_keeps_exact_stationary_minimum() raises:
    var domain = _Jet(
        _Interval(0, 1), _Interval(-2, 2), _Interval.point(2.0), 0.0
    )
    var center = _Jet(
        _Interval.point(0.0),
        _Interval.point(0.0),
        _Interval.point(2.0),
        inf[DType.float64](),
    )
    var support = _minimizer_support(domain, center, 0.0, 0.0, -1.0, 1.0)
    assert_equal(support.low, 0.0)
    assert_equal(support.high, 0.0)


def test_subnormal_radius_keeps_outward_station_boundary() raises:
    var eta = bitcast[DType.float64](UInt64(1))
    var right = _next_up(1.0)
    var domain = _Jet(
        _Interval(1.0, right), _Interval.point(1.0), _Interval.point(0.0), eta
    )
    var center = _Jet(
        _Interval.point(1.0),
        _Interval.point(1.0),
        _Interval.point(0.0),
        inf[DType.float64](),
    )
    var support = _minimizer_support(domain, center, 1.0, 1.0, 1.0, right)
    assert_true(support.contains(1.0))
    assert_true(support.contains(right))
    assert_true(support.high <= right)


def test_nonfinite_convex_discriminant_keeps_original_cell() raises:
    var domain = _Jet(
        _Interval(0, 1e300),
        _Interval(-1e300, 1e300),
        _Interval.point(1e300),
        1e300,
    )
    var center = _Jet(
        _Interval.point(0.0),
        _Interval.point(0.0),
        _Interval.point(1e300),
        inf[DType.float64](),
    )
    var support = _minimizer_support(domain, center, 0.0, 0.0, -1.0, 1.0)
    assert_equal(support.low, -1.0)
    assert_equal(support.high, 1.0)


def test_inconsistent_or_unknown_derivatives_do_not_trim() raises:
    var domain = _Jet(
        _Interval(0, 1), _Interval.point(1.0), _Interval.point(0.0), 0.0
    )
    var center = _Jet(
        _Interval.point(0.0),
        _Interval.point(-1.0),
        _Interval.point(0.0),
        inf[DType.float64](),
    )
    var support = _minimizer_support(domain, center, 0.0, 0.0, 0.0, 1.0)
    assert_equal(support.low, 0.0)
    assert_equal(support.high, 1.0)
    domain.first = _Interval.whole()
    domain.second = _Interval.whole()
    support = _minimizer_support(domain, center, 0.0, 0.0, 0.0, 1.0)
    assert_equal(support.low, 0.0)
    assert_equal(support.high, 1.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
