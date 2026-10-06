# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Affine binary64 decisions checked by an independent Fraction oracle."""

from math.exact_predicates import (
    _Dyadic,
    _fast_plane,
    _ordinary_range,
    _dyadic_normal_estimate,
    _absolute_plane_distance_compare,
    _collinear,
    _difference_compare,
    _line_distance_compare,
    _normal_estimate,
    _orient3d,
    _plane_above,
    _plane_distance_compare,
    _same_plane_absolute_distance_compare,
    _same_plane_distance_compare,
    _segment_distance_compare,
)
from math.scaled_products import _at_exponent
from std.math import sqrt
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from tests.exact_predicates_oracle import _oracle_cases

comptime _P = SIMD[DType.float64, 4]


def test_independent_fraction_oracle() raises:
    var cases = _oracle_cases()
    for index in range(len(cases)):
        ref c = cases[index]
        assert_equal(_orient3d(c.a, c.b, c.c, c.p), c.orientation)
        assert_equal(_plane_above(c.a, c.b, c.c, c.p, c.tolerance), c.above)
        assert_equal(
            _plane_distance_compare(c.a, c.b, c.c, c.p, c.d, c.e, c.f, c.q),
            c.signed_planes,
        )
        assert_equal(
            _absolute_plane_distance_compare(
                c.a, c.b, c.c, c.p, c.d, c.e, c.f, c.q
            ),
            c.absolute_planes,
        )
        assert_equal(
            _same_plane_distance_compare(c.a, c.b, c.c, c.p, c.q), c.same_signed
        )
        assert_equal(
            _same_plane_absolute_distance_compare(c.a, c.b, c.c, c.p, c.q),
            c.same_absolute,
        )
        assert_equal(_segment_distance_compare(c.a, c.b, c.p, c.q), c.segment)
        assert_equal(_line_distance_compare(c.a, c.b, c.p, c.q), c.line)
        assert_equal(
            _difference_compare(c.a[0], c.b[0], c.c[0], c.p[0]), c.difference
        )


def test_dyadic_arithmetic_and_exact_cancellation() raises:
    var tiny = bitcast[DType.float64](UInt64(1))
    var huge = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    var small = _Dyadic(tiny)
    var big = _Dyadic(huge)
    assert_equal(((big + small) - big - small).sign, 0)
    assert_equal(((big - small) - big + small).sign, 0)
    assert_equal(((big * small) - (small * big)).sign, 0)
    assert_equal((small - big).sign, -1)
    assert_equal((big - small).sign, 1)
    assert_equal((_Dyadic(-0.0) - _Dyadic(0)).sign, 0)
    assert_equal((_Dyadic(0) * big).sign, 0)
    assert_equal((big * _Dyadic(0)).sign, 0)
    assert_equal(small._compare_abs(_Dyadic(0)), 1)
    assert_equal(_Dyadic(0)._compare_abs(small), -1)
    assert_equal(_Dyadic(0)._compare_abs(_Dyadic(0)), 0)
    assert_equal(_difference_compare(1, 0, 1, tiny), 1)
    assert_equal(_difference_compare(1, tiny, 1, 0), -1)
    assert_equal(_difference_compare(1, 0, 1, 0), 0)


def test_exact_collinearity_and_scaled_normal() raises:
    var origin = _P(0, 0, 0, 0)
    assert_true(_collinear(origin, origin, origin))
    var zero = _normal_estimate(origin, origin, origin)
    for index in range(3):
        assert_equal(zero[index], 0)
    var tiny = bitcast[DType.float64](UInt64(1))
    var huge = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    for scale in [tiny, Float64(1), huge]:
        var a = _P(-scale, 0, 0, 0)
        var b = _P(scale, 0, 0, 0)
        assert_true(_collinear(a, b, origin))
        var c = _P(0, scale, 0, 0)
        assert_false(_collinear(a, b, c))
        var normal = _normal_estimate(a, b, c)
        assert_equal(normal[0], 0)
        assert_equal(normal[1], 0)
        assert_true(normal[2] > 0)
        assert_true(normal[2] <= 2)
        assert_equal(_orient3d(a, b, c, origin), 0)
        assert_false(_plane_above(a, b, c, origin, 0))
        assert_false(_plane_above(a, b, origin, c, 0))


def test_segment_endpoint_and_degenerate_ties() raises:
    var a = _P(0, 0, 0, 0)
    var b = _P(1, 0, 0, 0)
    assert_equal(_segment_distance_compare(a, b, _P(-1, 0, 0, 0), b), 1)
    assert_equal(_segment_distance_compare(a, b, _P(2, 0, 0, 0), a), 1)
    assert_equal(_segment_distance_compare(a, b, _P(0.5, 1, 0, 0), b), 1)
    assert_equal(_segment_distance_compare(a, b, a, b), 0)
    assert_equal(_segment_distance_compare(a, a, a, b), -1)


