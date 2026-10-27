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
from tools._python_json import PyJson


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


def _as_int(word: UInt64) -> BigInt:
    """Return `word` as an integer.

    Args:
        word: A binary64 encoding.

    Returns:
        The same bits as a non-negative integer.
    """
    var low = BigInt(Int(word & 0xFFFFFFFF))
    var high = BigInt(Int(word >> 32))
    return (high << 32) + low


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


def _slash_fraction(token: String) raises -> Fraction:
    """Return the exact value of one integer fraction.

    Args:
        token: Two integers separated by `/`, with an optional sign and spaces.

    Returns:
        The exact rational. A negative zero numerator keeps the sign for the
        caller.

    Raises:
        Error: `token` is not one integer fraction, or the denominator is zero.
    """
    var bytes = token.as_bytes()
    var index = 0
    while index < len(bytes) and (bytes[index] == 9 or bytes[index] == 32):
        index += 1
    _require(index < len(bytes), "unsupported decimal word")
    var negative = False
    if bytes[index] == 43 or bytes[index] == 45:
        negative = bytes[index] == 45
        index += 1
    var numerator = BigInt(0)
    var saw_numerator = False
    while index < len(bytes) and bytes[index] >= 48 and bytes[index] <= 57:
        numerator = numerator * BigInt(10) + BigInt(Int(bytes[index]) - 48)
        saw_numerator = True
        index += 1
    _require(saw_numerator, "unsupported decimal word")
    while index < len(bytes) and (bytes[index] == 9 or bytes[index] == 32):
        index += 1
    _require(
        index < len(bytes) and bytes[index] == 47, "unsupported decimal word"
    )
    index += 1
    while index < len(bytes) and (bytes[index] == 9 or bytes[index] == 32):
        index += 1
    var denominator = BigInt(0)
    var saw_denominator = False
    var nonzero = False
    while index < len(bytes) and bytes[index] >= 48 and bytes[index] <= 57:
        var digit = Int(bytes[index]) - 48
        if digit != 0:
            nonzero = True
        denominator = denominator * BigInt(10) + BigInt(digit)
        saw_denominator = True
        index += 1
    _require(saw_denominator and nonzero, "unsupported decimal word")
    while index < len(bytes) and (bytes[index] == 9 or bytes[index] == 32):
        index += 1
    _require(index == len(bytes), "unsupported decimal word")
    var value = Fraction.of(numerator, denominator)
    if negative:
        return -value
    return value^


def _decimal(token: String) raises -> Fraction:
    """Return the exact value of one decimal literal or integer fraction.

    Args:
        token: A decimal number, with an optional sign and exponent, or two
            integers separated by `/`.

    Returns:
        The exact rational. `-0.0` is zero.

    Raises:
        Error: `token` is not a decimal literal or one integer fraction.
    """
    var bytes = token.as_bytes()
    _require(len(bytes) > 0, "unsupported decimal word")
    var scan = 0
    while scan < len(bytes):
        if bytes[scan] == 47:
            return _slash_fraction(token)
        scan += 1
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
    """Return the binary64 encoding of one decimal literal or integer fraction.

    Args:
        token: A decimal number, with an optional sign, or two integers
            separated by `/`.

    Returns:
        The nearest encoding, ties to even. `-0.0` keeps its sign.

    Raises:
        Error: `token` is not a finite decimal literal or integer fraction.
    """
    var value = _decimal(token)
    if value.is_zero() and token.startswith("-"):
        return SIGN
    return nearest_even(value)


def _hex_word(word: UInt64) -> String:
    """Return `word` as `0x` and sixteen uppercase hexadecimal digits.

    Args:
        word: One binary64 encoding.

    Returns:
        The canonical literal.
    """
    var digits = "0123456789ABCDEF"
    var text = String("0x")
    var shift = 60
    while shift >= 0:
        var nibble = Int((word >> UInt64(shift)) & 15)
        text += String(digits[byte = nibble : nibble + 1])
        shift -= 4
    return text


def _parse_word(text: String) raises -> UInt64:
    """Return one `0x` word.

    Args:
        text: A hexadecimal encoding with an optional `0x` prefix.

    Returns:
        The encoding.

    Raises:
        Error: The text is not one to sixteen hexadecimal digits.
    """
    var data = text.as_bytes()
    var index = 0
    if len(data) >= 2 and data[0] == 48 and (data[1] == 120 or data[1] == 88):
        index = 2
    if index >= len(data):
        raise Error("malformed coefficient word")
    var value = UInt64(0)
    var digits = 0
    while index < len(data):
        var byte = data[index]
        var nibble = -1
        if byte >= 48 and byte <= 57:
            nibble = Int(byte) - 48
        elif byte >= 65 and byte <= 70:
            nibble = Int(byte) - 55
        elif byte >= 97 and byte <= 102:
            nibble = Int(byte) - 87
        if nibble < 0 or digits == 16:
            raise Error("malformed coefficient word")
        value = (value << 4) | UInt64(nibble)
        digits += 1
        index += 1
    return value


def _word_list(doc: PyJson, key: String) raises -> List[UInt64]:
    """Return one hex list from a node-sum payload.

    Args:
        doc: The payload document.
        key: `nodes` or `weights`.

    Returns:
        The encodings in order.

    Raises:
        Error: A word is malformed.
    """
    var node = doc.at(doc.root, key)
    var count = doc.length(node)
    var words = List[UInt64]()
    var index = 0
    while index < count:
        words.append(_parse_word(doc.text(doc.item(node, index))))
        index += 1
    return words^


