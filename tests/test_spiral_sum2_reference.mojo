# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The native Sum2 reference matches exact rationals and the checked bound.

The checked production function is called directly.
"""

from std.ffi import external_call
from std.math import inf, isfinite, nan
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true

from extensions.carla.curve_sum2 import _sum2_error_checked
from tests._spiral_sum2_reference import (
    _sum2_reference_add_upper,
    _sum2_reference_error,
)
from tools._bigint import BigInt
from tools._fraction import Fraction


comptime _INFINITY = UInt64(0x7FF0000000000000)


def _bits(value: Float64) -> UInt64:
    """Return the bits of a double.

    Args:
        value: The double.

    Returns:
        The 64 bits.
    """
    return bitcast[DType.uint64](value)


def _float(word: UInt64) -> Float64:
    """Return the double with these bits.

    Args:
        word: The 64 bits.

    Returns:
        The double.
    """
    return bitcast[DType.float64](word)


def _next_up(value: Float64) -> Float64:
    """Return the next double toward positive infinity.

    Args:
        value: The double.

    Returns:
        The successor toward positive infinity.
    """
    return external_call["nextafter", Float64](value, inf[DType.float64]())


def _power(exponent: Int) -> Float64:
    """Return `2**exponent` as a double.

    Args:
        exponent: The power of two, from -1074 through 1023.

    Returns:
        The double. Subnormal powers use the IEEE trailing bit.
    """
    if exponent > 1023:
        return inf[DType.float64]()
    if exponent < -1074:
        return 0.0
    if exponent >= -1022:
        return _float(UInt64(exponent + 1023) << 52)
    return _float(UInt64(1) << UInt64(exponent + 1074))


def _unit() raises -> Fraction:
    """Return the double unit roundoff, `2**-53`.

    Returns:
        The fraction.

    Raises:
        Error: If the power of two cannot be built.
    """
    return Fraction.of(BigInt(1), BigInt.power_of_two(53))


def _endpoint_add_high(one: Float64, two: Float64) -> Float64:
    """Return the high endpoint of two point intervals.

    Args:
        one: The first point.
        two: The second point.

    Returns:
        The outward high endpoint. Two zeros use positive zero.
    """
    if one == 0.0 and two == 0.0:
        return 0.0
    if one == 0.0:
        return two
    if two == 0.0:
        return one
    return _next_up(one + two)


def _magnitudes() -> List[Float64]:
    """Return the reviewed magnitude samples.

    Returns:
        Twelve finite samples, including both zeros.
    """
    var values = List[Float64]()
    values.append(0.0)
    values.append(_float(UInt64(1) << 63))
    values.append(_float(1))
    values.append(_float(2))
    values.append(_float(0x000FFFFFFFFFFFFF))
    values.append(_float(0x0010000000000000))
    values.append(_power(-400))
    values.append(1.0)
    values.append(_next_up(1.0))
    values.append(2.0)
    values.append(_power(400))
    values.append(_power(900))
    return values^


def _inherited() -> List[Float64]:
    """Return the reviewed inherited-error samples.

    Returns:
        Seven finite samples, including both zeros.
    """
    var values = List[Float64]()
    values.append(0.0)
    values.append(_float(UInt64(1) << 63))
    values.append(_float(1))
    values.append(_power(-100))
    values.append(_float(0x3D06849B86A12B9B))
    values.append(1.0)
    values.append(_power(1000))
    return values^


def _counts() -> List[Int]:
    """Return the reviewed term counts.

    Returns:
        Nine counts inside the supported range.
    """
    var values = List[Int]()
    values.append(1)
    values.append(2)
    values.append(3)
    values.append(7)
    values.append(10)
    values.append(100)
    values.append(320)
    values.append(65536)
    values.append(1073741824)
    return values^


def test_monotone_upper_matches_the_checked_bound() raises:
    """Each reviewed sample matches `_sum2_error_checked` bit for bit."""
    var counts = _counts()
    var magnitudes = _magnitudes()
    var inherited = _inherited()
    var cases = 0
    for count_index in range(len(counts)):
        var count = counts[count_index]
        for magnitude_index in range(len(magnitudes)):
            var magnitude = magnitudes[magnitude_index]
            for inherited_index in range(len(inherited)):
                var error = inherited[inherited_index]
                var reference = _sum2_reference_error(magnitude, error, count)
                var actual = _sum2_error_checked(magnitude, error, count)
                assert_equal(_bits(reference), _bits(actual))
                cases += 1
    assert_equal(cases, 756)


def test_every_upper_encloses_the_exact_rational_bound() raises:
    """Each reference upper bound is at least the exact rational majorant."""
    var unit = _unit()
    var cases = 0
    var exponent = -1074
    while exponent < 901:
        var magnitude = _power(exponent)
        var counts = List[Int]()
        counts.append(1)
        counts.append(2)
        counts.append(3)
        counts.append(10)
        counts.append(320)
        counts.append(1073741824)
        var errors = List[Float64]()
        errors.append(0.0)
        errors.append(_float(1))
        errors.append(_power(-53))
        errors.append(1.0)
        for count_index in range(len(counts)):
            var count = counts[count_index]
            var terms = Fraction(count - 1) * unit.copy()
            var gamma = terms.copy() / (Fraction(1) - terms.copy())
            for error_index in range(len(errors)):
                var error = errors[error_index]
                var result = _sum2_reference_error(magnitude, error, count)
                var exact = Fraction.from_float(error)
                if count != 1:
                    var factor = unit.copy() + gamma.copy() * gamma.copy()
                    exact = exact + factor * Fraction.from_float(magnitude)
                assert_true(Fraction.from_float(result) >= exact)
                cases += 1
        exponent += 17
    assert_equal(cases, 2808)


def test_guards_and_exact_boundary_words() raises:
    """Rejected inputs are positive infinity, and the boundaries stay exact."""
    var bad_magnitudes = List[Float64]()
    var bad_errors = List[Float64]()
    var bad_counts = List[Int]()
    bad_magnitudes.append(-1.0)
    bad_errors.append(0.0)
    bad_counts.append(2)
    bad_magnitudes.append(inf[DType.float64]())
    bad_errors.append(0.0)
    bad_counts.append(2)
    bad_magnitudes.append(-inf[DType.float64]())
    bad_errors.append(0.0)
    bad_counts.append(2)
    bad_magnitudes.append(nan[DType.float64]())
    bad_errors.append(0.0)
    bad_counts.append(2)
    bad_magnitudes.append(_next_up(_power(900)))
    bad_errors.append(0.0)
    bad_counts.append(2)
    bad_magnitudes.append(1.0)
    bad_errors.append(-1.0)
    bad_counts.append(2)
    bad_magnitudes.append(1.0)
    bad_errors.append(inf[DType.float64]())
    bad_counts.append(2)
    bad_magnitudes.append(1.0)
    bad_errors.append(nan[DType.float64]())
    bad_counts.append(2)
    bad_magnitudes.append(1.0)
    bad_errors.append(0.0)
    bad_counts.append(0)
    bad_magnitudes.append(1.0)
    bad_errors.append(0.0)
    bad_counts.append(-1)
    bad_magnitudes.append(1.0)
    bad_errors.append(0.0)
    bad_counts.append(1073741825)
    var index = 0
    while index < len(bad_counts):
        var magnitude = bad_magnitudes[index]
        var error = bad_errors[index]
        var count = bad_counts[index]
        var reference = _sum2_reference_error(magnitude, error, count)
        var actual = _sum2_error_checked(magnitude, error, count)
        assert_equal(_bits(reference), _INFINITY)
        assert_equal(_bits(actual), _INFINITY)
        index += 1
    assert_equal(_sum2_reference_error(0.0, 3.0, 2), 3.0)
    assert_equal(_sum2_reference_error(_float(UInt64(1) << 63), 3.0, 2), 3.0)
    assert_equal(_sum2_reference_error(1.0, 3.0, 1), 3.0)
    assert_true(isfinite(_sum2_reference_error(_power(900), 0.0, 1073741824)))


def test_upper_accumulation_preserves_signed_zero_contract() raises:
    """Point addition matches the outward high endpoint, including both zeros.
    """
    var samples = List[Float64]()
    samples.append(0.0)
    samples.append(_float(UInt64(1) << 63))
    samples.append(_float(1))
    samples.append(1.0)
    samples.append(inf[DType.float64]())
    for one_index in range(len(samples)):
        var one = samples[one_index]
        for two_index in range(len(samples)):
            var two = samples[two_index]
            var actual = _sum2_reference_add_upper(one, two)
            assert_equal(_bits(actual), _bits(_endpoint_add_high(one, two)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
