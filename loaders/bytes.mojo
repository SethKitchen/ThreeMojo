# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shared checks on a byte.

`bytes_match` asks whether an ASCII word sits at one byte.
`ascii_space`, `ascii_digit`, and `ascii_letter` name white space, a
decimal digit, and a letter. `hex_digit_value` reads one hexadecimal
digit. `base64_digit` reads one letter or digit of the base64 alphabet.
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
