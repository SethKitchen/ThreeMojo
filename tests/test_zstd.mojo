# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.zstd`: streams the reference library wrote, frames
built by hand for the modes it rarely picks, and every malformed stream the
decoder refuses.

`assets/zstd/reference.zst` holds ten frames and a skippable frame that
python-zstandard 0.25 (libzstd 1.5.7) wrote at levels -5 to 19, each with
its checksum. Between them they use raw, RLE and compressed blocks; raw,
Huffman and treeless literals; direct and FSE-coded Huffman weights; and
predefined, described and repeated FSE tables.

`assets/zstd/crafted.zst` is two frames built by hand: a treeless literals
section of every size format, RLE literals, single-symbol and repeated
tables, 32512 sequences in one block, a zero-length RLE block and an
eight-byte content size. libzstd decodes both files to the same bytes.
"""

from render.zstd import xxh64, zstd_decompress
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises


def fixture(name: String) raises -> List[UInt8]:
    """Return one of the files under assets/zstd/."""
    return Path("assets/zstd/" + name).read_bytes()


def le(value: Int, count: Int) -> List[UInt8]:
    """Return `value` as `count` little-endian bytes."""
    var out = List[UInt8]()
    for index in range(count):
        out.append(UInt8((value >> (index * 8)) & 0xFF))
    return out^


def block(kind: Int, content: List[UInt8], size: Int = -1) -> List[UInt8]:
    """Return a last block of `kind`: its header, then `content`."""
    var stated = size if size >= 0 else len(content)
    var out = le(1 | (kind << 1) | (stated << 3), 3)
    out.extend(content.copy())
    return out^


def frame(body: List[UInt8], descriptor: Int = 0) -> List[UInt8]:
    """Return the magic number, a frame header descriptor, a window byte
    when the descriptor is not single segment, and `body`."""
    var out = le(0xFD2FB528, 4)
    out.append(UInt8(descriptor))
    if (descriptor >> 5) & 1 == 0:
        out.append(0)
    out.extend(body.copy())
    return out^


def compressed(section: List[UInt8]) -> List[UInt8]:
    """Return a frame of one compressed block holding `section`."""
    return frame(block(2, section))


def cat(a: List[UInt8], b: List[UInt8]) -> List[UInt8]:
    """Return `a` followed by `b`."""
    var out = a.copy()
    out.extend(b.copy())
    return out^


def test_reference_frames_decompress() raises:
    var out = zstd_decompress(fixture("reference.zst"))
    assert_equal(len(out), 382538)
    assert_equal(xxh64(out, 0, len(out)), 0x633D1CBD2026F3D8)


def test_crafted_frames_decompress() raises:
    var out = zstd_decompress(fixture("crafted.zst"))
    assert_equal(len(out), 130268)
    assert_equal(xxh64(out, 0, len(out)), 0x3B743A33648A3EB4)


def test_xxh64_matches_the_reference() raises:
    var bytes = List[UInt8]()
    for index in range(100):
        bytes.append(UInt8(index))
    assert_equal(xxh64(bytes, 0, 0), 0xEF46DB3751D8E999)
    assert_equal(xxh64(bytes, 0, 1), 0xE934A84ADB052768)
    assert_equal(xxh64(bytes, 0, 4), 0xFFCED8604453CC1E)
    assert_equal(xxh64(bytes, 0, 33), 0x0C535D1ACAFB8EAD)
    assert_equal(xxh64(bytes, 0, 100), 0x6AC1E58032166597)


def test_a_malformed_stream_is_refused() raises:
    with assert_raises(contains="empty"):
        _ = zstd_decompress(List[UInt8]())
    with assert_raises(contains="magic number"):
        _ = zstd_decompress([1, 2, 3, 4])
    var reference = fixture("reference.zst")
    with assert_raises(contains="cut short"):
        _ = zstd_decompress(List[UInt8](reference[:6]))
    with assert_raises(contains="cut short"):
        _ = zstd_decompress([0x50, 0x2A, 0x4D, 0x18, 5, 0, 0, 0])
    with assert_raises(contains="more than was expected"):
        _ = zstd_decompress(reference, 100)
    # A content size past the top of an Int.
    var huge = le(0xFD2FB528, 4)
    huge.append(0xE0)
    huge.extend(le(-1, 8))
    with assert_raises(contains="more than was expected"):
        _ = zstd_decompress(huge)


def test_a_malformed_frame_is_refused() raises:
    with assert_raises(contains="reserved bit"):
        _ = zstd_decompress(frame(block(0, [1]), 0x08))
    with assert_raises(contains="dictionary"):
        _ = zstd_decompress(frame(cat([1], block(0, [1])), 0x01))
    with assert_raises(contains="128 KiB"):
        _ = zstd_decompress(frame(block(1, [1], 128 * 1024 + 1)))
    with assert_raises(contains="reserved type"):
        _ = zstd_decompress(frame(block(3, [1])))
    # A one-byte content size of five, and four bytes.
    with assert_raises(contains="size its header states"):
        _ = zstd_decompress(frame(cat([5], block(0, [1, 2, 3, 4])), 0x20))
    var summed = frame(block(0, [1, 2]), 0x04)
    summed.extend([1, 2, 3, 4])
    with assert_raises(contains="checksum"):
        _ = zstd_decompress(summed)


def test_malformed_literals_are_refused() raises:
    # A treeless section in the first block.
    with assert_raises(contains="treeless"):
        _ = zstd_decompress(compressed([0x13, 0x40, 0x00, 0x01]))
    # Direct weights: fifteen gives a code too long; three and one do not
    # leave a power of two.
    with assert_raises(contains="longer than eleven"):
        _ = zstd_decompress(compressed([0x02, 0x80, 0x00, 0x80, 0xF0]))
    with assert_raises(contains="do not complete"):
        _ = zstd_decompress(compressed([0x02, 0x80, 0x00, 0x81, 0x31]))
    # FSE-coded weights: one symbol fills every state and reads no bits,
    # so the stream never ends.
    with assert_raises(contains="more than 255"):
        _ = zstd_decompress(
            compressed([0x02, 0x40, 0x01, 0x04, 0xF0, 0x03, 0x00, 0x80])
        )
    with assert_raises(contains="accuracy"):
        _ = zstd_decompress(compressed([0x02, 0x80, 0x00, 0x01, 0x02]))
    # A zero count and four repeat flags name thirteen weights.
    with assert_raises(contains="too many symbols"):
        _ = zstd_decompress(
            compressed([0x02, 0x00, 0x01, 0x03, 0x10, 0xFE, 0x01])
        )
    # Four streams of no literals, the last one empty.
    with assert_raises(contains="marker bit"):
        _ = zstd_decompress(
            compressed(
                [0x06, 0xC0, 0x02, 0x80, 0x10, 1, 0, 1, 0, 1, 0, 1, 1, 1]
            )
        )
    # One stream of no literals whose marker leaves a bit unread.
    with assert_raises(contains="Huffman stream"):
        _ = zstd_decompress(compressed([0x02, 0xC0, 0x00, 0x80, 0x10, 0x02]))
    # Five literals in four streams of two, two, two and none.
    with assert_raises(contains="too few literals"):
        _ = zstd_decompress(
            compressed(
                [0x56, 0x00, 0x03, 0x80, 0x10, 1, 0, 1, 0, 1, 0, 4, 4, 4, 1]
            )
        )


def test_malformed_sequences_are_refused() raises:
    # No literals, then the sequences section.
    with assert_raises(contains="no such symbol"):
        _ = zstd_decompress(compressed([0x00, 0x01, 0x40, 36]))
    with assert_raises(contains="repeated table"):
        _ = zstd_decompress(compressed([0x00, 0x01, 0xC0]))
    with assert_raises(contains="reserved bits"):
        _ = zstd_decompress(compressed([0x00, 0x01, 0x01]))
    with assert_raises(contains="no sequences"):
        _ = zstd_decompress(compressed([0x00, 0x00, 0x99]))
    # An offset table whose description ends one byte early.
    with assert_raises(contains="runs past its section"):
        _ = zstd_decompress(compressed([0x00, 0x01, 0x20, 0xF0]))
    # Single-symbol tables: offset value three with no literals repeats
    # the first offset less one, which is zero.
    with assert_raises(contains="offset is zero"):
        _ = zstd_decompress(compressed([0x00, 0x01, 0x54, 0, 1, 0, 0x03]))
    with assert_raises(contains="more literals"):
        _ = zstd_decompress(compressed([0x00, 0x01, 0x54, 1, 0, 0, 0x01]))
    with assert_raises(contains="before the start"):
        _ = zstd_decompress(compressed([0x00, 0x01, 0x54, 0, 0, 0, 0x01]))
    # Four raw literals, then a stream with a bit left over, and one with
    # no marker.
    var abcd: List[UInt8] = [0x20, 0x61, 0x62, 0x63, 0x64]
    with assert_raises(contains="does not end with its block"):
        _ = zstd_decompress(compressed(cat(abcd, [0x01, 0x54, 4, 0, 0, 0x02])))
    with assert_raises(contains="marker bit"):
        _ = zstd_decompress(compressed(cat(abcd, [0x01, 0x54, 4, 0, 0, 0x00])))
    # The same block, well formed.
    var good = zstd_decompress(
        compressed(cat(abcd, [0x01, 0x54, 4, 0, 0, 0x01]))
    )
    assert_equal(len(good), 7)
    assert_equal(good[6], 0x64)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
