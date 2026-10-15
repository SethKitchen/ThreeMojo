# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""ZIP archives written byte for byte as CPython 3.12's `zipfile` writes them.

A CARLA package is published by its SHA-256 sum, so the tool that zips it
must write the bytes that `zipfile.ZipFile(path, "w").writestr(info, data)`
writes on Linux or macOS: the same headers, attributes and order. A member
is stored, or deflated by the system zlib at its default level, as
`zlib.compressobj(-1, DEFLATED, -15)` deflates it.

`zipfile` writes each local header twice, first with a zero CRC and zero
sizes, then again with the real ones; the archive ends with the second.
A member keeps the `?rw-------` permissions that `zipfile` gives one whose
attributes are zero, and a name that is not ASCII is UTF-8 with flag bit
11. This writer refuses what would need ZIP64: a member of 2 GiB / 1.05 or
more, more than 65,535 members, or an offset past 2 GiB.

`read_directory` and `read_member` read an archive as `zipfile` reads it:
a name is UTF-8 when flag bit 11 says so and code page 437 otherwise, a
later member of the same name wins, and a member's CRC-32 is checked when
the member is read. The system zlib expands a deflated member. These
readers refuse a ZIP64 archive.
"""

from std.ffi import OwnedDLHandle
from std.sys import CompilationTarget

from tools._owned_process import c_text
from tools._python_json import py_repr
from tools._zlib import compress, crc32

comptime ZIP64_LIMIT = (1 << 31) - 1
"""Past this size or offset, `zipfile` writes ZIP64 records."""


@fieldwise_init
struct ZipMember(Copyable, Movable):
    """One member to write: its name and its bytes."""

    var name: String
    """The name in the archive, with `/` between folders."""
    var data: List[UInt8]
    """The bytes."""


@fieldwise_init
struct DosTime(ImplicitlyCopyable, Movable):
    """A `ZipInfo.date_time`: year, month, day, hour, minute, second."""

    var year: Int
    """The year, 1980 or later."""
    var month: Int
    """The month, 1 to 12."""
    var day: Int
    """The day of the month."""
    var hour: Int
    """The hour."""
    var minute: Int
    """The minute."""
    var second: Int
    """The second; the archive keeps it to two seconds."""


def _put16(mut out: List[UInt8], value: Int):
    """Append a little-endian 16-bit value."""
    out.append(UInt8(value & 0xFF))
    out.append(UInt8((value >> 8) & 0xFF))


def _put32(mut out: List[UInt8], value: Int):
    """Append a little-endian 32-bit value."""
    _put16(out, value & 0xFFFF)
    _put16(out, (value >> 16) & 0xFFFF)


def raw_deflate(data: List[UInt8]) raises -> List[UInt8]:
    """Return a raw DEFLATE stream at zlib's default level.

    The zlib stream of `compress2` at level 6 holds the same DEFLATE blocks
    that a raw stream at level -1 holds; this strips its two-byte header
    and its Adler-32 trailer.

    Args:
        data: The bytes.

    Returns:
        The raw stream.

    Raises:
        Error: If zlib cannot be loaded or fails.
    """
    var stream = compress(data, 6)
    var out = List[UInt8](capacity=len(stream) - 6)
    for index in range(2, len(stream) - 4):
        out.append(stream[index])
    return out^


def _is_ascii(name: String) -> Bool:
    """Return whether a name is ASCII."""
    for byte in name.as_bytes():
        if byte >= 0x80:
            return False
    return True


def python_zip(
    members: List[ZipMember], date: DosTime, deflated: Bool
) raises -> List[UInt8]:
    """Return the archive `zipfile` writes for these members.

    Args:
        members: The members, in order.
        date: Every member's `date_time`.
        deflated: True for `ZIP_DEFLATED`, False for `ZIP_STORED`.

    Returns:
        The archive's bytes.

    Raises:
        Error: `LargeZipFile` text for an archive that needs ZIP64, or
            `ValueError` text for a date before 1980.
    """
    if date.year < 1980:
        raise Error("ValueError: ZIP does not support timestamps before 1980")
    if len(members) > 0xFFFF:
        raise Error(
            "zipfile.LargeZipFile: Files count would require ZIP64 extensions"
        )
    var dosdate = ((date.year - 1980) << 9) | (date.month << 5) | date.day
    var dostime = (date.hour << 11) | (date.minute << 5) | (date.second // 2)
    var method = 8 if deflated else 0
    var out = List[UInt8]()
    var directory = List[UInt8]()
    for member in members:
        var size = len(member.data)
        if Float64(size) * 1.05 > Float64(ZIP64_LIMIT):
            raise Error(
                "zipfile.LargeZipFile: Filesize would require ZIP64 extensions"
            )
        var offset = len(out)
        if offset > ZIP64_LIMIT:
            raise Error(
                "zipfile.LargeZipFile: Central directory offset would require"
                " ZIP64 extensions"
            )
        var packed = raw_deflate(
            member.data
        ) if deflated else member.data.copy()
        var crc = Int(crc32(member.data))
        var name = member.name.as_bytes()
        var flags = 0 if _is_ascii(member.name) else 0x800
        # The local header, as `zipfile` rewrites it after the data.
        _put32(out, 0x04034B50)
        out.append(20)
        out.append(0)
        _put16(out, flags)
        _put16(out, method)
        _put16(out, dostime)
        _put16(out, dosdate)
        _put32(out, crc)
        _put32(out, len(packed))
        _put32(out, size)
        _put16(out, len(name))
        _put16(out, 0)
        out.extend(Span(name))
        out.extend(packed^)
        # Its central directory record.
        _put32(directory, 0x02014B50)
        directory.append(20)
        directory.append(3)
        directory.append(20)
        directory.append(0)
        _put16(directory, flags)
        _put16(directory, method)
        _put16(directory, dostime)
        _put16(directory, dosdate)
        _put32(directory, crc)
        _put32(directory, len(out) - offset - 30 - len(name))
        _put32(directory, size)
        _put16(directory, len(name))
        _put16(directory, 0)
        _put16(directory, 0)
        _put16(directory, 0)
        _put16(directory, 0)
        _put32(directory, 0o600 << 16)
        _put32(directory, offset)
        directory.extend(Span(name))
    var start = len(out)
    if start > ZIP64_LIMIT:
        raise Error(
            "zipfile.LargeZipFile: Central directory offset would require"
            " ZIP64 extensions"
        )
    out.extend(directory^)
    var size = len(out) - start
    _put32(out, 0x06054B50)
    _put16(out, 0)
    _put16(out, 0)
    _put16(out, len(members))
    _put16(out, len(members))
    _put32(out, size)
    _put32(out, start)
    _put16(out, 0)
    return out^


# --- Reading ---------------------------------------------------------------------------


comptime _CP437: List[Int] = [
    199,
    252,
    233,
    226,
    228,
    224,
    229,
    231,
    234,
    235,
    232,
    239,
    238,
    236,
    196,
    197,
    201,
    230,
    198,
    244,
    246,
    242,
    251,
    249,
    255,
    214,
    220,
    162,
    163,
    165,
    8359,
    402,
    225,
    237,
    243,
    250,
    241,
    209,
    170,
    186,
    191,
    8976,
    172,
    189,
    188,
    161,
    171,
    187,
    9617,
    9618,
    9619,
    9474,
    9508,
    9569,
    9570,
    9558,
    9557,
    9571,
    9553,
    9559,
    9565,
    9564,
    9563,
    9488,
    9492,
    9524,
    9516,
    9500,
    9472,
    9532,
    9566,
    9567,
    9562,
    9556,
    9577,
    9574,
    9568,
    9552,
    9580,
    9575,
    9576,
    9572,
    9573,
    9561,
    9560,
    9554,
    9555,
    9579,
    9578,
    9496,
    9484,
    9608,
    9604,
    9612,
    9616,
    9600,
    945,
    223,
    915,
    960,
    931,
    963,
    181,
    964,
    934,
    920,
    937,
    948,
    8734,
    966,
    949,
    8745,
    8801,
    177,
    8805,
    8804,
    8992,
    8993,
    247,
    8776,
    176,
    8729,
    183,
    8730,
    8319,
    178,
    9632,
    160,
]
"""Code page 437's characters for the bytes 0x80 to 0xFF."""

