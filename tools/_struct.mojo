# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Little-endian packing with the rules of Python's `struct` module.

The converters wrote their files with `struct.pack("<...")`. These functions
append the same bytes and refuse the same values: an integer outside its
field, or a double too large for a `float`.
"""

from std.math import isinf
from std.memory import bitcast


def _push(mut out: List[UInt8], value: UInt64, width: Int):
    """Append the low `width` bytes of `value`, least significant first."""
    for i in range(width):
        out.append(UInt8((value >> UInt64(8 * i)) & 0xFF))


def pack_u8(mut out: List[UInt8], value: Int) raises:
    """Append an unsigned byte, as `struct.pack("<B", value)` does.

    Args:
        out: The bytes so far.
        value: A number from 0 to 255.

    Raises:
        Error: If the value is out of range.
    """
    if value < 0 or value > 0xFF:
        raise Error("ubyte format requires 0 <= number <= 255")
    out.append(UInt8(value))


def pack_u16(mut out: List[UInt8], value: Int) raises:
    """Append an unsigned 16-bit integer, as `struct.pack("<H")` does.

    Args:
        out: The bytes so far.
        value: A number from 0 to 65535.

    Raises:
        Error: If the value is out of range.
    """
    if value < 0 or value > 0xFFFF:
        raise Error("'H' format requires 0 <= number <= 65535")
    _push(out, UInt64(value), 2)


def pack_i16(mut out: List[UInt8], value: Int) raises:
    """Append a signed 16-bit integer, as `struct.pack("<h")` does.

    Args:
        out: The bytes so far.
        value: A number from -32768 to 32767.

    Raises:
        Error: If the value is out of range.
    """
    if value < -0x8000 or value > 0x7FFF:
        raise Error("'h' format requires -32768 <= number <= 32767")
    _push(out, UInt64(value & 0xFFFF), 2)


def pack_u32(mut out: List[UInt8], value: Int) raises:
    """Append an unsigned 32-bit integer, as `struct.pack("<I")` does.

    Args:
        out: The bytes so far.
        value: A number from 0 to 4294967295.

    Raises:
        Error: If the value is out of range.
    """
    if value < 0 or value > 0xFFFFFFFF:
        raise Error("'I' format requires 0 <= number <= 4294967295")
    _push(out, UInt64(value), 4)


def pack_f32(mut out: List[UInt8], value: Float64) raises:
    """Append a double rounded to a `float`, as `struct.pack("<f")` does.

    Args:
        out: The bytes so far.
        value: The number.

    Raises:
        Error: If a finite double rounds to an infinite `float`.
    """
    var single = value.cast[DType.float32]()
    if isinf(single) and not isinf(value):
        raise Error("float too large to pack with f format")
    _push(out, UInt64(bitcast[DType.uint32](single)), 4)


def pad4(mut out: List[UInt8]):
    """Append zero bytes up to a multiple of four.

    Args:
        out: The bytes so far.
    """
    while len(out) % 4 != 0:
        out.append(0)


def unpack_u32(data: Span[UInt8, _], at: Int) raises -> Int:
    """Read an unsigned 32-bit integer, as `struct.unpack_from("<I")` does.

    Args:
        data: The bytes.
        at: The offset of the first byte.

    Returns:
        The number.

    Raises:
        Error: If the four bytes are not all inside `data`.
    """
    if at < 0 or at + 4 > len(data):
        raise Error("unpack_from requires a buffer of at least 4 bytes")
    var value = 0
    for i in range(4):
        value |= Int(data[at + i]) << (8 * i)
    return value


def unpack_f32(data: Span[UInt8, _], at: Int) raises -> Float64:
    """Read a `float` as a double, as `struct.unpack_from("<f")` does.

    Args:
        data: The bytes.
        at: The offset of the first byte.

    Returns:
        The number, exactly.

    Raises:
        Error: If the four bytes are not all inside `data`.
    """
    var bits = UInt32(unpack_u32(data, at))
    return bitcast[DType.float32](bits).cast[DType.float64]()
