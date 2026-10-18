# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Little-endian integers shared by the file readers.

The caller checks that `at` lies inside the buffer. These functions do
not allocate and do not raise. `little_endian_u16` and `little_endian_u32`
read a fixed width. `little_endian_uint` reads one through eight bytes.
"""


def _pack_u16(low: UInt8, high: UInt8) -> Int:
    return Int(low) | (Int(high) << 8)


def _pack_u32(b0: UInt8, b1: UInt8, b2: UInt8, b3: UInt8) -> Int:
    return Int(b0) | (Int(b1) << 8) | (Int(b2) << 16) | (Int(b3) << 24)


def little_endian_u16(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian 16-bit word at `at`.

    Args:
        bytes: The buffer.
        at: The index of the first byte.

    Returns:
        The word, with the first byte in the low eight bits.
    """
    return _pack_u16(bytes[at], bytes[at + 1])


def little_endian_u32(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian 32-bit word at `at`.

    Args:
        bytes: The buffer.
        at: The index of the first byte.

    Returns:
        The word, with the first byte in the low eight bits.
    """
    return _pack_u32(bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3])


def little_endian_u32(bytes: Span[UInt8, _], at: Int) -> Int:
    """Return the little-endian 32-bit word at `at`.

    Args:
        bytes: The buffer.
        at: The index of the first byte.

    Returns:
        The word, with the first byte in the low eight bits.
    """
    return _pack_u32(bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3])


def little_endian_i32(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian signed 32-bit integer at `at`.

    Args:
        bytes: The buffer.
        at: The index of the first byte.

    Returns:
        The integer. A word at or above 2^31 is negative.
    """
    var value = little_endian_u32(bytes, at)
    if value >= 1 << 31:
        return value - (1 << 32)
    return value


def little_endian_uint(bytes: List[UInt8], at: Int, width: Int) -> Int:
    """Return the little-endian unsigned integer of `width` bytes at `at`.

    Args:
        bytes: The buffer.
        at: The index of the first byte.
        width: How many bytes, zero through eight. Zero reads nothing.
            The caller has checked that a positive width lies inside
            `bytes`.

    Returns:
        The integer, with the first byte in the low eight bits. Zero
        when `width` is zero. Eight bytes past 2^63 read as negative.
    """
    var value = 0
    for index in range(width):
        value |= Int(bytes[at + index]) << (8 * index)
    return value
