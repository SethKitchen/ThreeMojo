# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.zip`.

Archives are written by `zip_archive` and read back, and then damaged
byte by byte to reach every refusal. `assets/3mf/fixture.3mf`, written by
Python's `zipfile`, is the deflated archive read.
"""

from loaders.zip import (
    ZIP_DEFLATED,
    ZIP_STORED,
    ZipEntry,
    ZipMethod,
    _archive_length,
    _directory_candidate,
    _directory_shape,
    _end_of_directory,
    _entry_layout,
    unzip,
    zip_archive,
)
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def text_bytes(text: String) -> List[UInt8]:
    """Return a text as bytes."""
    var bytes = List[UInt8]()
    for byte in text.as_bytes():
        bytes.append(byte)
    return bytes^


def stored(name: String, text: String) -> ZipEntry:
    """Return a stored entry holding a text."""
    return ZipEntry(name, ZIP_STORED, text_bytes(text))


def one() raises -> List[UInt8]:
    """Return an archive of `a.txt` holding `hello`.

    The local header is at 0, the central header at 40, and the end
    record at 91.
    """
    return zip_archive([stored("a.txt", "hello")])


def poke(mut bytes: List[UInt8], at: Int, value: Int, size: Int):
    """Overwrite a little-endian value."""
    for index in range(size):
        bytes[at + index] = UInt8((value >> (index * 8)) & 0xFF)


def refused(bytes: List[UInt8], message: String) raises:
    """Assert `unzip` refuses bytes with a message."""
    with assert_raises(contains=message):
        _ = unzip(bytes)


def test_methods_are_types() raises:
    assert_true(ZIP_STORED.is_valid())
    assert_true(ZIP_DEFLATED.is_valid())
    assert_false(ZipMethod(12).is_valid())


def test_a_written_archive_reads_back() raises:
    var entries: List[ZipEntry] = [
        stored("folder/", ""),
        stored("folder/b.txt", "bee"),
        stored("c", "sea"),
    ]
    var archive = zip_archive(entries)
    var back = unzip(archive)
    assert_equal(len(back), 3)
    for index in range(3):
        assert_equal(back[index].name, entries[index].name)
        assert_true(back[index].method == ZIP_STORED)
        assert_equal(back[index].data, entries[index].data)
    assert_equal(len(unzip(zip_archive(List[ZipEntry]()))), 0)


def test_alignment_pads_each_entry() raises:
    var archive = zip_archive([stored("x", "1"), stored("long name", "22")], 64)
    # The first entry's data follows a 30-byte header, one byte of name and
    # 33 bytes of padding.
    assert_equal(archive[64], UInt8(ord("1")))
    var back = unzip(archive)
    assert_equal(back[1].data, text_bytes("22"))
    var second = 65
    var name_end = second + 30 + 9
    var padded = name_end + (64 - name_end % 64) % 64
    assert_equal(archive[padded], UInt8(ord("2")))


def test_the_writer_refuses() raises:
    with assert_raises(contains="alignment"):
        _ = zip_archive([stored("x", "1")], 0)
    with assert_raises(contains="only a stored"):
        _ = zip_archive([ZipEntry("x", ZIP_DEFLATED, List[UInt8]())])
    with assert_raises(contains="too long"):
        _ = zip_archive([stored(String("n") * 65536, "")])


def test_a_deflated_archive_reads() raises:
    var entries = unzip(Path("assets/3mf/fixture.3mf").read_bytes())
    assert_equal(len(entries), 6)
    assert_equal(entries[0].name, "[Content_Types].xml")
    assert_true(entries[0].method == ZIP_DEFLATED)
    assert_equal(entries[4].name, "3D/Texture/")
    assert_equal(len(entries[4].data), 0)
    assert_true(entries[5].method == ZIP_STORED)
    assert_equal(entries[5].data[1], UInt8(ord("P")))
    var model = String(from_utf8=Span(entries[3].data))
    assert_true(model.startswith("<?xml"))


def test_a_comment_after_the_end_record_is_passed() raises:
    var archive = one()
    poke(archive, 91 + 20, 3, 2)
    archive.extend(text_bytes("hey"))
    assert_equal(unzip(archive)[0].data, text_bytes("hello"))


def test_end_record_refusals() raises:
    refused(List[UInt8](), "no end of central directory")
    refused(List[UInt8](length=100, fill=0), "no end of central directory")
    var split = one()
    poke(split, 95, 1, 2)
    refused(split, "split across disks")
    split = one()
    poke(split, 97, 1, 2)
    refused(split, "split across disks")
    var wide = one()
    poke(wide, 101, 0xFFFF, 2)
    refused(wide, "ZIP64 archive")
    wide = one()
    poke(wide, 107, 0xFFFFFFFF, 4)
    refused(wide, "ZIP64 archive")


def test_central_header_refusals() raises:
    var bytes = one()
    poke(bytes, 107, 80, 4)
    refused(bytes, "ends inside central directory entry 0")
    bytes = one()
    poke(bytes, 40, 0, 4)
    refused(bytes, "wrong signature")
    bytes = one()
    poke(bytes, 40 + 28, 200, 2)
    refused(bytes, "ends inside central directory entry 0")
    bytes = one()
    poke(bytes, 60, 0xFFFFFFFF, 4)
    refused(bytes, "ZIP64 entry")
    bytes = one()
    poke(bytes, 64, 0xFFFFFFFF, 4)
    refused(bytes, "ZIP64 entry")
    bytes = one()
    poke(bytes, 48, 1, 2)
    refused(bytes, "encrypted")
    bytes = one()
    poke(bytes, 50, 12, 2)
    refused(bytes, "compression method 12")


def test_local_header_and_data_refusals() raises:
    var bytes = one()
    poke(bytes, 82, 100, 4)
    refused(bytes, "ends inside entry `a.txt`")
    bytes = one()
    poke(bytes, 0, 0, 4)
    refused(bytes, "local header")
    bytes = one()
    poke(bytes, 60, 200, 4)
    refused(bytes, "ends inside entry `a.txt`")
    bytes = one()
    poke(bytes, 64, 6, 4)
    refused(bytes, "expands to 5 bytes")
    bytes = one()
    poke(bytes, 56, 0, 4)
    refused(bytes, "CRC-32")


def test_a_deflated_entry_that_expands_past_its_size_is_refused() raises:
    var bytes = Path("assets/3mf/fixture.3mf").read_bytes()
    # The first central header: find its signature after the local data.
    var at = len(bytes) - 1
    while at >= 0:
        var found = (
            bytes[at] == 0x50
            and bytes[at + 1] == 0x4B
            and bytes[at + 2] == 1
            and bytes[at + 3] == 2
        )
        if found:
            break
        at -= 1
    # The last central header is the stored PNG; step back to the first.
    var first = at
    while first >= 0:
        var found = (
            bytes[first] == 0x50
            and bytes[first + 1] == 0x4B
            and bytes[first + 2] == 1
            and bytes[first + 3] == 2
            and bytes[first + 46] == UInt8(ord("["))
        )
        if found:
            break
        first -= 1
    poke(bytes, first + 24, 3, 4)
    refused(bytes, "more than was expected")


def test_writer_field_boundaries_without_large_allocations() raises:
    assert_equal(_archive_length(0xFFFE, 0, 0), 22)
    assert_equal(_archive_length(0, 0xFFFFFFFF - 22, 0), 0xFFFFFFFF)
    assert_equal(_archive_length(0, 0, 0xFFFFFFFF - 22), 0xFFFFFFFF)
    with assert_raises(contains="entry count"):
        _ = _archive_length(0xFFFF, 0, 0)
    with assert_raises(contains="entry count"):
        _ = _archive_length(-1, 0, 0)
    with assert_raises(contains="local data size"):
        _ = _archive_length(0, 0xFFFFFFFF, 0)
    with assert_raises(contains="central directory size"):
        _ = _archive_length(0, 0, 0xFFFFFFFF)
    with assert_raises(contains="archive size"):
        _ = _archive_length(0, 0x100000000 - 22, 0)
    with assert_raises(contains="archive size"):
        _ = _archive_length(0, 0, 0x100000000 - 22)
    with assert_raises(contains="entry count"):
        _ = _archive_length(0x7FFFFFFFFFFFFFFF, 0, 0)
    with assert_raises(contains="local data size"):
        _ = _archive_length(0, 0x7FFFFFFFFFFFFFFF, 0)
    with assert_raises(contains="central directory size"):
        _ = _archive_length(0, 0, 0x7FFFFFFFFFFFFFFF)
    var maximum_name = _entry_layout(65535, 0, 0, 0, 1)
    assert_equal(maximum_name[0], 65565)
    assert_equal(maximum_name[1], 65581)
    assert_equal(maximum_name[2], 0)
    with assert_raises(contains="name"):
        _ = _entry_layout(65536, 0, 0, 0, 1)
    with assert_raises(contains="entry size"):
        _ = _entry_layout(0, 0xFFFFFFFF, 0, 0, 1)
    # These sums reach the total limit without creating any payload bytes.
    var largest = _entry_layout(0, 0xFFFFFFFF - 98, 0, 0, 1)
    assert_equal(_archive_length(1, largest[0], largest[1]), 0xFFFFFFFF)
    with assert_raises(contains="archive size"):
        _ = _entry_layout(0, 0x100000000 - 98, 0, 0, 1)
    largest = _entry_layout(0, 0, 0xFFFFFFFF - 98, 0, 1)
    assert_equal(_archive_length(1, largest[0], largest[1]), 0xFFFFFFFF)
    with assert_raises(contains="archive size"):
        _ = _entry_layout(0, 0, 0x100000000 - 98, 0, 1)
    with assert_raises(contains="local data size"):
        _ = _entry_layout(0, 0, 0xFFFFFFFF - 30, 0, 1)
    with assert_raises(contains="central directory size"):
        _ = _entry_layout(0, 0, 0, 0xFFFFFFFF - 46, 1)


def test_writer_padding_boundaries() raises:
    var layout = _entry_layout(1, 0, 0, 0, 65566)
    assert_equal(layout[2], 65535)
    with assert_raises(contains="extra field padding"):
        _ = _entry_layout(1, 0, 0, 0, 65567)
    with assert_raises(contains="extra field padding"):
        _ = zip_archive([stored("x", "123")], 70000)
    with assert_raises(contains="extra field padding"):
        _ = zip_archive([stored("x", "")], 0x7FFFFFFFFFFFFFFF)
    # Large alignment is legal when its actual padding fits the field.
    layout = _entry_layout(5000, 1, 0, 0, 70000)
    assert_equal(layout[0], 70001)
    assert_equal(layout[2], 64970)
    assert_equal(len(zip_archive(List[ZipEntry](), 70000)), 22)


def test_signatures_inside_comments_do_not_replace_the_end_record() raises:
    var empty = zip_archive(List[ZipEntry]())
    poke(empty, 20, 22, 2)
    empty.extend(List[UInt8](length=22, fill=1))
    poke(empty, 22, 0x06054B50, 4)
    assert_equal(len(unzip(empty)), 0)
    # A fake record whose comment length fits still has no matching directory.
    poke(empty, 22 + 20, 0, 2)
    assert_equal(len(unzip(empty)), 0)
    var bytes = one()
    poke(bytes, 91 + 20, 44, 2)
    bytes.extend(List[UInt8](length=44, fill=0))
    poke(bytes, 113, 0x06054B50, 4)
    poke(bytes, 113 + 20, 22, 2)
    poke(bytes, 135, 0x06054B50, 4)
    assert_equal(unzip(bytes)[0].data, text_bytes("hello"))


def test_comment_lengths_must_reach_the_archive_end() raises:
    var bytes = one()
    poke(bytes, 91 + 20, 1, 2)
    refused(bytes, "no end of central directory")
    bytes = one()
    bytes.append(0)
    refused(bytes, "no end of central directory")
    refused(List[UInt8](length=21, fill=0), "no end of central directory")
    bytes = one()
    poke(bytes, 91 + 20, 65535, 2)
    bytes.extend(List[UInt8](length=65535, fill=0))
    assert_equal(unzip(bytes)[0].data, text_bytes("hello"))
    bytes.append(0)
    refused(bytes, "no end of central directory")


def test_directory_counts_and_bounds_must_agree() raises:
    var bytes = one()
    poke(bytes, 91 + 8, 0, 2)
    refused(bytes, "split across disks")
    bytes = one()
    poke(bytes, 91 + 8, 0, 2)
    poke(bytes, 91 + 10, 0, 2)
    refused(bytes, "size does not match its entry count")
    bytes = one()
    poke(bytes, 91 + 8, 2, 2)
    poke(bytes, 91 + 10, 2, 2)
    refused(bytes, "ends inside central directory entry 1")
    bytes = one()
    poke(bytes, 91 + 12, 50, 4)
    refused(bytes, "does not end at its end record")
    bytes = one()
    poke(bytes, 91 + 12, 52, 4)
    refused(bytes, "ends inside central directory entry 0")
    bytes = one()
    poke(bytes, 91 + 16, 92, 4)
    refused(bytes, "ends inside central directory entry 0")
    bytes = one()
    poke(bytes, 91 + 8, 0xFFFF, 2)
    refused(bytes, "ZIP64 archive")
    bytes = one()
    poke(bytes, 91 + 12, 0xFFFFFFFF, 4)
    refused(bytes, "ZIP64 archive")


def test_central_extra_and_comment_fields_stay_inside_the_directory() raises:
    var original = one()
    var bytes = List[UInt8](original[:91])
    bytes.extend(text_bytes("extra"))
    bytes.extend(List[UInt8](original[91:]))
    poke(bytes, 40 + 30, 2, 2)
    poke(bytes, 40 + 32, 3, 2)
    poke(bytes, 96 + 12, 56, 4)
    assert_equal(unzip(bytes)[0].data, text_bytes("hello"))
    bytes = one()
    poke(bytes, 40 + 30, 1, 2)
    refused(bytes, "ends inside central directory entry 0")
    bytes = one()
    poke(bytes, 40 + 32, 1, 2)
    refused(bytes, "ends inside central directory entry 0")


def test_local_records_cannot_cross_into_the_directory() raises:
    var bytes = one()
    poke(bytes, 40 + 42, 40, 4)
    refused(bytes, "ends inside entry `a.txt`")
    bytes = one()
    poke(bytes, 26, 6, 2)
    refused(bytes, "ends inside entry `a.txt`")
    bytes = one()
    poke(bytes, 28, 1, 2)
    refused(bytes, "ends inside entry `a.txt`")
    bytes = one()
    poke(bytes, 40 + 20, 6, 4)
    refused(bytes, "ends inside entry `a.txt`")
    bytes = one()
    poke(bytes, 40 + 42, 0xFFFFFFFF, 4)
    refused(bytes, "ZIP64 entry")
    bytes = one()
    poke(bytes, 40 + 34, 0xFFFF, 2)
    refused(bytes, "ZIP64 entry")
    bytes = one()
    poke(bytes, 40 + 34, 1, 2)
    refused(bytes, "split across disks")


def test_invalid_utf8_names_use_replacement_characters() raises:
    var bytes = one()
    poke(bytes, 40 + 46, 0xFF, 1)
    assert_equal(unzip(bytes)[0].name, "�.txt")


def with_directory_trailer(trailer: List[UInt8]) raises -> List[UInt8]:
    """Put a record after the one-entry directory and adjust its size."""
    var original = one()
    var bytes = List[UInt8](original[:91])
    bytes.extend(trailer.copy())
    bytes.extend(List[UInt8](original[91:]))
    poke(bytes, 91 + len(trailer) + 12, 51 + len(trailer), 4)
    return bytes^


def test_a_bounded_central_directory_digital_signature_is_skipped() raises:
    # APPNOTE 4.3.12-13: a six-byte header followed by opaque signature data.
    var bytes = with_directory_trailer([0x50, 0x4B, 0x05, 0x05, 3, 0, 1, 2, 3])
    assert_equal(unzip(bytes)[0].data, text_bytes("hello"))
    bytes = with_directory_trailer([0x50, 0x4B, 0x05, 0x05, 0, 0])
    assert_equal(unzip(bytes)[0].name, "a.txt")
    # The optional record is part of the directory size, not its file count.
    poke(bytes, 97 + 8, 2, 2)
    poke(bytes, 97 + 10, 2, 2)
    refused(bytes, "ends inside central directory entry 1")


def test_the_directory_signature_must_fit_and_be_last() raises:
    refused(
        with_directory_trailer([0x50, 0x4B, 0x05, 0x05, 0]),
        "ends inside central directory digital signature",
    )
    refused(
        with_directory_trailer([0x50, 0x4B, 0x05, 0x05, 3, 0, 1, 2]),
        "ends inside central directory digital signature",
    )
    refused(
        with_directory_trailer([0x50, 0x4B, 0x05, 0x05, 0, 0, 1]),
        "bytes follow the central directory digital signature",
    )
    refused(
        with_directory_trailer(
            [
                0x50,
                0x4B,
                0x05,
                0x05,
                0,
                0,
                0x50,
                0x4B,
                0x05,
                0x05,
                0,
                0,
            ]
        ),
        "bytes follow the central directory digital signature",
    )


def fake_end(mut bytes: List[UInt8], at: Int, count: Int, start: Int):
    """Write a comment-shaped EOCD whose arithmetic extent reaches itself."""
    poke(bytes, at, 0x06054B50, 4)
    poke(bytes, at + 8, count, 2)
    poke(bytes, at + 10, count, 2)
    poke(bytes, at + 12, at - start, 4)
    poke(bytes, at + 16, start, 4)
    poke(bytes, at + 20, len(bytes) - at - 22, 2)


def test_an_impossible_coherent_comment_candidate_is_skipped() raises:
    var bytes = zip_archive(List[ZipEntry]())
    poke(bytes, 20, 22, 2)
    bytes.extend(List[UInt8](length=22, fill=0))
    fake_end(bytes, 22, 1, 22)
    assert_equal(len(unzip(bytes)), 0)
    # Matching arithmetic alone cannot count the original EOCD as directory.
    bytes = one()
    poke(bytes, 91 + 20, 22, 2)
    bytes.extend(List[UInt8](length=22, fill=0))
    fake_end(bytes, 113, 1, 40)
    assert_equal(unzip(bytes)[0].data, text_bytes("hello"))


def test_comment_candidates_must_reference_local_records() raises:
    # A complete fake central header cannot refer to the real empty EOCD
    # as though it were a local file header.
    var bytes = zip_archive(List[ZipEntry]())
    poke(bytes, 20, 68, 2)
    bytes.extend(List[UInt8](length=68, fill=0))
    poke(bytes, 22, 0x02014B50, 4)
    fake_end(bytes, 68, 1, 22)
    assert_equal(len(unzip(bytes)), 0)
    # A split-disk candidate with an empty directory is not admissible.
    bytes = zip_archive(List[ZipEntry]())
    poke(bytes, 20, 22, 2)
    bytes.extend(List[UInt8](length=22, fill=0))
    fake_end(bytes, 22, 0, 22)
    poke(bytes, 22 + 4, 1, 2)
    assert_equal(len(unzip(bytes)), 0)


def test_many_comment_candidates_reuse_one_directory_chain() raises:
    var entries = List[ZipEntry]()
    for _ in range(64):
        entries.append(stored("x", ""))
    var bytes = zip_archive(entries)
    var directory = 64 * 31
    var end = len(bytes) - 22
    poke(bytes, end + 20, 128 * 22, 2)
    bytes.extend(List[UInt8](length=128 * 22, fill=0))
    var shapes = Dict[Int, Tuple[Int, Int, Int]]()
    # Preload a suffix, then reach it from the preceding record.
    var suffix = _directory_shape(bytes, directory + 47, shapes)
    assert_equal(suffix[1], 63)
    var whole = _directory_shape(bytes, directory, shapes)
    assert_equal(whole[0], end)
    assert_equal(whole[1], 64)
    assert_equal(whole[2], directory)
    assert_equal(len(shapes), 65)
    for index in range(128):
        var at = end + 22 + 22 * index
        fake_end(bytes, at, 64, directory)
        assert_false(_directory_candidate(bytes, at, shapes))
        assert_equal(len(shapes), 65)
    assert_equal(_end_of_directory(bytes), end)
    assert_equal(len(unzip(bytes)), 64)


def test_shape_cache_bounds_and_failed_suffixes() raises:
    var shapes = Dict[Int, Tuple[Int, Int, Int]]()
    var short = List[UInt8](length=3, fill=0)
    assert_equal(_directory_shape(short, 0, shapes)[1], 0)
    shapes = Dict[Int, Tuple[Int, Int, Int]]()
    short = List[UInt8](length=10, fill=0)
    poke(short, 0, 0x02014B50, 4)
    assert_equal(_directory_shape(short, 0, shapes)[1], -1)
    # The first record reaches a truncated second header. Both suffixes
    # must cache failure, including the predecessor on the path stack.
    var bytes = one()
    poke(bytes, 40 + 28, 22, 2)
    poke(bytes, 108, 0x02014B50, 4)
    shapes = Dict[Int, Tuple[Int, Int, Int]]()
    assert_equal(_directory_shape(bytes, 40, shapes)[1], -1)
    assert_equal(len(shapes), 2)
    assert_equal(_directory_shape(bytes, 108, shapes)[1], -1)


def test_competing_complete_directory_layouts_use_the_last_record() raises:
    var bytes = one()
    poke(bytes, 91 + 20, 22, 2)
    bytes.extend(List[UInt8](length=22, fill=0))
    # Both an earlier one-file archive with a comment and a trailing empty
    # archive with a prefix have complete structural interpretations.
    fake_end(bytes, 113, 0, 113)
    assert_equal(_end_of_directory(bytes), 113)
    assert_equal(len(unzip(bytes)), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
