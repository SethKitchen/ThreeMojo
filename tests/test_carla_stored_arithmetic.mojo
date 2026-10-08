# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent arithmetic controls for stored subtraction and sample blending.

Literal output words and upward exact-error fixtures were derived with Python
Fraction. They cover the separate graph and both permitted final FMA graphs.
This suite does not use ideal trigonometry to validate canonical arithmetic.
"""

from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _ValueJet,
    _stored_difference,
    _stored_blend_error,
    _without_derivatives,
    _next_up,
    _next_down,
)
from extensions.carla.lane_distance import (
    _normalized_square,
    _refinement_square,
)
from std.math import fma, inf, isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


@no_inline
def _product(a: Float64, b: Float64) -> Float64:
    return a * b


@no_inline
def _sum(a: Float64, b: Float64) -> Float64:
    return a + b


@no_inline
def _complement(rate: Float64) -> Float64:
    return 1.0 - rate


def _blend_fixture(
    ideal_rate: Float64,
    actual_rate: Float64,
    inherited: Float64,
    one: Float64,
    two: Float64,
    required_error: Float64,
    separate_word: UInt64,
    left_fma_word: UInt64,
    right_fma_word: UInt64,
) raises:
    var rate = _Jet.variable(ideal_rate, ideal_rate)
    rate.error = inherited
    var error = _stored_blend_error(rate, one, two)
    var value_error = _stored_blend_error(_without_derivatives(rate), one, two)
    assert_true(isfinite(error))
    assert_true(error >= required_error)
    assert_equal(error, value_error)
    var complement = _complement(actual_rate)
    var first = _product(actual_rate, one)
    var second = _product(complement, two)
    assert_equal(bitcast[DType.uint64](_sum(first, second)), separate_word)
    assert_equal(
        bitcast[DType.uint64](fma(actual_rate, one, second)), left_fma_word
    )
    assert_equal(
        bitcast[DType.uint64](fma(complement, two, first)), right_fma_word
    )


def test_stored_blend_covers_exact_rational_fma_fixtures() raises:
    _blend_fixture(
        0.3,
        0.3000000000000001,
        2.220446049250313e-16,
        8.7,
        9.0,
        3.519406988061746e-16,
        UInt64(0x4021D1EB851EB852),
        UInt64(0x4021D1EB851EB852),
        UInt64(0x4021D1EB851EB852),
    )
    _blend_fixture(
        0.1,
        0.10000000000000003,
        5.551115123125783e-17,
        9.0,
        9.0,
        0.0,
        UInt64(0x4022000000000000),
        UInt64(0x4022000000000000),
        UInt64(0x4022000000000000),
    )
    _blend_fixture(
        0.9,
        0.9000000000000002,
        4.440892098500626e-16,
        -8.7,
        -9.0,
        1.0724754417879012e-15,
        UInt64(0xC02175C28F5C28F6),
        UInt64(0xC02175C28F5C28F5),
        UInt64(0xC02175C28F5C28F6),
    )
    _blend_fixture(
        0.2,
        0.20000000000000007,
        1.1102230246251565e-16,
        8.7,
        -9.0,
        8.693046282814976e-16,
        UInt64(0xC015D70A3D70A3D6),
        UInt64(0xC015D70A3D70A3D6),
        UInt64(0xC015D70A3D70A3D6),
    )
    _blend_fixture(
        0.8,
        0.8000000000000003,
        4.440892098500626e-16,
        -8.7,
        9.0,
        4.3653969328261155e-15,
        UInt64(0xC014A3D70A3D70A8),
        UInt64(0xC014A3D70A3D70A9),
        UInt64(0xC014A3D70A3D70A8),
    )
    _blend_fixture(
        -0.25,
        -0.24999999999999994,
        2.220446049250313e-16,
        8.7,
        9.0,
        8.881784197001252e-16,
        UInt64(0x4022266666666667),
        UInt64(0x4022266666666667),
        UInt64(0x4022266666666667),
    )
    _blend_fixture(
        1.25,
        1.2500000000000004,
        8.881784197001252e-16,
        -8.7,
        9.0,
        7.993605777301127e-15,
        UInt64(0xC02A400000000004),
        UInt64(0xC02A400000000004),
        UInt64(0xC02A400000000004),
    )
    _blend_fixture(
        3.0,
        3.000000000000001,
        1.7763568394002505e-15,
        1e30,
        -1e30,
        1970324836974592.0,
        UInt64(0x464F8DEF8808B028),
        UInt64(0x464F8DEF8808B028),
        UInt64(0x464F8DEF8808B028),
    )
    _blend_fixture(
        0.75,
        0.7500000000000002,
        4.440892098500626e-16,
        1e-30,
        2e-30,
        1.7516230804060213e-46,
        UInt64(0x39B95A5EFEA6B347),
        UInt64(0x39B95A5EFEA6B347),
        UInt64(0x39B95A5EFEA6B347),
    )
    _blend_fixture(
        0.5,
        0.5000000000000002,
        4.440892098500626e-16,
        0.0,
        9.0,
        1.7763568394002505e-15,
        UInt64(0x4011FFFFFFFFFFFE),
        UInt64(0x4011FFFFFFFFFFFE),
        UInt64(0x4011FFFFFFFFFFFE),
    )
    _blend_fixture(
        0.5,
        0.5000000000000002,
        4.440892098500626e-16,
        9.0,
        0.0,
        1.7763568394002505e-15,
        UInt64(0x4012000000000002),
        UInt64(0x4012000000000002),
        UInt64(0x4012000000000002),
    )


def test_stored_difference_checks_every_domain_endpoint() raises:
    for low, high in [(0.5, 0.5), (2.0, 2.0), (0.5, 2.0)]:
        var one = _Jet.variable(low, high)
        var two = _Jet.constant(1.0)
        var ordinary = one - two
        var exact = _stored_difference(one, two)
        assert_equal(exact.error, 0.0)
        assert_equal(exact.value.low, ordinary.value.low)
        assert_equal(exact.value.high, ordinary.value.high)
        assert_equal(exact.first.low, ordinary.first.low)
        assert_equal(exact.first.high, ordinary.first.high)
        assert_equal(exact.second.low, ordinary.second.low)
        assert_equal(exact.second.high, ordinary.second.high)
        var value = _stored_difference(
            _without_derivatives(one), _without_derivatives(two)
        )
        assert_equal(value.error, exact.error)
        assert_equal(value.value.low, exact.value.low)
        assert_equal(value.value.high, exact.value.high)
    for low, high in [
        (_next_down(0.5), 1.5),
        (1.0, _next_up(2.0)),
        (-1.0, -0.5),
    ]:
        var one = _Jet.variable(low, high)
        var two = _Jet.constant(1.0)
        assert_equal(_stored_difference(one, two).error, (one - two).error)


def test_stored_difference_retains_prior_error() raises:
    var one = _Jet.variable(1.25, 1.5)
    var two = _Jet.constant(1.0)
    one.error = 1e-14
    two.error = 2e-14
    var exact = _stored_difference(one, two)
    assert_true(exact.error >= one.error + two.error)
    assert_true(exact.error <= _next_up(one.error + two.error))
    assert_true(exact.error < (one - two).error)
    var value = _stored_difference(
        _without_derivatives(one), _without_derivatives(two)
    )
    assert_equal(value.error, exact.error)


def test_stored_difference_safe_range_edges_and_fallback() raises:
    var low = bitcast[DType.float64](UInt64(623) << UInt64(52))
    var high = bitcast[DType.float64](UInt64(1423) << UInt64(52))
    for value in [low, high]:
        var point = _Jet.constant(value)
        assert_equal(_stored_difference(point, point).error, 0.0)
    for value in [
        _next_down(low),
        _next_up(high),
        bitcast[DType.float64](UInt64(1)),
    ]:
        var point = _Jet.constant(value)
        var ordinary = point - point
        assert_equal(_stored_difference(point, point).error, ordinary.error)
        assert_true(ordinary.error > 0.0)
    var unknown = _Jet(
        _Interval.whole(),
        _Interval.whole(),
        _Interval.whole(),
        inf[DType.float64](),
    )
    assert_true(
        not isfinite(_stored_difference(unknown, _Jet.constant(1.0)).error)
    )


def test_stored_blend_equal_values_keep_rounding_error() raises:
    var rate = _Jet.variable(0.3, 0.3)
    rate.error = 1e-12
    var equal_error = _stored_blend_error(rate, 9.0, 9.0)
    assert_true(isfinite(equal_error) and equal_error > 0.0)
    var coupled = _stored_blend_error(rate, 8.7, 9.0)
    # Shared-rate cancellation is the reason to add this bound. Merely
    # increasing tolerance or keeping |a|+|b| would fail this control.
    assert_true(coupled < (8.7 + 9.0) * rate.error / 50.0)


def test_stored_blend_refuses_unsupported_inputs() raises:
    var tiny = bitcast[DType.float64](UInt64(1))
    for value in [tiny, 1e-300, 1e200]:
        assert_true(
            not isfinite(_stored_blend_error(_Jet.constant(value), 1.0, 1.0))
        )
    var rate = _Jet.variable(0.3, 0.3)
    assert_true(not isfinite(_stored_blend_error(rate, 1e308, -1e308)))
    assert_true(not isfinite(_stored_blend_error(rate, 1e-300, 1.0)))
    assert_true(
        not isfinite(_stored_blend_error(rate, inf[DType.float64](), 1.0))
    )
    rate.error = -1.0
    assert_true(not isfinite(_stored_blend_error(rate, 1.0, 2.0)))
    rate.error = inf[DType.float64]()
    assert_true(not isfinite(_stored_blend_error(rate, 1.0, 2.0)))
    var reversed = _Jet.variable(2.0, 1.0)
    assert_true(not isfinite(_stored_blend_error(reversed, 1.0, 2.0)))


def test_refinement_distance_preserves_accuracy_lower_endpoint() raises:
    # Upward exact Fraction values for the stored point/query words.
    for scale, required_upper in [
        (0.5, 30.318254544649832),
        (1.0, 7.579563636162458),
        (2.0, 1.8948909090406145),
        (16.0, 0.029607670453759602),
    ]:
        var point: Array[Float64, 3] = [
            52.48327152950449,
            -124.37542572135717,
            2.2733014773624762,
        ]
        var query: Array[Float64, 3] = [51.20000076293945, -125.25, 0.0]
        var old = _normalized_square[3](point, query, scale)
        var refined = _refinement_square[3](point, query, scale)
        assert_equal(refined.low, old.low)
        assert_true(refined.high <= old.high)
        assert_true(refined.high >= refined.low)
        assert_true(refined.high >= required_upper)


def test_broad_blend_rate_covers_interior_gradual_underflow() raises:
    var eta = bitcast[DType.float64](UInt64(1))
    var coefficient = bitcast[DType.float64](UInt64(623) << UInt64(52))
    # The exact product eta*2^-400 is positive and below eta/2; each
    # permitted final contraction rounds to zero. Its absolute error is
    # below eta, which remains inside the broad-domain error bound.
    for low, high in [(0.0, 1.0), (-1.0, 1.0)]:
        var rate = _Jet.variable(low, high)
        var error = _stored_blend_error(rate, coefficient, 0.0)
        assert_true(isfinite(error) and error >= eta)
        var value_error = _stored_blend_error(
            _without_derivatives(rate), coefficient, 0.0
        )
        assert_equal(value_error, error)
        assert_equal(eta * coefficient, 0.0)
        assert_equal(fma(eta, coefficient, 0.0), 0.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
