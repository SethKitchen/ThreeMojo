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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
