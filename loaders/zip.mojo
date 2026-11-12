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
and deflated, and an archive split across disks, which fflate either
refuses or reads wrongly. A name is read as UTF-8, as fflate reads a
name whose flag says so. Invalid UTF-8 bytes become replacement
characters.

**ZIP64.** An end record with a field at its largest value names a ZIP64
end record, which holds the entry count and the directory's size and
place in 64 bits. Its locator sits just before the end record, and the
central directory ends where the ZIP64 record starts. An entry with a
size or an offset at its largest value holds the real one in its ZIP64
extra field, in the order the format gives: size, compressed size,
offset. Some writers use these records for every archive, small ones
too: two of the seven 3MF files three.js ships are such archives.
fflate reads all three values of the extra field whichever the entry
asks for; this reads the ones it asks for.

**Writing.** `zip_archive` writes entries stored as they are, with no
compression, as fflate's `zipSync` writes them at level zero. It can pad
each entry so its data starts on a boundary, which a USDZ file needs. It
does not write ZIP64, so an archive must stay under 4 GiB. It checks all
field lengths before it allocates or writes the archive.
"""

from core.ordinal import index_in_count, require_positive

from core.binary import (
    append_little_endian_u16,
    append_little_endian_u32,
    copy_bytes,
    little_endian_u16,
    little_endian_u32,
    little_endian_uint,
)
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
comptime _ZIP64_END = 0x06064B50
comptime _ZIP64_LOCATOR = 0x07064B50
# The fixed lengths of those records. The ZIP64 end record's is the part
# before its extensible data.
comptime _LOCAL_LENGTH = 30
comptime _CENTRAL_LENGTH = 46
comptime _END_LENGTH = 22
comptime _DIGITAL_LENGTH = 6
comptime _ZIP64_END_LENGTH = 56
comptime _ZIP64_LOCATOR_LENGTH = 20
# The header ID of an entry's ZIP64 extra field.
comptime _ZIP64_EXTRA = 1
# What a 16-bit and a 32-bit field hold to say "see the ZIP64 record".
comptime _WIDE16 = 0xFFFF
comptime _WIDE32 = 0xFFFFFFFF


@fieldwise_init
struct ZipEntry(Copyable, Movable):
    """One file of an archive: its name and its expanded bytes."""

    # The name as the archive stores it, with `/` between folders.
    var name: String
    # How it was stored.
    var method: ZipMethod
    # The expanded bytes. A folder's entry has none.
    var data: List[UInt8]


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
    # Subtracted, not added: a ZIP64 offset can be near the largest integer.
    if length > end - at:
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
        if (
            at + 4 > len(bytes)
            or little_endian_u32(bytes, at) != _CENTRAL_HEADER
        ):
            shapes[at] = (at, 0, 0)
            break
        if at + _CENTRAL_LENGTH > len(bytes):
            shapes[at] = (-1, -1, 0)
            break
        var next = (
            at
            + _CENTRAL_LENGTH
            + little_endian_u16(bytes, at + 28)
            + little_endian_u16(bytes, at + 30)
            + little_endian_u16(bytes, at + 32)
        )
        if next > len(bytes):
            shapes[at] = (-1, -1, 0)
            break
        var local = little_endian_u32(bytes, at + 42)
        if local + _LOCAL_LENGTH > len(bytes):
            shapes[at] = (-1, -1, 0)
            break
        if little_endian_u32(bytes, local) != _LOCAL_HEADER:
            shapes[at] = (-1, -1, 0)
            break
        var local_end = (
            local
            + _LOCAL_LENGTH
            + little_endian_u16(bytes, local + 26)
            + little_endian_u16(bytes, local + 28)
            + little_endian_u32(bytes, at + 20)
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


struct _Wide(Movable):
    """What a ZIP64 end record says of the central directory."""

    # How many entries the directory holds.
    var count: Int
    # Where the directory starts, and how long it is.
    var start: Int
    var size: Int
    # Where the ZIP64 end record starts. The directory ends there.
    var record: Int
    # Empty, or why the record is refused.
    var problem: String

    def __init__(out self, problem: String):
        """Start with no directory, and a reason or none."""
        self.count = 0
        self.start = 0
        self.size = 0
        self.record = 0
        self.problem = problem


def _names_zip64(bytes: List[UInt8], end: Int) -> Bool:
    """Return True when an end record names a ZIP64 end record: one of
    its fields is at the largest value the field holds.

    Args:
        bytes: The archive.
        end: Where the end record starts. The record fits.

    Returns:
        Whether a disk number, an entry count, the directory's size or
        its offset is such a value.
    """
    # Two disk numbers and two entry counts: the loop always runs.
    for field in range(4):  # pragma: no branch
        if little_endian_u16(bytes, end + 4 + 2 * field) == _WIDE16:
            return True
    return (
        little_endian_u32(bytes, end + 12) == _WIDE32
        or little_endian_u32(bytes, end + 16) == _WIDE32
    )


def _zip64_directory(bytes: List[UInt8], end: Int) -> _Wide:
    """Read the ZIP64 end record that an end record names.

    The record's locator is the twenty bytes before the end record. The
    record must end where the locator starts, on the one disk there is,
    and the directory it names must lie before it.

    Args:
        bytes: The archive.
        end: Where the end record starts.

    Returns:
        The directory's entry count, start and size, and where the ZIP64
        end record starts; or the reason the record is refused.
    """
    var locator = end - _ZIP64_LOCATOR_LENGTH
    if locator < 0 or little_endian_u32(bytes, locator) != _ZIP64_LOCATOR:
        return _Wide("ZIP: a ZIP64 archive has no ZIP64 end record locator")
    # Eight bytes past 2^63 read as negative.
    var record = little_endian_uint(bytes, locator + 8, 8)
    if record < 0 or record > locator - _ZIP64_END_LENGTH:
        return _Wide("ZIP: a ZIP64 end record does not fit before its locator")
    if little_endian_u32(bytes, record) != _ZIP64_END:
        return _Wide("ZIP: a ZIP64 end record has the wrong signature")
    # The record's length counts the bytes after the length itself.
    if little_endian_uint(bytes, record + 4, 8) != locator - record - 12:
        return _Wide("ZIP: a ZIP64 end record does not end at its locator")
    if (
        little_endian_u32(bytes, locator + 4) != 0
        or little_endian_u32(bytes, locator + 16) > 1
        or little_endian_u32(bytes, record + 16) != 0
        or little_endian_u32(bytes, record + 20) != 0
    ):
        return _Wide("ZIP: an archive split across disks is not read")
    var wide = _Wide("")
    wide.record = record
    wide.count = little_endian_uint(bytes, record + 32, 8)
    wide.size = little_endian_uint(bytes, record + 40, 8)
    wide.start = little_endian_uint(bytes, record + 48, 8)
    if little_endian_uint(bytes, record + 24, 8) != wide.count:
        wide.problem = (
            "ZIP: different entry counts in an archive split across disks"
        )
        return wide^
    # The directory lies before the record, so each value is at most the
    # record's offset, and a sum of two of them does not wrap.
    var held = (
        index_in_count(wide.count, record + 1)
        and index_in_count(wide.size, record + 1)
        and index_in_count(wide.start, record + 1)
    )
    if not held:
        wide.problem = (
            "ZIP: a ZIP64 end record names more than the archive holds"
        )
    return wide^


def _wide_values(bytes: List[UInt8], at: Int, length: Int) -> List[Int]:
    """Return the 64-bit values of an entry's ZIP64 extra field.

    Args:
        bytes: The archive.
        at: Where the entry's extra fields start.
        length: How many bytes they take. They lie inside the directory.

    Returns:
        The values, in file order: as many whole ones as the field holds
        inside the entry's extra fields. Empty when the entry has no
        ZIP64 extra field.
    """
    var end = at + length
    var field = at
    while field + 4 <= end:
        var size = little_endian_u16(bytes, field + 2)
        if little_endian_u16(bytes, field) == _ZIP64_EXTRA:
            var values = List[Int]()
            var value = field + 4
            var stop = min(value + size, end)
            while value + 8 <= stop:
                values.append(little_endian_uint(bytes, value, 8))
                value += 8
            return values^
        field += 4 + size
    return List[Int]()


def _wide_value(wide: List[Int], index: Int, what: String) raises -> Int:
    """Return one value of an entry's ZIP64 extra field.

    Args:
        wide: What `_wide_values` gives for the entry.
        index: Which value.
        what: The entry, for the error.

    Returns:
        The value.

    Raises:
        Error: If the field does not hold that value, or the value is
            past 2^63.
    """
    if index >= len(wide):
        raise Error(
            "ZIP: a ZIP64 " + what + " does not hold its ZIP64 extra field"
        )
    if wide[index] < 0:
        raise Error("ZIP: a ZIP64 " + what + " is larger than this reads")
    return wide[index]


def _directory_candidate(
    bytes: List[UInt8], end: Int, mut shapes: Dict[Int, Tuple[Int, Int, Int]]
) raises -> Bool:
    """Check an EOCD's central-record count and complete extent."""
    if _names_zip64(bytes, end):
        # A ZIP64 end record that reads, and a directory that ends at it
        # and can hold the entries it counts.
        var wide = _zip64_directory(bytes, end)
        return (
            wide.problem == ""
            and wide.start + wide.size == wide.record
            and wide.count <= wide.size // _CENTRAL_LENGTH
        )
    var count = little_endian_u16(bytes, end + 10)
    if (
        little_endian_u16(bytes, end + 4) != 0
        or little_endian_u16(bytes, end + 6) != 0
    ):
        return False
    if little_endian_u16(bytes, end + 8) != count:
        return False
    var start = little_endian_u32(bytes, end + 16)
    var size = little_endian_u32(bytes, end + 12)
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
    if little_endian_u32(bytes, at) != _DIGITAL_SIGNATURE:
        return False
    return at + _DIGITAL_LENGTH + little_endian_u16(bytes, at + 4) == end


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
        if little_endian_u32(bytes, at) == _END_OF_DIRECTORY:
            if at + _END_LENGTH + little_endian_u16(bytes, at + 20) == len(
                bytes
            ):
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
        Error: If the archive has no end record or is split, a record
            runs past the end or has the wrong signature, a ZIP64 record
            or extra field that an end record or an entry names is not
            there, an entry is encrypted or uses another method, or an
            entry's data does not expand to its declared size and CRC-32.
    """
    var end = _end_of_directory(bytes)
    var count: Int
    var directory_size: Int
    var at: Int
    # Where the directory must end: at the end record, or at the ZIP64 end
    # record when there is one.
    var directory_limit = end
    if _names_zip64(bytes, end):
        var wide = _zip64_directory(bytes, end)
        if wide.problem:
            raise Error(wide.problem)
        count = wide.count
        directory_size = wide.size
        at = wide.start
        directory_limit = wide.record
    else:
        var disk = little_endian_u16(bytes, end + 4)
        var directory_disk = little_endian_u16(bytes, end + 6)
        if disk != 0 or directory_disk != 0:
            raise Error("ZIP: an archive split across disks is not read")
        var disk_count = little_endian_u16(bytes, end + 8)
        count = little_endian_u16(bytes, end + 10)
        directory_size = little_endian_u32(bytes, end + 12)
        at = little_endian_u32(bytes, end + 16)
        if disk_count != count:
            raise Error(
                "ZIP: different entry counts in an archive split across disks"
            )
    var directory_start = at
    _need(directory_limit, at, directory_size, "central directory entry 0")
    var directory_end = at + directory_size
    if directory_end != directory_limit:
        raise Error("ZIP: the central directory does not end at its end record")
    var entries = List[ZipEntry]()
    for index in range(count):
        var what = "central directory entry " + String(index)
        _need(directory_end, at, _CENTRAL_LENGTH, what)
        if little_endian_u32(bytes, at) != _CENTRAL_HEADER:
            raise Error("ZIP: a " + what + " has the wrong signature")
        var flags = little_endian_u16(bytes, at + 8)
        var method = ZipMethod(little_endian_u16(bytes, at + 10))
        var crc = little_endian_u32(bytes, at + 16)
        var packed = little_endian_u32(bytes, at + 20)
        var size = little_endian_u32(bytes, at + 24)
        var name_length = little_endian_u16(bytes, at + 28)
        var extra_length = little_endian_u16(bytes, at + 30)
        var comment_length = little_endian_u16(bytes, at + 32)
        var entry_disk = little_endian_u16(bytes, at + 34)
        var local = little_endian_u32(bytes, at + 42)
        _need(
            directory_end,
            at + _CENTRAL_LENGTH,
            name_length + extra_length + comment_length,
            what,
        )
        var name = String(
            from_utf8_lossy=Span(
                copy_bytes(bytes, at + _CENTRAL_LENGTH, name_length)
            )
        )
        what = "entry `" + name + "`"
        # A field at its largest value holds the real one in the entry's
        # ZIP64 extra field, in the format's order: size, compressed size,
        # offset. A disk number there names a disk past the one there is.
        var wide = _wide_values(
            bytes, at + _CENTRAL_LENGTH + name_length, extra_length
        )
        var taken = 0
        if size == _WIDE32:
            size = _wide_value(wide, taken, what)
            taken += 1
        if packed == _WIDE32:
            packed = _wide_value(wide, taken, what)
            taken += 1
        if local == _WIDE32:
            local = _wide_value(wide, taken, what)
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
        if little_endian_u32(bytes, local) != _LOCAL_HEADER:
            raise Error("ZIP: the local header of " + what + " is not one")
        var start = (
            local
            + _LOCAL_LENGTH
            + little_endian_u16(bytes, local + 26)
            + little_endian_u16(bytes, local + 28)
        )
        _need(directory_start, start, packed, what)
        var data: List[UInt8]
        if method == ZIP_STORED:
            data = copy_bytes(bytes, start, packed)
        else:
            data = inflate(copy_bytes(bytes, start, packed), 0, size)
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
        if little_endian_u32(bytes, at) != _DIGITAL_SIGNATURE:
            raise Error(
                "ZIP: the central directory size does not match its entry count"
            )
        at += _DIGITAL_LENGTH + little_endian_u16(bytes, at + 4)
        _need(directory_end, at, 0, "central directory digital signature")
        if at != directory_end:
            raise Error(
                "ZIP: bytes follow the central directory digital signature"
            )
    return entries^


def _write_length(value: Int, limit: Int, what: String) raises:
    """Refuse a negative or unrepresentable writer length before arithmetic."""
    if not index_in_count(value, limit):
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
    require_positive(align, "ZIP: an alignment must be one or more")
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
        append_little_endian_u32(out, _LOCAL_HEADER)
        append_little_endian_u16(out, 20)
        append_little_endian_u16(out, 0x0800)
        append_little_endian_u16(out, ZIP_STORED.value)
        append_little_endian_u32(out, 0)
        append_little_endian_u32(out, crc)
        append_little_endian_u32(out, size)
        append_little_endian_u32(out, size)
        append_little_endian_u16(out, len(name))
        append_little_endian_u16(out, pad)
        out.extend(name)
        for _ in range(pad):
            out.append(0)
        out.extend(Span(entry.data))
        append_little_endian_u32(directory, _CENTRAL_HEADER)
        append_little_endian_u16(directory, 20)
        append_little_endian_u16(directory, 20)
        append_little_endian_u16(directory, 0x0800)
        append_little_endian_u16(directory, ZIP_STORED.value)
        append_little_endian_u32(directory, 0)
        append_little_endian_u32(directory, crc)
        append_little_endian_u32(directory, size)
        append_little_endian_u32(directory, size)
        append_little_endian_u16(directory, len(name))
        append_little_endian_u32(directory, 0)
        append_little_endian_u32(directory, 0)
        append_little_endian_u32(directory, 0)
        append_little_endian_u32(directory, offset)
        directory.extend(name)
    var start = len(out)
    out.extend(directory^)
    append_little_endian_u32(out, _END_OF_DIRECTORY)
    append_little_endian_u32(out, 0)
    append_little_endian_u16(out, len(entries))
    append_little_endian_u16(out, len(entries))
    append_little_endian_u32(out, len(out) - start - 12)
    append_little_endian_u32(out, start)
    append_little_endian_u16(out, 0)
    return out^