def rounded_node_sums(
    nodes: List[UInt64], weights: List[UInt64]
) raises -> List[UInt64]:
    """Return the rounded `1 + node` words and check the weight sum.

    Args:
        nodes: The five stored Gauss-Legendre nodes.
        weights: The five stored Gauss-Legendre weights.

    Returns:
        The five nearest encodings of `1 + node`, ties to even.

    Raises:
        Error: A list does not hold five words, or the stored weights do
            not keep the zeroth moment.
    """
    if len(nodes) != 5 or len(weights) != 5:
        raise Error("wrong constant-array shape")
    var sums = List[UInt64]()
    for node in nodes:
        sums.append(nearest_even(Fraction(1) + fraction_of_word(node)))
    var total = Fraction(0)
    for weight in weights:
        total = total + fraction_of_word(weight)
    var zeroth = Fraction(1) + Fraction.of(BigInt(3), BigInt.power_of_two(55))
    if total / Fraction(2) != zeroth:
        raise Error("stored zeroth moment must not be normalized to one")
    return sums^


def rounded_node_sums_payload(payload: String) raises -> String:
    """Return the rounded node sums for one JSON word document.

    Args:
        payload: JSON with `nodes` and `weights`.

    Returns:
        A JSON list of five `0x` words.

    Raises:
        Error: A word is malformed, a list does not hold five words, or
            the stored weights do not keep the zeroth moment.
    """
    var doc = PyJson.parse(payload)
    var sums = rounded_node_sums(
        _word_list(doc, "nodes"), _word_list(doc, "weights")
    )
    var out = PyJson()
    var rows = out.new_list()
    for word in sums:
        out.append(rows, out.new_str(_hex_word(word)))
    out.root = rows
    return out.dumps()


def _fraction_text(value: Fraction) -> String:
    """Return `n/d`, or `n` when the denominator is one.

    Args:
        value: The exact coefficient.

    Returns:
        The text `str(Fraction)` would produce.
    """
    var text = value.numerator.to_string()
    if value.denominator != BigInt(1):
        text += "/"
        text += value.denominator.to_string()
    return text


def fraction_texts(words: List[UInt64]) raises -> List[String]:
    """Return the exact fraction spelling of each binary64 word.

    Args:
        words: Finite binary64 encodings.

    Returns:
        One `n` or `n/d` spelling per word, in order.

    Raises:
        Error: A word is not finite.
    """
    var texts = List[String]()
    for word in words:
        texts.append(_fraction_text(fraction_of_word(word)))
    return texts^


def fraction_texts_payload(payload: String) raises -> String:
    """Return exact fraction spellings for one JSON word list.

    Args:
        payload: A JSON list of `0x` words.

    Returns:
        A JSON list of `n` or `n/d` spellings.

    Raises:
        Error: A word is malformed or not finite.
    """
    var doc = PyJson.parse(payload)
    var count = doc.length(doc.root)
    var words = List[UInt64]()
    var index = 0
    while index < count:
        words.append(_parse_word(doc.text(doc.item(doc.root, index))))
        index += 1
    var texts = fraction_texts(words)
    var out = PyJson()
    var rows = out.new_list()
    for text in texts:
        out.append(rows, out.new_str(text))
    out.root = rows
    return out.dumps()


def _u64_decimal(text: String) raises -> UInt64:
    """Return the value of an unsigned decimal integer.

    Args:
        text: Decimal digits, with no sign.

    Returns:
        The value.

    Raises:
        Error: The text is empty, not decimal, or larger than 64 bits.
    """
    var data = text.as_bytes()
    if len(data) == 0:
        raise Error("invalid UInt64 word")
    var value = UInt64(0)
    var index = 0
    while index < len(data):
        var byte = data[index]
        if byte < 48 or byte > 57:
            raise Error("invalid UInt64 word")
        var digit = UInt64(Int(byte - 48))
        if value > UInt64(1844674407370955161) or (
            value == UInt64(1844674407370955161) and digit > UInt64(5)
        ):
            raise Error("invalid UInt64 word")
        value = value * UInt64(10) + digit
        index += 1
    return value


def hex_words_json(payload: String) raises -> String:
    """Return the `0x` spelling of each decimal word.

    Args:
        payload: A JSON list of unsigned decimal integers.

    Returns:
        A JSON list of `0x` words with 16 uppercase digits.

    Raises:
        Error: A word is empty, not decimal, or larger than 64 bits.
    """
    var doc = PyJson.parse(payload)
    var count = doc.length(doc.root)
    var out = PyJson()
    var rows = out.new_list()
    var index = 0
    while index < count:
        var word = _u64_decimal(doc.text(doc.item(doc.root, index)))
        out.append(rows, out.new_str(_hex_word(word)))
        index += 1
    out.root = rows
    return out.dumps()


def require_stored_words(payload: String) raises:
    """Require decimal words to match a pinned `0x` list.

    Args:
        payload: JSON with `words`, `expected`, and `message`. `words` are
            unsigned decimals. `expected` are `0x` spellings.

    Raises:
        Error: A word is invalid, or the lists differ. The text is `message`.
    """
    var doc = PyJson.parse(payload)
    var words = doc.at(doc.root, "words")
    var expected = doc.at(doc.root, "expected")
    var message = doc.text(doc.at(doc.root, "message"))
    var count = doc.length(words)
    if count != doc.length(expected):
        raise Error(message)
    var index = 0
    while index < count:
        var spelled = _hex_word(_u64_decimal(doc.text(doc.item(words, index))))
        if spelled != doc.text(doc.item(expected, index)):
            raise Error(message)
        index += 1
