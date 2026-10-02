# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""ZIP archives, the part three.js reads with `fflate.unzipSync`.

A 3MF file is a ZIP archive, and three.js's `3MFLoader` opens it with
fflate. `unzip` reads an archive's bytes into its entries, each a name
and its expanded bytes, in the order the central directory lists them.

**How it is read.** The end of central directory record is found by
searching back from the end of the file, past a comment of up to 65,535
bytes. Its central directory is read entry by entry. Each entry's data
starts after its local header, whose name and extra field lengths are
read from the local header itself, as fflate reads them. A `STORED`
entry is copied, and a `DEFLATED` one is expanded by `render.inflate`, up
to its declared size and not past it.

**Where this is stricter than fflate.** fflate does not check an entry's
CRC-32, and it reads past a size that does not match. This refuses an
entry whose expanded size or CRC-32 is not what the directory declares.
It refuses an encrypted entry, a compression method other than stored
and deflated, a ZIP64 archive, and an archive split across disks, which
fflate either refuses or reads wrongly. A name is read as UTF-8, as
fflate reads a name whose flag says so. Invalid UTF-8 bytes become
replacement characters.

**Writing.** `zip_archive` writes entries stored as they are, with no
compression, as fflate's `zipSync` writes them at level zero. It can pad
each entry so its data starts on a boundary, which a USDZ file needs. It
does not write ZIP64, so an archive must stay under 4 GiB. It checks all
field lengths before it allocates or writes the archive.
"""

from render.checksum import crc32
from render.inflate import inflate


@fieldwise_init
struct ZipMethod(Equatable, ImplicitlyCopyable, Writable):
    """How an entry's bytes are stored, as a type rather than a bare int.

    The value is the method number the archive stores. `unzip` refuses
    every method but `ZIP_STORED` and `ZIP_DEFLATED`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for the two methods this reader expands."""
        return self == ZIP_STORED or self == ZIP_DEFLATED


# Method 0: the bytes as they are.
comptime ZIP_STORED = ZipMethod(0)
# Method 8: DEFLATE, RFC 1951.
comptime ZIP_DEFLATED = ZipMethod(8)

# The signatures of the records read.
comptime _LOCAL_HEADER = 0x04034B50
comptime _CENTRAL_HEADER = 0x02014B50
comptime _END_OF_DIRECTORY = 0x06054B50
comptime _DIGITAL_SIGNATURE = 0x05054B50
# The fixed lengths of those records.
comptime _LOCAL_LENGTH = 30
comptime _CENTRAL_LENGTH = 46
comptime _END_LENGTH = 22
comptime _DIGITAL_LENGTH = 6


@fieldwise_init
struct ZipEntry(Copyable, Movable):
    """One file of an archive: its name and its expanded bytes."""

    # The name as the archive stores it, with `/` between folders.
    var name: String
    # How it was stored.
    var method: ZipMethod
    # The expanded bytes. A folder's entry has none.
    var data: List[UInt8]


def _u16(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian 16-bit value at `at`."""
    return Int(bytes[at]) | (Int(bytes[at + 1]) << 8)


