# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Stored spiral-moment words use exact even rounding."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._spiral_moment_words import (
    INFINITY,
    MAX_FINITE,
    SIGN,
    bracket,
    decimal_word,
    fraction_of_word,
    nearest_even,
    verify_bracket,
)


def test_stored_words_round_trip() raises:
    """Each finite word is its own tight bracket."""
    var words = List[UInt64]()
    words.append(0)
    words.append(1)
    words.append((UInt64(1) << 52) - 1)
    words.append(UInt64(1) << 52)
    words.append(0x3FEFFFFFFFFFFFFF)
    words.append(0x3FF0000000000000)
    words.append(0x3FF0000000000001)
    words.append(MAX_FINITE)
    for word in words:
        for sign in range(2):
            var signed = word
            if sign == 1:
                signed = word | SIGN
            var value = fraction_of_word(signed)
            var pair = bracket(value)
            if value.is_zero():
                assert_equal(pair[0], SIGN)
                assert_equal(pair[1], UInt64(0))
            else:
                assert_equal(pair[0], signed)
                assert_equal(pair[1], signed)


def test_halfway_rounding_is_even() raises:
    """A halfway value keeps the even encoding."""
    var lows = List[UInt64]()
    lows.append(0)
    lows.append(1)
    lows.append((UInt64(1) << 52) - 1)
    lows.append(UInt64(1) << 52)
    lows.append(0x3FEFFFFFFFFFFFFF)
    lows.append(0x3FF0000000000000)
    lows.append(0x3FF0000000000001)
    for low in lows:
        var mid = (
            fraction_of_word(low) + fraction_of_word(low + 1)
        ) / Fraction(2)
        var even = low
        if low % 2 != 0:
            even = low + 1
        assert_equal(nearest_even(mid), even)
        assert_equal(nearest_even(-mid), even | SIGN)


def test_decimal_sign_and_exact_rounding() raises:
    """Signed zero and one tenth keep their reviewed encodings."""
    assert_equal(decimal_word("-0.0"), SIGN)
    assert_equal(decimal_word("0.0"), UInt64(0))
    assert_equal(decimal_word("0.1"), UInt64(0x3FB999999999999A))
    assert_equal(decimal_word("-0.1"), UInt64(0xBFB999999999999A))
    assert_equal(decimal_word("1e1"), UInt64(0x4024000000000000))
    assert_equal(decimal_word("-1e1"), UInt64(0xC024000000000000))
    with assert_raises(contains="unsupported"):
        _ = decimal_word("no")
    with assert_raises(contains="unsupported"):
        _ = decimal_word("1e")
    with assert_raises(contains="unsupported"):
        _ = decimal_word("1.2.3")


def test_subnormal_underflow_brackets() raises:
    """The smallest positive fraction sits between 0 and the minimum."""
    var tiny = Fraction.of(BigInt(1), BigInt.power_of_two(1076))
    var pair = bracket(tiny)
    assert_equal(pair[0], UInt64(0))
    assert_equal(pair[1], UInt64(1))
    var negative = bracket(-tiny)
    assert_equal(negative[0], SIGN | 1)
    assert_equal(negative[1], SIGN)


def test_bad_and_nonfinite_words_are_refused() raises:
    """A nonfinite word and an overflow are refused."""
    var words = List[UInt64]()
    words.append(INFINITY)
    words.append(INFINITY + 1)
    words.append(SIGN | INFINITY)
    for word in words:
        with assert_raises(contains="nonfinite"):
            _ = fraction_of_word(word)
    with assert_raises(contains="overflow"):
        _ = bracket(fraction_of_word(MAX_FINITE) * Fraction(2))


def test_a_wide_endpoint_is_refused() raises:
    """A bracket wider than one step is refused."""
    with assert_raises(contains="greatest-below"):
        verify_bracket(
            Fraction(1), UInt64(0x3FEFFFFFFFFFFFFF), UInt64(0x3FF0000000000001)
        )


def main() raises:
    """Run the spiral-moment word tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
