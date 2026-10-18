# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Integers and byte copies shared by the file readers.

The caller checks that the read lies inside the buffer. The integer
readers do not allocate and do not raise. `little_endian_u16`,
`little_endian_u32`, `big_endian_u16`, and `big_endian_u32` read a fixed
width. `little_endian_uint` reads zero through eight bytes.
`append_little_endian` appends a chosen width.
`append_little_endian_u16` and `append_little_endian_u32` append a fixed
width. `store_little_endian` writes a chosen width at an index.
`append_big_endian` and `store_big_endian` write the most significant
byte first. `copy_bytes` returns a new list and does not raise.
`copy_byte_range` copies from one index up to another.
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


def big_endian_u16(bytes: List[UInt8], at: Int) -> Int:
    """Return the big-endian 16-bit word at `at`.

    Args:
        bytes: The buffer.
        at: The index of the first byte.

    Returns:
        The word, with the first byte in the high eight bits.

    Raises:
        Error: Never.
    """
    return (Int(bytes[at]) << 8) | Int(bytes[at + 1])


def little_endian_u32(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian 32-bit word at `at`.

    Args:
        bytes: The buffer.
        at: The index of the first byte.

    Returns:
        The word, with the first byte in the low eight bits.
    """
    return _pack_u32(bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3])


def big_endian_u32(bytes: Span[UInt8, _], at: Int) -> Int:
    """Return the big-endian 32-bit word at `at`.

    Args:
        bytes: The buffer.
        at: The index of the first byte.

    Returns:
        The word, with the first byte in the high eight bits.

    Raises:
        Error: Never.
    """
    return (
        (Int(bytes[at]) << 24)
        | (Int(bytes[at + 1]) << 16)
        | (Int(bytes[at + 2]) << 8)
        | Int(bytes[at + 3])
    )


def big_endian_u32(bytes: List[UInt8], at: Int) -> Int:
    """Return the big-endian 32-bit word at `at`.

    Args:
        bytes: The buffer.
        at: The index of the first byte.

    Returns:
        The word, with the first byte in the high eight bits.

    Raises:
        Error: Never.
    """
    return big_endian_u32(Span(bytes), at)


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


def little_endian_uint(bytes: Span[UInt8, _], at: Int, width: Int) -> Int:
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

    Raises:
        Error: Never.
    """
    var value = 0
    for index in range(width):
        value |= Int(bytes[at + index]) << (8 * index)
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
    return little_endian_uint(Span(bytes), at, width)


def append_little_endian(mut out: List[UInt8], value: Int, width: Int):
    """Append the low `width` bytes of `value`, least significant byte first.

    Args:
        out: The buffer, extended in place.
        value: The integer.
        width: How many bytes to append. Zero appends nothing.

    Returns:
        Nothing.

    Raises:
        Error: Never.
    """
    for index in range(width):
        out.append(UInt8((value >> (8 * index)) & 0xFF))


def append_little_endian_u16(mut out: List[UInt8], value: Int):
    """Append the low sixteen bits of `value` as two little-endian bytes.

    Args:
        out: The buffer, extended in place.
        value: The integer. Bits above the low sixteen are not written.

    Returns:
        Nothing.

    Raises:
        Error: Never.
    """
    append_little_endian(out, value, 2)


def append_little_endian_u32(mut out: List[UInt8], value: Int):
    """Append the low thirty-two bits of `value` as four little-endian bytes.

    Args:
        out: The buffer, extended in place.
        value: The integer. Bits above the low thirty-two are not written.

    Returns:
        Nothing.

    Raises:
        Error: Never.
    """
    append_little_endian(out, value, 4)


def store_little_endian(
    mut bytes: List[UInt8], at: Int, value: Int, width: Int
):
    """Store the low `width` bytes of `value` at `at`.

    The first byte is the least significant one.

    Args:
        bytes: The buffer.
        at: The index of the first byte.
        value: The integer.
        width: How many bytes. The caller has checked that a positive
            width lies inside `bytes`.

    Returns:
        Nothing.

    Raises:
        Error: Never.
    """
    for index in range(width):  # pragma: no branch
        bytes[at + index] = UInt8((value >> (8 * index)) & 0xFF)


def append_big_endian(mut out: List[UInt8], value: Int, width: Int):
    """Append the low `width` bytes of `value`, most significant byte first.

    Args:
        out: The buffer, extended in place.
        value: The integer.
        width: How many bytes to append. The caller passes a positive
            width.

    Returns:
        Nothing.

    Raises:
        Error: Never.
    """
    for index in range(width):  # pragma: no branch
        var shift = 8 * (width - 1 - index)
        out.append(UInt8((value >> shift) & 0xFF))


def store_big_endian(mut bytes: List[UInt8], at: Int, value: Int, width: Int):
    """Store the low `width` bytes of `value` at `at`, most significant byte first.

    Args:
        bytes: The buffer.
        at: The index of the first byte.
        value: The integer.
        width: How many bytes. The caller has checked that a positive
            width lies inside `bytes`.

    Returns:
        Nothing.

    Raises:
        Error: Never.
    """
    for index in range(width):  # pragma: no branch
        var shift = 8 * (width - 1 - index)
        bytes[at + index] = UInt8((value >> shift) & 0xFF)


def copy_bytes(bytes: Span[UInt8, _], start: Int, count: Int) -> List[UInt8]:
    """Return `count` bytes beginning at `start`.

    Args:
        bytes: The buffer.
        start: The index of the first byte.
        count: How many bytes. Zero returns an empty list. The caller
            has checked that a positive count lies inside `bytes`.

    Returns:
        A copy of those bytes.

    Raises:
        Error: Never.
    """
    return List[UInt8](bytes[start : start + count])


def copy_bytes(bytes: List[UInt8], start: Int, count: Int) -> List[UInt8]:
    """Return `count` bytes beginning at `start`.

    Args:
        bytes: The buffer.
        start: The index of the first byte.
        count: How many bytes. Zero returns an empty list. The caller
            has checked that a positive count lies inside `bytes`.

    Returns:
        A copy of those bytes.
    """
    return copy_bytes(Span(bytes), start, count)


def copy_byte_range(bytes: List[UInt8], start: Int, end: Int) -> List[UInt8]:
    """Return a copy of the bytes from `start` up to `end`.

    Args:
        bytes: The buffer.
        start: The first byte.
        end: The first byte not copied. An end before `start` copies
            nothing.

    Returns:
        The copy. The caller has checked that a positive span lies
        inside `bytes`.

    Raises:
        Error: Never.
    """
    var count = end - start
    if count < 0:
        count = 0
    return copy_bytes(bytes, start, count)
