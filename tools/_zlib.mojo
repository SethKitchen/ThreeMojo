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
