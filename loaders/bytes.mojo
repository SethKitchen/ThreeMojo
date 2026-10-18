# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shared checks on a byte.

`bytes_match` asks whether an ASCII word sits at one byte.
`ascii_space` and `ascii_digit` name white space and a decimal digit.
`hex_digit_value` reads one hexadecimal digit.
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


def ascii_digit(byte: Int) -> Bool:
    """Return True for an ASCII decimal digit.

    Args:
        byte: A byte value.

    Returns:
        Whether it is `0` through `9`.
    """
    return byte >= 48 and byte <= 57


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