def _u32(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian 32-bit value at `at`."""
    return _u16(bytes, at) | (_u16(bytes, at + 2) << 16)


def _need(end: Int, at: Int, length: Int, what: String) raises:
    """Refuse a record that runs past its containing region.

    Args:
        end: The end of the containing region.
        at: Where the record starts.
        length: How long it is.
        what: What it is, for the error.

    Raises:
        Error: If it runs past the end.
    """
    if at + length > end:
        raise Error("ZIP: the archive ends inside " + what)


def _directory_shape(
    bytes: List[UInt8], start: Int, mut shapes: Dict[Int, Tuple[Int, Int, Int]]
) raises -> Tuple[Int, Int, Int]:
    """Return terminal offset, file count and required local-data end.

    A negative count marks a malformed chain. Each visited offset is cached,
    including terminal and invalid records. Candidate directories can share
    suffixes without scanning those records again. Use the cache only with
    the same unchanged archive. Successors move forward, so this uses a path
    stack rather than recursion.
    """
    var path = List[Tuple[Int, Int]]()
    var at = start
    while at not in shapes:
        if at + 4 > len(bytes) or _u32(bytes, at) != _CENTRAL_HEADER:
            shapes[at] = (at, 0, 0)
            break
        if at + _CENTRAL_LENGTH > len(bytes):
            shapes[at] = (-1, -1, 0)
            break
        var next = (
            at
            + _CENTRAL_LENGTH
            + _u16(bytes, at + 28)
            + _u16(bytes, at + 30)
            + _u16(bytes, at + 32)
        )
        if next > len(bytes):
            shapes[at] = (-1, -1, 0)
            break
        var local = _u32(bytes, at + 42)
        if local + _LOCAL_LENGTH > len(bytes):
            shapes[at] = (-1, -1, 0)
            break
        if _u32(bytes, local) != _LOCAL_HEADER:
            shapes[at] = (-1, -1, 0)
            break
        var local_end = (
            local
            + _LOCAL_LENGTH
            + _u16(bytes, local + 26)
            + _u16(bytes, local + 28)
            + _u32(bytes, at + 20)
        )
        if local_end > len(bytes):
            shapes[at] = (-1, -1, 0)
            break
        path.append((at, local_end))
        at = next
    var shape = shapes[at]
    for index in range(len(path) - 1, -1, -1):
        if shape[1] >= 0:
            shape = (shape[0], shape[1] + 1, max(shape[2], path[index][1]))
        shapes[path[index][0]] = shape
    return shape


def _directory_candidate(
    bytes: List[UInt8], end: Int, mut shapes: Dict[Int, Tuple[Int, Int, Int]]
) raises -> Bool:
    """Check a classic EOCD's central-record count and complete extent."""
    var count = _u16(bytes, end + 10)
    if _u16(bytes, end + 4) != 0 or _u16(bytes, end + 6) != 0:
        return False
    if count == 0xFFFF or _u16(bytes, end + 8) != count:
        return False
    var start = _u32(bytes, end + 16)
    var size = _u32(bytes, end + 12)
    if start == 0xFFFFFFFF or size == 0xFFFFFFFF:
        return False
    if start + size != end:
        return False
    if count > size // _CENTRAL_LENGTH:
        return False
    var shape = _directory_shape(bytes, start, shapes)
    if shape[1] != count:
        return False
    if shape[2] > start:
        return False
    var at = shape[0]
    if at == end:
        return True
    if at + _DIGITAL_LENGTH > end:
        return False
    if _u32(bytes, at) != _DIGITAL_SIGNATURE:
        return False
    return at + _DIGITAL_LENGTH + _u16(bytes, at + 4) == end


def _end_of_directory(bytes: List[UInt8]) raises -> Int:
    """Return where the end of central directory record starts.

    Args:
        bytes: The archive.

    Returns:
        The last structurally admissible candidate's offset. Competing
        complete layouts cannot identify the writer's intent. If none is
        admissible, return a comment-shaped candidate for a precise error.

    Raises:
        Error: If no record is found within the last 65,557 bytes.
    """
    var at = len(bytes) - _END_LENGTH
    var stop = max(0, at - 65535)
    var candidate = -1
    var shapes = Dict[Int, Tuple[Int, Int, Int]]()
    while at >= stop:
        if _u32(bytes, at) == _END_OF_DIRECTORY:
            if at + _END_LENGTH + _u16(bytes, at + 20) == len(bytes):
                # Keep malformed or unsupported records for unzip's precise
                # error, but prefer a complete structural directory layout.
                if candidate < 0:
                    candidate = at
                if _directory_candidate(bytes, at, shapes):
                    return at
        at -= 1
    if candidate >= 0:
        return candidate
    raise Error("ZIP: no end of central directory record")


def unzip(bytes: List[UInt8]) raises -> List[ZipEntry]:
    """Read every entry of a ZIP archive.

    Args:
        bytes: The whole archive.

    Returns:
        The entries, in central directory order.

    Raises:
        Error: If the archive has no end record, is ZIP64 or split, a
            record runs past the end or has the wrong signature, an entry
            is encrypted or uses another method, or an entry's data does
            not expand to its declared size and CRC-32.
    """
    var end = _end_of_directory(bytes)
    var disk = _u16(bytes, end + 4)
    var directory_disk = _u16(bytes, end + 6)
    if disk != 0 or directory_disk != 0:
        raise Error("ZIP: an archive split across disks is not read")
    var disk_count = _u16(bytes, end + 8)
    var count = _u16(bytes, end + 10)
    var directory_size = _u32(bytes, end + 12)
    var at = _u32(bytes, end + 16)
    if disk_count == 0xFFFF or count == 0xFFFF:
        raise Error("ZIP: a ZIP64 archive is not read")
    if directory_size == 0xFFFFFFFF or at == 0xFFFFFFFF:
        raise Error("ZIP: a ZIP64 archive is not read")
    if disk_count != count:
        raise Error(
            "ZIP: different entry counts in an archive split across disks"
        )
    var directory_start = at
    _need(end, at, directory_size, "central directory entry 0")
    var directory_end = at + directory_size
    if directory_end != end:
        raise Error("ZIP: the central directory does not end at its end record")
    var entries = List[ZipEntry]()
    for index in range(count):
        var what = "central directory entry " + String(index)
        _need(directory_end, at, _CENTRAL_LENGTH, what)
        if _u32(bytes, at) != _CENTRAL_HEADER:
            raise Error("ZIP: a " + what + " has the wrong signature")
        var flags = _u16(bytes, at + 8)
        var method = ZipMethod(_u16(bytes, at + 10))
        var crc = _u32(bytes, at + 16)
        var packed = _u32(bytes, at + 20)
        var size = _u32(bytes, at + 24)
        var name_length = _u16(bytes, at + 28)
        var extra_length = _u16(bytes, at + 30)
        var comment_length = _u16(bytes, at + 32)
        var entry_disk = _u16(bytes, at + 34)
        var local = _u32(bytes, at + 42)
        _need(
            directory_end,
            at + _CENTRAL_LENGTH,
            name_length + extra_length + comment_length,
            what,
        )
        var name = String(
            from_utf8_lossy=Span(
                List[UInt8](
                    bytes[
                        at
                        + _CENTRAL_LENGTH : at
                        + _CENTRAL_LENGTH
                        + name_length
                    ]
                )
            )
        )
        what = "entry `" + name + "`"
        if packed == 0xFFFFFFFF or size == 0xFFFFFFFF:
            raise Error("ZIP: a ZIP64 " + what + " is not read")
        if local == 0xFFFFFFFF or entry_disk == 0xFFFF:
            raise Error("ZIP: a ZIP64 " + what + " is not read")
        if entry_disk != 0:
            raise Error("ZIP: an archive split across disks is not read")
        if flags & 1 == 1:
            raise Error("ZIP: an encrypted " + what + " is not read")
        if not method.is_valid():
            raise Error(
                "ZIP: "
                + what
                + " uses compression method "
                + String(method.value)
                + ", and only stored and deflated are read"
            )
        _need(directory_start, local, _LOCAL_LENGTH, what)
        if _u32(bytes, local) != _LOCAL_HEADER:
            raise Error("ZIP: the local header of " + what + " is not one")
        var start = (
            local
            + _LOCAL_LENGTH
            + _u16(bytes, local + 26)
            + _u16(bytes, local + 28)
        )
        _need(directory_start, start, packed, what)
        var data: List[UInt8]
        if method == ZIP_STORED:
            data = List[UInt8](bytes[start : start + packed])
        else:
            data = inflate(List[UInt8](bytes[start : start + packed]), 0, size)
        if len(data) != size:
            raise Error(
                "ZIP: "
                + what
                + " expands to "
                + String(len(data))
                + " bytes, and the directory declares "
                + String(size)
            )
        if Int(crc32(data)) != crc:
            raise Error("ZIP: " + what + " does not match its CRC-32")
        entries.append(ZipEntry(name, method, data^))
        at += _CENTRAL_LENGTH + name_length + extra_length + comment_length
    if at != directory_end:
        # APPNOTE 4.3.12 permits one signature after the directory entries.
        # Preserve this record without claiming to authenticate its contents.
        _need(
            directory_end,
            at,
            _DIGITAL_LENGTH,
            "central directory digital signature",
        )
        if _u32(bytes, at) != _DIGITAL_SIGNATURE:
            raise Error(
                "ZIP: the central directory size does not match its entry count"
            )
        at += _DIGITAL_LENGTH + _u16(bytes, at + 4)
        _need(directory_end, at, 0, "central directory digital signature")
        if at != directory_end:
            raise Error(
                "ZIP: bytes follow the central directory digital signature"
            )
    return entries^


def _put16(mut out: List[UInt8], value: Int):
    """Append a little-endian 16-bit value."""
    out.append(UInt8(value & 0xFF))
    out.append(UInt8((value >> 8) & 0xFF))


def _put32(mut out: List[UInt8], value: Int):
    """Append a little-endian 32-bit value."""
    _put16(out, value & 0xFFFF)
    _put16(out, (value >> 16) & 0xFFFF)


def _write_length(value: Int, limit: Int, what: String) raises:
    """Refuse a negative or unrepresentable writer length before arithmetic."""
    if value < 0 or value >= limit:
        raise Error(
            "ZIP: " + what + " is too long or needs ZIP64: " + String(value)
        )


def _archive_length(count: Int, local: Int, directory: Int) raises -> Int:
    """Check bounded lengths and return the complete non-ZIP64 archive size.

    This helper checks numeric limits without allocating a large archive.
    The 16-bit count and 32-bit size sentinels are reserved for ZIP64.
    The complete archive, including its end record, must stay below 4 GiB.
    """
    _write_length(count, 0xFFFF, "entry count")
    _write_length(local, 0xFFFFFFFF, "local data size")
    _write_length(directory, 0xFFFFFFFF, "central directory size")
    var total = local + directory + _END_LENGTH
    _write_length(total, 0x100000000, "archive size")
    return total


def _entry_layout(
    name: Int, size: Int, offset: Int, directory: Int, align: Int
) raises -> Tuple[Int, Int, Int]:
    """Check one entry's lengths and return local end, directory end and pad.

    The caller checks that align is positive. Each input length is checked
    before sums are evaluated. Padding must fit the 16-bit extra field.
    """
    _write_length(name, 0x10000, "name")
    _write_length(size, 0xFFFFFFFF, "entry size")
    _ = _archive_length(0, offset, directory)
    var header_end = offset + _LOCAL_LENGTH + name
    var pad = (align - header_end % align) % align
    _write_length(pad, 0x10000, "extra field padding")
    var local_end = header_end + pad + size
    var directory_end = directory + _CENTRAL_LENGTH + name
    _ = _archive_length(0, local_end, directory_end)
    return local_end, directory_end, pad


def zip_archive(entries: List[ZipEntry], align: Int = 1) raises -> List[UInt8]:
    """Write entries into a ZIP archive, each one stored as it is.

    This is the archive fflate's `zipSync` writes at level zero. With
    `align` above one, each local header's extra field is padded so that
    the entry's data starts at a multiple of `align`, as three.js's
    `USDZExporter` pads its files to 64 bytes.

    Args:
        entries: The names and bytes, in order. Each must be `ZIP_STORED`.
        align: What each entry's data offset must be a multiple of.

    Returns:
        The archive.

    Raises:
        Error: If an entry is not stored, `align` is below one, a field
            does not fit its non-ZIP64 representation, or the complete
            archive is 4 GiB or larger.
    """
    if align < 1:
        raise Error("ZIP: an alignment must be one or more")
    _ = _archive_length(len(entries), 0, 0)
    var local_length = 0
    var directory_length = 0
    for entry in entries:
        if entry.method != ZIP_STORED:
            raise Error(
                "ZIP: only a stored entry can be written: `" + entry.name + "`"
            )
        var layout = _entry_layout(
            len(entry.name.as_bytes()),
            len(entry.data),
            local_length,
            directory_length,
            align,
        )
        local_length = layout[0]
        directory_length = layout[1]
    var out = List[UInt8]()
    var directory = List[UInt8]()
    for entry in entries:
        var name = entry.name.as_bytes()
        var offset = len(out)
        var pad = (align - (offset + _LOCAL_LENGTH + len(name)) % align) % align
        var crc = Int(crc32(entry.data))
        var size = len(entry.data)
        _put32(out, _LOCAL_HEADER)
        _put16(out, 20)
        _put16(out, 0x0800)
        _put16(out, ZIP_STORED.value)
        _put32(out, 0)
        _put32(out, crc)
        _put32(out, size)
        _put32(out, size)
        _put16(out, len(name))
        _put16(out, pad)
        out.extend(List[UInt8](name))
        for _ in range(pad):
            out.append(0)
        out.extend(entry.data.copy())
        _put32(directory, _CENTRAL_HEADER)
        _put16(directory, 20)
        _put16(directory, 20)
        _put16(directory, 0x0800)
        _put16(directory, ZIP_STORED.value)
        _put32(directory, 0)
        _put32(directory, crc)
        _put32(directory, size)
        _put32(directory, size)
        _put16(directory, len(name))
        _put32(directory, 0)
        _put32(directory, 0)
        _put32(directory, 0)
        _put32(directory, offset)
        directory.extend(List[UInt8](name))
    var start = len(out)
    out.extend(directory^)
    _put32(out, _END_OF_DIRECTORY)
    _put32(out, 0)
    _put16(out, len(entries))
    _put16(out, len(entries))
    _put32(out, len(out) - start - 12)
    _put32(out, start)
    _put16(out, 0)
    return out^