comptime _Z_STREAM_BYTES = 112
"""The size of zlib's `z_stream` on a 64-bit platform."""


@fieldwise_init
struct ZipItem(Copyable, Movable):
    """One member of an archive, as its central directory lists it."""

    var name: String
    """The name, decoded as `zipfile` decodes it."""
    var flags: Int
    """The general purpose flags."""
    var method: Int
    """The compression method."""
    var crc: Int
    """The CRC-32 of the expanded bytes."""
    var packed: Int
    """The size of the stored bytes."""
    var size: Int
    """The size of the expanded bytes."""
    var offset: Int
    """Where its local header starts."""


def _bad(text: String) -> Error:
    """Return a `zipfile.BadZipFile` error."""
    return Error("zipfile.BadZipFile: " + text)


def _get16(data: Span[UInt8, _], at: Int) -> Int:
    """Return the little-endian 16-bit value at `at`."""
    return Int(data[at]) | (Int(data[at + 1]) << 8)


def _get32(data: Span[UInt8, _], at: Int) -> Int:
    """Return the little-endian 32-bit value at `at`."""
    return _get16(data, at) | (_get16(data, at + 2) << 16)


def _decode_name(data: Span[UInt8, _], utf8: Bool) -> String:
    """Decode a member name as UTF-8 or as code page 437."""
    if utf8:
        return String(from_utf8_lossy=data)
    var out = String()
    for byte in data:
        if byte < 0x80:
            out += chr(Int(byte))
        else:
            out += chr(materialize[_CP437]()[Int(byte) - 0x80])
    return out^


