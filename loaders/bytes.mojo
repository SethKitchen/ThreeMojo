# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shared checks on a byte.

`bytes_match` asks whether an ASCII word sits at one byte.
`ascii_space`, `ascii_digit`, and `ascii_letter` name white space, a
decimal digit, and a letter. `ascii_space_at` and `ascii_digit_at` ask
the same of one index. `js_float_byte` names a byte a JavaScript number
can hold, and `js_float_byte_at` asks the same of one index.
`hex_digit_value` reads one hexadecimal digit.
`base64_digit` reads one letter or digit of the base64 alphabet.
"""


def bytes_match(
    bytes: Span[UInt8, _], at: Int, limit: Int, word: String
) -> Bool:
    """Return True when `word` fits before `limit` and matches there.

    Args:
        bytes: The bytes to read.
        at: The first byte of `word`.
        limit: The first byte `word` must not reach. This is the end of
            `bytes`, or the end of a shorter span inside them.
        word: The ASCII text to match. The word is not empty.

    Returns:
        Whether every byte of `word` is at `at`.
    """
    var expected = word.as_bytes()
    if at + len(expected) > limit:
        return False
    # The word is not empty: the loop always runs.
    for offset in range(len(expected)):  # pragma: no branch
        if bytes[at + offset] != expected[offset]:
            return False
    return True


def ascii_space(byte: Int) -> Bool:
    """Return True for an ASCII white space byte.

    Args:
        byte: A byte value.

    Returns:
        Whether it is a space, a tab, a line feed, a vertical tab, a form
        feed, or a carriage return.
    """
    return byte == 32 or (byte >= 9 and byte <= 13)


def ascii_space(byte: UInt8) -> Bool:
    """Return True for an ASCII white space byte.

    Args:
        byte: A byte value.

    Returns:
        Whether it is a space, a tab, a line feed, a vertical tab, a form
        feed, or a carriage return.

    Raises:
        Error: Never.
    """
    return ascii_space(Int(byte))


def space_tab_return(byte: UInt8) -> Bool:
    """Return True for a space, a tab, or a carriage return.

    Args:
        byte: A byte value.

    Returns:
        Whether it is one of those three bytes.

    Raises:
        Error: Never.
    """
    return byte == 0x20 or byte == 0x09 or byte == 0x0D


def space_tab_line(byte: Int) -> Bool:
    """Return True for a space, a tab, a line feed, or a carriage return.

    Args:
        byte: A byte value.

    Returns:
        Whether it is one of those four bytes.

    Raises:
        Error: Never.
    """
    return byte == 32 or byte == 9 or byte == 10 or byte == 13


def space_tab_line(byte: UInt8) -> Bool:
    """Return True for a space, a tab, a line feed, or a carriage return.

    Args:
        byte: A byte value.

    Returns:
        Whether it is one of those four bytes.

    Raises:
        Error: Never.
    """
    return space_tab_line(Int(byte))


def ascii_digit(byte: Int) -> Bool:
    """Return True for an ASCII decimal digit.

    Args:
        byte: A byte value.

    Returns:
        Whether it is `0` through `9`.
    """
    return byte >= 48 and byte <= 57


def ascii_digit(byte: UInt8) -> Bool:
    """Return True for an ASCII decimal digit.

    Args:
        byte: A byte value.

    Returns:
        Whether it is `0` through `9`.

    Raises:
        Error: Never.
    """
    return ascii_digit(Int(byte))


def ascii_space_at(bytes: Span[UInt8, _], at: Int) -> Bool:
    """Return True when `at` names an ASCII white space byte.

    Args:
        bytes: The bytes to read.
        at: The index to read.

    Returns:
        Whether `at` is inside `bytes` and that byte is white space.

    Raises:
        Error: Never.
    """
    return at < len(bytes) and ascii_space(bytes[at])


def ascii_digit_at(bytes: Span[UInt8, _], at: Int) -> Bool:
    """Return True when `at` names an ASCII decimal digit.

    Args:
        bytes: The bytes to read.
        at: The index to read.

    Returns:
        Whether `at` is inside `bytes` and that byte is a decimal digit.

    Raises:
        Error: Never.
    """
    return at < len(bytes) and ascii_digit(bytes[at])


def is_sign_mark(byte: Int) -> Bool:
    """Return True for `+` or `-`.

    Args:
        byte: A byte value.

    Returns:
        Whether it is a sign.

    Raises:
        Error: Never.
    """
    return byte == 43 or byte == 45


def is_sign_mark(byte: UInt8) -> Bool:
    """Return True for `+` or `-`.

    Args:
        byte: A byte value.

    Returns:
        Whether it is a sign.

    Raises:
        Error: Never.
    """
    return is_sign_mark(Int(byte))


def is_exponent_mark(byte: Int) -> Bool:
    """Return True for `e` or `E`.

    Args:
        byte: A byte value.

    Returns:
        Whether it starts a decimal exponent.

    Raises:
        Error: Never.
    """
    return byte == 101 or byte == 69


def is_exponent_mark(byte: UInt8) -> Bool:
    """Return True for `e` or `E`.

    Args:
        byte: A byte value.

    Returns:
        Whether it starts a decimal exponent.

    Raises:
        Error: Never.
    """
    return is_exponent_mark(Int(byte))


def js_float_byte(byte: UInt8) -> Bool:
    """Return True when `byte` can sit inside a JavaScript number.

    The bytes are a digit, `.`, `e`, `+`, and `-`.

    Args:
        byte: The byte.

    Returns:
        Whether the byte is one of those.

    Raises:
        Error: Never.
    """
    return (
        ascii_digit(byte)
        or byte == 46
        or byte == 43
        or byte == 45
        or byte == 101
    )


def js_float_byte_at(bytes: Span[UInt8, _], at: Int) -> Bool:
    """Return True when `at` names a byte a JavaScript number can hold.

    Args:
        bytes: The bytes to read.
        at: The index to read.

    Returns:
        Whether `at` is inside `bytes` and that byte can sit in a number.

    Raises:
        Error: Never.
    """
    return at < len(bytes) and js_float_byte(bytes[at])


def ascii_letter(byte: Int) -> Bool:
    """Return True for an ASCII letter, either case.

    Args:
        byte: A byte value.

    Returns:
        Whether it is `A` through `Z` or `a` through `z`.
    """
    return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)


def base64_digit(byte: Int) -> Int:
    """Return 0 through 61 for an ASCII letter or digit, or -1.

    `A` is 0, `a` is 26, and `0` is 52. `+`, `/`, and the URL forms stay
    with the caller.

    Args:
        byte: A byte value.

    Returns:
        The six-bit value, or -1 when `byte` is outside `A-Z`, `a-z`, and
        `0-9`.
    """
    if ascii_digit(byte):
        return byte + 4
    if not ascii_letter(byte):
        return -1
    if byte <= 90:
        return byte - 65
    return byte - 71


def hex_digit_value(byte: Int) -> Int:
    """Return the value of one ASCII hexadecimal digit, or -1.

    Args:
        byte: A byte value. A value outside 0 through 255 is not a digit.

    Returns:
        0 through 15 for `0-9`, `A-F` and `a-f`. -1 for any other value.
    """
    if ascii_digit(byte):
        return byte - 48
    if byte >= 65 and byte <= 70:
        return byte - 55
    if byte >= 97 and byte <= 102:
        return byte - 87
    return -1


def is_hex_digit(byte: Int) -> Bool:
    """Return True for one ASCII hexadecimal digit.

    Args:
        byte: A byte value. A value outside 0 through 255 is not a digit.

    Returns:
        Whether it is `0-9`, `A-F`, or `a-f`.

    Raises:
        Error: Never.
    """
    return hex_digit_value(byte) >= 0