def test_distances_keep_bits_below_a_rounded_norm() raises:
    var a = _P(0, 0, 0, 0)
    var b = _P(1, 0, 0, 0)
    var c = _P(0, 1, 0, 0)
    var p = _P(0, 0, 1, 0)
    var tiny = bitcast[DType.float64](UInt64(1))
    var tilted = _P(0, 1, tiny, 0)
    # The second distance is 1/sqrt(1+tiny**2), strictly below one.
    # Both its rounded normal and every floating squared norm equal one.
    assert_equal(_plane_distance_compare(a, b, c, p, a, b, tilted, p), 1)
    assert_equal(
        _absolute_plane_distance_compare(a, b, c, p, a, b, tilted, p), 1
    )
    assert_true(_plane_above(a, b, c, p, 0))
    assert_false(_plane_above(a, b, c, p, 1))
    assert_false(_plane_above(a, b, tilted, p, 1))
    var u = _P(1, 1, 0, 0)
    var v = _P(1, 0, 1, 0)
    var first = _P(1, 0, 0, 0)
    var second = _P(1, tiny, 0, 0)
    assert_equal(_same_plane_distance_compare(a, u, v, first, second), 1)
    assert_equal(
        _same_plane_absolute_distance_compare(a, u, v, first, second), 1
    )


def test_degree_ten_capacity_covers_full_binary64_span() raises:
    var tiny = _Dyadic(bitcast[DType.float64](UInt64(1)))
    var huge = _Dyadic(bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF)))
    var sum = huge + tiny
    var difference = huge - tiny
    var left = _Dyadic(1)
    var right = _Dyadic(1)
    for _ in range(5):
        left = left * sum
        right = right * difference
    var factorized = (left - right) * (left + right)
    var expanded = left * left - right * right
    assert_equal((factorized - expanded).sign, 0)
    assert_true(expanded.sign > 0)
    assert_true(expanded.count < 672)


def test_normal_estimate_keeps_a_full_significand() raises:
    # A top radix word of one formerly retained only 33 leading bits.
    # Keep the next word before conversion, even after heavy cancellation.
    var value = _Dyadic(1)
    value.words[0] = UInt32(0xFEDCBA98)
    value.words[1] = UInt32(0x76543210)
    value.words[2] = UInt32(1)
    value.count = 3
    value.exponent = -64
    var estimate = _at_exponent(value._estimate(), 0)
    assert_equal(estimate, Float64(1.462222222470575))


def test_ordinary_filter_guards_and_uncertain_boundaries() raises:
    var lower = bitcast[DType.float64](UInt64(0x39B0000000000000))
    var upper = bitcast[DType.float64](UInt64(0x4630000000000000))
    assert_true(_ordinary_range(_P(lower, -upper, 0, 0)))
    assert_false(
        _ordinary_range(
            _P(bitcast[DType.float64](UInt64(0x39AFFFFFFFFFFFFF)), 0, 0, 0)
        )
    )
    assert_false(
        _ordinary_range(
            _P(bitcast[DType.float64](UInt64(0x4630000000000001)), 0, 0, 0)
        )
    )
    var a = _P(0, 0, 0, 0)
    var b = _P(1, 1, 0, 0)
    var c = _P(1, 0, 1, 0)
    # At 32*u*permanent, the conservative filter must stay uncertain.
    assert_equal(_fast_plane(a, b, c, _P(2.0000000000000142, 1, 1, 0), 0), 0)
    assert_equal(_fast_plane(a, b, c, _P(2.0000000000001137, 1, 1, 0), 0), 1)
    assert_equal(_fast_plane(a, b, c, _P(1.9999999999998863, 1, 1, 0), 0), -1)
    # A nearest stored tolerance for 1/sqrt(3) needs the exact fallback.
    assert_equal(_fast_plane(a, b, c, _P(1, 0, 0, 0), 0.5773502691896258), 0)


def _check_normal_direction(a: _P, b: _P, c: _P) raises:
    var reference = _dyadic_normal_estimate(a, b, c)
    var candidate = _normal_estimate(a, b, c)
    var reference_length = sqrt(
        reference[0] * reference[0]
        + reference[1] * reference[1]
        + reference[2] * reference[2]
    )
    var candidate_length = sqrt(
        candidate[0] * candidate[0]
        + candidate[1] * candidate[1]
        + candidate[2] * candidate[2]
    )
    assert_equal(reference_length == 0, candidate_length == 0)
    if reference_length != 0:
        for axis in range(3):
            assert_true(
                abs(
                    reference[axis] / reference_length
                    - candidate[axis] / candidate_length
                )
                <= Float64(1.4210854715202004e-14)
            )


def test_certified_normal_direction_matches_exact_fallback() raises:
    var cases = _oracle_cases()
    for c in cases:
        _check_normal_direction(c.a, c.b, c.c)
        _check_normal_direction(c.d, c.e, c.f)
    var a = _P(0, 0, 0, 0)
    var b = _P(1, 1, 0, 0)
    var c = _P(1, 1.0000000000000002, 0, 0)
    _check_normal_direction(a, b, c)
    _check_normal_direction(a, b, _P(2, 2, 0, 0))
    _check_normal_direction(
        _P(1e16, 1e16, 1e16, 0),
        _P(1e16, 1e16 + 2, 1e16, 0),
        _P(1e16, 1e16, 1e16 + 2, 0),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