def _end_record(data: Span[UInt8, _]) raises -> Int:
    """Return where the end of central directory record starts."""
    var size = len(data)
    if (
        size >= 22
        and _get32(data, size - 22) == 0x06054B50
        and data[size - 2] == 0
        and data[size - 1] == 0
    ):
        return size - 22
    var first = max(size - 65535 - 22, 0)
    var at = size - 4
    while at >= first:
        if _get32(data, at) == 0x06054B50:
            if at + 22 > size:
                raise _bad("File is not a zip file")
            return at
        at -= 1
    raise _bad("File is not a zip file")


def read_directory(data: Span[UInt8, _]) raises -> List[ZipItem]:
    """Read an archive's central directory, as `zipfile.ZipFile` does.

    Args:
        data: The whole archive.

    Returns:
        Each member, in directory order.

    Raises:
        Error: `zipfile.BadZipFile` text for a damaged archive, or for a
            ZIP64 archive, which this reader refuses.
    """
    var end = _end_record(data)
    if end >= 20 and _get32(data, end - 20) == 0x07064B50:
        raise _bad("a ZIP64 archive is not read by this tool")
    var size_cd = _get32(data, end + 12)
    var offset_cd = _get32(data, end + 16)
    var concat = end - size_cd - offset_cd
    var start = offset_cd + concat
    if start < 0:
        raise _bad("Bad offset for central directory")
    var items = List[ZipItem]()
    var at = start
    var total = 0
    while total < size_cd:
        if at + 46 > len(data) or at + 46 > start + size_cd:
            raise _bad("Truncated central directory")
        if _get32(data, at) != 0x02014B50:
            raise _bad("Bad magic number for central directory")
        var flags = _get16(data, at + 8)
        var name_length = _get16(data, at + 28)
        var extra_length = _get16(data, at + 30)
        var comment_length = _get16(data, at + 32)
        var name_end = min(at + 46 + name_length, len(data))
        var name = _decode_name(data[at + 46 : name_end], flags & 0x800 != 0)
        items.append(
            ZipItem(
                name,
                flags,
                _get16(data, at + 10),
                _get32(data, at + 16),
                _get32(data, at + 20),
                _get32(data, at + 24),
                _get32(data, at + 42) + concat,
            )
        )
        var step = 46 + name_length + extra_length + comment_length
        at += step
        total += step
    return items^


