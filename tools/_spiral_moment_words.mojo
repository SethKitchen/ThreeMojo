# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact binary64 brackets for stored spiral-moment words.

The floor and the ceiling use integer arithmetic. No host floating-point
conversion is used.
"""

from tools._bigint import BigInt
from tools._fraction import Fraction


comptime SIGN: UInt64 = 0x8000000000000000
"""The binary64 sign bit."""
comptime INFINITY: UInt64 = 0x7FF0000000000000
"""The positive-infinity encoding."""
comptime MAX_FINITE: UInt64 = 0x7FEFFFFFFFFFFFFF
"""The largest finite binary64 encoding."""


def _require(condition: Bool, message: String) raises:
    """Raise when a word check fails.

    Args:
        condition: The check.
        message: The failure text.

    Raises:
        Error: `condition` is false.
    """
    if not condition:
        raise Error("spiral moment word: " + message)


def fraction_of_word(word: UInt64) raises -> Fraction:
    """Return the exact value of one finite binary64 word.

    Args:
        word: A finite binary64 encoding.

    Returns:
        The exact rational value.

    Raises:
        Error: `word` is not finite.
    """
    var exponent = Int((word >> 52) & 0x7FF)
    _require(exponent != 0x7FF, "nonfinite binary64 word")
    var significand = Int(word & 0xFFFFFFFFFFFFF)
    var shift = -1074
    if exponent != 0:
        significand |= 1 << 52
        shift = exponent - 1075
    var magnitude = BigInt(significand)
    var value: Fraction
    if shift >= 0:
        value = Fraction(magnitude << shift)
    else:
        value = Fraction.of(magnitude, BigInt.power_of_two(-shift))
    if word & SIGN != 0:
        return -value
    return value^


def next_up(word: UInt64) -> UInt64:
    """Return the next encoding above `word`.

    Args:
        word: A binary64 encoding.

    Returns:
        The next encoding toward positive infinity, or 1 for either zero.
    """
    if word == 0 or word == SIGN:
        return 1
    if word & SIGN != 0:
        return word - 1
    return word + 1


def next_down(word: UInt64) -> UInt64:
    """Return the next encoding below `word`.

    Args:
        word: A binary64 encoding.

    Returns:
        The next encoding toward negative infinity, or the negative
        minimum for either zero.
    """
    if word == 0 or word == SIGN:
        return SIGN | 1
    if word & SIGN != 0:
        return word + 1
    return word - 1


def verify_bracket(value: Fraction, low: UInt64, high: UInt64) raises:
    """Require `low` and `high` to be the tight binary64 bracket of `value`.

    Args:
        value: The exact coefficient.
        low: The greatest encoding at or below `value`.
        high: The least encoding at or above `value`.

    Raises:
        Error: The endpoints do not form that bracket.
    """
    var lower = fraction_of_word(low)
    var upper = fraction_of_word(high)
    _require(
        lower <= value and value <= upper,
        "endpoints do not enclose exact coefficient",
    )
    var following = next_up(low)
    var preceding = next_down(high)
    _require(
        following == INFINITY or fraction_of_word(following) > value,
        "lower endpoint is not greatest-below (or equal)",
    )
    _require(
        preceding == (SIGN | INFINITY) or fraction_of_word(preceding) < value,
        "upper endpoint is not least-above (or equal)",
    )
    if value.is_zero():
        _require(low == SIGN and high == 0, "zero bracket must be [-0, +0]")


def bracket(value: Fraction) raises -> Tuple[UInt64, UInt64]:
    """Return the tight binary64 floor and ceiling of `value`.

    Args:
        value: A finite exact coefficient inside the binary64 range.

    Returns:
        The low encoding and the high encoding. Zero is `[-0, +0]`.

    Raises:
        Error: `value` overflows binary64, or the bracket is not tight.
    """
    if value.is_zero():
        return SIGN, 0
    var positive = abs(value)
    _require(positive <= fraction_of_word(MAX_FINITE), "binary64 overflow")
    var numerator = positive.numerator.copy()
    var denominator = positive.denominator.copy()
    var exponent = numerator.bit_length() - denominator.bit_length()
    var smaller: Bool
    if exponent >= 0:
        smaller = numerator < (denominator << exponent)
    else:
        smaller = (numerator << -exponent) < denominator
    if smaller:
        exponent -= 1
    var shift = max(exponent - 52, -1074)
    var significand: BigInt
    if shift >= 0:
        significand = numerator // (denominator << shift)
    else:
        significand = (numerator << -shift) // denominator
    var stored = significand.to_int()
    var low: UInt64
    if exponent < -1022:
        low = UInt64(stored)
    else:
        low = (UInt64(exponent + 1023) << 52) | (
            UInt64(stored) - (UInt64(1) << 52)
        )
    var high = low
    if fraction_of_word(low) != positive:
        high = low + 1
    var pair: Tuple[UInt64, UInt64]
    if value < Fraction(0):
        pair = (SIGN | high, SIGN | low)
    else:
        pair = (low, high)
    verify_bracket(value, pair[0], pair[1])
    return pair


def nearest_even(value: Fraction) raises -> UInt64:
    """Return the nearest binary64 encoding, with ties to even.

    Args:
        value: A finite exact coefficient inside the binary64 range.

    Returns:
        The encoding. Zero is `+0`.

    Raises:
        Error: `value` overflows binary64.
    """
    if value.is_zero():
        return 0
    var pair = bracket(value)
    var low = pair[0]
    var high = pair[1]
    var below = fraction_of_word(low)
    var above = fraction_of_word(high)
    if value - below < above - value:
        return low
    if above - value < value - below:
        return high
    if low % 2 == 0:
        return low
    return high


def _decimal(token: String) raises -> Fraction:
    """Return the exact value of one decimal literal.

    Args:
        token: A decimal number, with an optional sign and exponent.

    Returns:
        The exact rational. `-0.0` is zero.

    Raises:
        Error: `token` is not a decimal literal.
    """
    var bytes = token.as_bytes()
    _require(len(bytes) > 0, "unsupported decimal word")
    var index = 0
    var negative = False
    if bytes[0] == 43 or bytes[0] == 45:
        negative = bytes[0] == 45
        index = 1
    var magnitude = BigInt(0)
    var places = 0
    var saw_digit = False
    var fraction = False
    while index < len(bytes) and bytes[index] != 101 and bytes[index] != 69:
        if bytes[index] == 46:
            _require(not fraction, "unsupported decimal word")
            fraction = True
        else:
            _require(
                bytes[index] >= 48 and bytes[index] <= 57,
                "unsupported decimal word",
            )
            magnitude = magnitude * BigInt(10) + BigInt(Int(bytes[index]) - 48)
            saw_digit = True
            if fraction:
                places += 1
        index += 1
    _require(saw_digit, "unsupported decimal word")
    var exponent = -places
    if index < len(bytes):
        index += 1
        var exp_sign = 1
        if index < len(bytes) and (bytes[index] == 43 or bytes[index] == 45):
            if bytes[index] == 45:
                exp_sign = -1
            index += 1
        var exp_value = 0
        var saw_exp = False
        while index < len(bytes):
            _require(
                bytes[index] >= 48 and bytes[index] <= 57,
                "unsupported decimal word",
            )
            exp_value = exp_value * 10 + Int(bytes[index]) - 48
            saw_exp = True
            index += 1
        _require(saw_exp, "unsupported decimal word")
        exponent += exp_sign * exp_value
    var value: Fraction
    if exponent >= 0:
        var scale = BigInt(1)
        for _power in range(exponent):
            scale = scale * BigInt(10)
        value = Fraction(magnitude * scale)
    else:
        var scale = BigInt(1)
        for _power in range(-exponent):
            scale = scale * BigInt(10)
        value = Fraction.of(magnitude, scale)
    if negative:
        return -value
    return value^


def decimal_word(token: String) raises -> UInt64:
    """Return the binary64 encoding of one decimal literal.

    Args:
        token: A decimal number, with an optional sign.

    Returns:
        The nearest encoding, ties to even. `-0.0` keeps its sign.

    Raises:
        Error: `token` is not a finite decimal literal.
    """
    var value = _decimal(token)
    if value.is_zero() and token.startswith("-"):
        return SIGN
    return nearest_even(value)
