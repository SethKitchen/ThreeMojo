# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The system zlib, for tools that must write the bytes Python's `zlib` wrote.

A fixture generator that used `zlib.compress` recorded the system zlib's
exact output. `render/deflate` writes fflate's streams, which decode to the
same bytes but are not the same bytes. These functions call the system
library, `libz.so.1` on Linux or `libz.1.dylib` on macOS, as Python does.
"""

from std.ffi import OwnedDLHandle
from std.memory import OpaquePointer
from std.sys import CompilationTarget

comptime Z_OK = 0
"""The success code of zlib."""


def _library() raises -> OwnedDLHandle:
    """Open the system zlib."""
    comptime if CompilationTarget.is_macos():
        return OwnedDLHandle("libz.1.dylib")
    else:
        return OwnedDLHandle("libz.so.1")


def compress(data: List[UInt8], level: Int = 6) raises -> List[UInt8]:
    """Return a zlib stream, as `zlib.compress(data, level)` does.

    Args:
        data: The bytes to compress.
        level: From 0, stored, to 9, the smallest. Python's default is 6.

    Returns:
        The stream.

    Raises:
        Error: If zlib cannot be loaded or fails.
    """
    if level < -1 or level > 9:
        raise Error("zlib level must be -1 to 9")
    var library = _library()
    var bound = library.call["compressBound", UInt64](UInt64(len(data)))
    var out = List[UInt8](length=Int(bound), fill=0)
    var size = List[UInt64](length=1, fill=bound)
    var status = library.call["compress2", Int32](
        out.unsafe_ptr().unsafe_bitcast[NoneType](),
        size.unsafe_ptr().unsafe_bitcast[NoneType](),
        data.unsafe_ptr().unsafe_bitcast[NoneType](),
        UInt64(len(data)),
        Int32(level),
    )
    if status != Z_OK:
        raise Error("zlib compress2 failed: " + String(status))
    out.resize(Int(size[0]), 0)
    return out^


def crc32(data: List[UInt8], start: UInt32 = 0) raises -> UInt32:
    """Return the CRC-32 of the data, as `zlib.crc32(data, start)` does.

    Args:
        data: The bytes.
        start: The running CRC to continue.

    Returns:
        The CRC.

    Raises:
        Error: If zlib cannot be loaded.
    """
    var library = _library()
    return UInt32(
        library.call["crc32", UInt64](
            UInt64(start),
            data.unsafe_ptr().unsafe_bitcast[NoneType](),
            UInt32(len(data)),
        )
    )


# LP64 `z_stream` from zlib 1.2 and 1.3: 112 bytes, little-endian.
comptime _STREAM_BYTES = 112
comptime _NEXT_IN = 0
comptime _AVAIL_IN = 8
comptime _NEXT_OUT = 24
comptime _AVAIL_OUT = 32
comptime _TOTAL_OUT = 40
comptime _Z_NO_FLUSH = 0
comptime _Z_STREAM_END = 1
comptime _Z_FINISH = 4
comptime _Z_FILTERED = 1


def _store_u32(mut raw: List[UInt8], offset: Int, value: UInt32):
    """Write one little-endian 32-bit field."""
    raw[offset] = UInt8(value & 255)
    raw[offset + 1] = UInt8((value >> 8) & 255)
    raw[offset + 2] = UInt8((value >> 16) & 255)
    raw[offset + 3] = UInt8((value >> 24) & 255)


def _store_u64(mut raw: List[UInt8], offset: Int, value: UInt64):
    """Write one little-endian 64-bit field."""
    var rest = value
    for shift in range(8):
        raw[offset + shift] = UInt8(rest & 255)
        rest >>= 8


def _load_u32(raw: List[UInt8], offset: Int) -> UInt32:
    """Read one little-endian 32-bit field."""
    var value = UInt32(0)
    for shift in range(4):
        value |= UInt32(raw[offset + shift]) << UInt32(8 * shift)
    return value


def _load_u64(raw: List[UInt8], offset: Int) -> UInt64:
    """Read one little-endian 64-bit field."""
    var value = UInt64(0)
    for shift in range(8):
        value |= UInt64(raw[offset + shift]) << UInt64(8 * shift)
    return value


def _pointer(address: Int) -> OpaquePointer[MutAnyOrigin]:
    """Return an address as a C pointer."""
    return OpaquePointer[MutAnyOrigin](unsafe_from_address=address)


def deflate_filtered(data: List[UInt8], level: Int) raises -> List[UInt8]:
    """Return a zlib stream with Pillow's PNG compressor settings.

    Args:
        data: The filtered scanlines.
        level: From 0 to 9, or -1 for zlib's default. Pillow uses 9 when
            `optimize` is true and -1 otherwise.

    Returns:
        The stream from `deflateInit2` with window 15, memory level 9,
        and strategy `Z_FILTERED`.

    Raises:
        Error: If zlib cannot be loaded, `level` is outside -1..9, or
            deflate fails.
    """
    if level < -1 or level > 9:
        raise Error("zlib level must be -1 to 9")
    var library = _library()
    var version = library.call["zlibVersion", OpaquePointer[MutAnyOrigin]]()
    var stream = List[UInt8](length=_STREAM_BYTES, fill=0)
    var stream_ptr = _pointer(Int(stream.unsafe_ptr()))
    var status = library.call["deflateInit2_", Int32](
        stream_ptr,
        Int32(level),
        Int32(8),
        Int32(15),
        Int32(9),
        Int32(_Z_FILTERED),
        version,
        Int32(_STREAM_BYTES),
    )
    if status != Z_OK:
        raise Error("zlib deflateInit2 failed: " + String(status))
    var bound = (
        Int(library.call["compressBound", UInt64](UInt64(len(data)))) + 64
    )
    var out = List[UInt8](length=bound, fill=0)
    var source = UInt64(0)
    if len(data) > 0:
        source = UInt64(Int(data.unsafe_ptr()))
    _store_u64(stream, _NEXT_IN, source)
    _store_u32(stream, _AVAIL_IN, UInt32(len(data)))
    _store_u64(stream, _NEXT_OUT, UInt64(Int(out.unsafe_ptr())))
    _store_u32(stream, _AVAIL_OUT, UInt32(bound))
    status = library.call["deflate", Int32](stream_ptr, Int32(_Z_NO_FLUSH))
    if status != Z_OK:
        _ = library.call["deflateEnd", Int32](stream_ptr)
        raise Error("zlib deflate failed: " + String(status))
    if _load_u32(stream, _AVAIL_IN) != 0:
        _ = library.call["deflateEnd", Int32](stream_ptr)
        raise Error("zlib deflate left input")
    status = library.call["deflate", Int32](stream_ptr, Int32(_Z_FINISH))
    var produced = Int(_load_u64(stream, _TOTAL_OUT))
    _ = library.call["deflateEnd", Int32](stream_ptr)
    if status != _Z_STREAM_END:
        raise Error("zlib deflate finish failed: " + String(status))
    out.resize(produced, 0)
    return out^