def _inflate(packed: Span[UInt8, _], size: Int) raises -> List[UInt8]:
    """Expand a raw DEFLATE stream with the system zlib."""
    var library = _zlib()
    var stream = List[UInt8](length=_Z_STREAM_BYTES, fill=0)
    var out = List[UInt8](length=max(size, 1), fill=0)
    var version: List[UInt8] = [0x31, 0x2E, 0x32, 0x2E, 0x31, 0x31, 0]
    var base = Int(stream.unsafe_ptr())
    var status = library.call["inflateInit2_", Int32](
        OpaquePointer[MutAnyOrigin](unsafe_from_address=base),
        Int32(-15),
        OpaquePointer[MutAnyOrigin](
            unsafe_from_address=Int(version.unsafe_ptr())
        ),
        Int32(_Z_STREAM_BYTES),
    )
    if status != 0:
        raise Error("zlib inflateInit2 failed: " + String(status))
    _put_address(stream, 0, Int(packed.unsafe_ptr()))
    _put_word(stream, 8, len(packed))
    _put_address(stream, 24, Int(out.unsafe_ptr()))
    _put_word(stream, 32, len(out))
    status = library.call["inflate", Int32](
        OpaquePointer[MutAnyOrigin](unsafe_from_address=base), Int32(4)
    )
    var produced = len(out) - _get32(Span(stream), 32)
    var message = c_text(
        Int(_get32(Span(stream), 48)) | (Int(_get32(Span(stream), 52)) << 32)
    )
    _ = library.call["inflateEnd", Int32](
        OpaquePointer[MutAnyOrigin](unsafe_from_address=base)
    )
    if status != 1 and status != 0 and status != -5:
        var text = (
            "zlib.error: Error " + String(status) + " while decompressing data"
        )
        if message:
            text += ": " + message
        raise Error(text)
    out.resize(produced, 0)
    return out^


def _put_word(mut buffer: List[UInt8], at: Int, value: Int):
    """Write a 32-bit value into a structure."""
    for index in range(4):
        buffer[at + index] = UInt8((value >> (8 * index)) & 0xFF)


def _put_address(mut buffer: List[UInt8], at: Int, value: Int):
    """Write a 64-bit address into a structure."""
    for index in range(8):
        buffer[at + index] = UInt8((value >> (8 * index)) & 0xFF)


def open_member(data: Span[UInt8, _], item: ZipItem) raises -> Int:
    """Check a member's local header, as `ZipFile.open` does.

    Args:
        data: The whole archive.
        item: The member.

    Returns:
        Where its stored bytes start.

    Raises:
        Error: `zipfile.BadZipFile` text for a damaged header, or Python's
            error for an encrypted member or another compression method.
    """
    var at = item.offset
    if at < 0 or at + 30 > len(data):
        raise _bad("Truncated file header")
    if _get32(data, at) != 0x04034B50:
        raise _bad("Bad magic number for file header")
    var name_length = _get16(data, at + 26)
    var extra_length = _get16(data, at + 28)
    var local_flags = _get16(data, at + 6)
    var name_end = min(at + 30 + name_length, len(data))
    var local = _decode_name(data[at + 30 : name_end], local_flags & 0x800 != 0)
    if local != item.name:
        raise _bad(
            "File name in directory "
            + _repr(item.name)
            + " and header "
            + _repr(local)
            + " differ."
        )
    if item.flags & 1:
        raise Error(
            "RuntimeError: File "
            + _repr(item.name)
            + " is encrypted, password required for extraction"
        )
    if item.method != 0 and item.method != 8:
        raise Error(
            "NotImplementedError: That compression method is not supported"
        )
    return at + 30 + name_length + extra_length


def read_member(data: Span[UInt8, _], item: ZipItem) raises -> List[UInt8]:
    """Return a member's expanded bytes, as `ZipFile.open(...).read()` does.

    Args:
        data: The whole archive.
        item: The member.

    Returns:
        Its bytes.

    Raises:
        Error: `zipfile.BadZipFile` text for a damaged header or a bad
            CRC-32, `zlib.error` text for a damaged stream, or Python's
            error for an encrypted member or another compression method.
    """
    var start = open_member(data, item)
    var stop = min(start + item.packed, len(data))
    var out: List[UInt8]
    if item.method == 0:
        out = List[UInt8](data[start:stop])
    else:
        out = _inflate(data[start:stop], item.size)
    if Int(crc32(out)) != item.crc:
        raise _bad("Bad CRC-32 for file " + _repr(item.name))
    return out^


def _repr(text: String) -> String:
    """Return a name as `repr` writes it."""
    return py_repr(text)


def _zlib() raises -> OwnedDLHandle:
    """Open the system zlib."""
    comptime if CompilationTarget.is_macos():
        return OwnedDLHandle("libz.1.dylib")
    else:
        return OwnedDLHandle("libz.so.1")
