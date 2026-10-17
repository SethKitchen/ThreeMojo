# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The public DEFLATE reader owns its snapshot; decoding borrows internally."""

from render.inflate import BitReader, Huffman, inflate
from render.jpeg import BitReader as JpegBitReader, HuffmanTable
from std.testing import TestSuite, assert_equal, assert_raises


def _reader_from_local_bytes() -> BitReader:
    var bytes: List[UInt8] = [5]
    return BitReader(bytes, 0)


def test_public_constructor_keeps_an_independent_snapshot() raises:
    var bytes: List[UInt8] = [1, 2]
    var reader = BitReader(bytes, 0)
    bytes[0] = 0
    bytes.clear()
    assert_equal(reader.read_bits(8), 1)
    assert_equal(reader.read_bits(8), 2)
    var local = _reader_from_local_bytes()
    assert_equal(local.read_bits(8), 5)


def test_public_huffman_decode_retains_reader_state() raises:
    var bytes: List[UInt8] = [2]
    var reader = BitReader(bytes, 0)
    var lengths: List[Int] = [1, 1]
    var code = Huffman(lengths)
    bytes[0] = 0
    assert_equal(code.decode(reader), 0)
    assert_equal(code.decode(reader), 1)
    assert_equal(reader.bit, 2)
    assert_equal(reader.position, 0)


def test_public_reader_failure_keeps_consumed_position() raises:
    var bytes: List[UInt8] = [255]
    var reader = BitReader(bytes, 0)
    with assert_raises(
        contains="Compressed stream ended in the middle of a code"
    ):
        _ = reader.read_bits(9)
    assert_equal(reader.position, 1)
    assert_equal(reader.bit, 0)


def test_public_inflate_overloads_keep_borrowed_input() raises:
    var bytes: List[UInt8] = [3, 0]
    assert_equal(len(inflate(bytes)), 0)
    assert_equal(len(inflate(Span(bytes))), 0)
    var expected: List[UInt8] = [3, 0]
    assert_equal(bytes, expected)


def _jpeg_reader_from_local_bytes() -> JpegBitReader:
    var bytes: List[UInt8] = [128, 0]
    return JpegBitReader(bytes^, 0)


def test_jpeg_public_constructor_keeps_an_independent_snapshot() raises:
    var bytes: List[UInt8] = [128, 0]
    var reader = JpegBitReader(bytes.copy(), 0)
    bytes[0] = 0
    bytes.clear()
    assert_equal(reader.bit(), 1)
    assert_equal(reader.bits(7), 0)
    var local = _jpeg_reader_from_local_bytes()
    assert_equal(local.bit(), 1)


def test_jpeg_public_reader_failure_keeps_consumed_position() raises:
    var bytes: List[UInt8] = [128]
    var reader = JpegBitReader(bytes^, 0)
    assert_equal(reader.bits(8), 128)
    with assert_raises(contains="A scan ended before its last block"):
        _ = reader.bit()
    assert_equal(reader.at, 1)
    assert_equal(reader.count, 0)


def test_public_deflate_alignment_matches_original_case() raises:
    var bytes: List[UInt8] = [UInt8(0b10110101), UInt8(0xFF)]
    var reader = BitReader(bytes, 0)
    assert_equal(reader.read_bits(0), 0)
    assert_equal(reader.read_bits(3), 5)
    reader.align()
    assert_equal(reader.position, 1)
    assert_equal(reader.bit, 0)
    reader.align()
    assert_equal(reader.position, 1)
    assert_equal(reader.read_bits(8), 255)


def test_public_deflate_incomplete_huffman_matches_original_case() raises:
    var lengths: List[Int] = [2]
    var code = Huffman(lengths)
    var ones: List[UInt8] = [0xFF, 0xFF, 0xFF]
    var reader = BitReader(ones, 0)
    with assert_raises():
        _ = code.decode(reader)
    assert_equal(reader.position, 1)
    assert_equal(reader.bit, 7)


def test_public_jpeg_huffman_lookup_and_slow_paths() raises:
    var counts = List[Int](length=16, fill=0)
    counts[0] = 1
    var table = HuffmanTable(counts, [UInt8(7)])
    var short: List[UInt8] = [0]
    var slow = JpegBitReader(short^, 0)
    assert_equal(slow.decode(table), UInt8(7))
    assert_equal(slow.count, 7)
    var full: List[UInt8] = [0, 0, 0xFF, 0xD9]
    var fast = JpegBitReader(full^, 0)
    assert_equal(fast.decode(table), UInt8(7))
    assert_equal(fast.count, 15)
    counts[0] = 0
    counts[9] = 1
    var long_table = HuffmanTable(counts, [UInt8(9)])
    var long_bytes: List[UInt8] = [0, 0]
    var long_reader = JpegBitReader(long_bytes^, 0)
    assert_equal(long_reader.decode(long_table), UInt8(9))
    assert_equal(long_reader.count, 6)
    var stuffed: List[UInt8] = [0xFF, 0, 0xFF, 0]
    var wrong = JpegBitReader(stuffed^, 0)
    with assert_raises(contains="Huffman table does not define"):
        _ = wrong.decode(table)
    assert_equal(wrong.at, 4)
    assert_equal(wrong.count, 0)


def test_public_jpeg_fill_boundaries_and_stuffing() raises:
    var bytes: List[UInt8] = [0xFF, 0, 0xFF, 0xD9]
    var stuffed = JpegBitReader(bytes^, 0)
    assert_equal(stuffed.bits(0), 0)
    assert_equal(stuffed.at, 0)
    assert_equal(stuffed.bits(8), 255)
    assert_equal(stuffed.at, 2)
    with assert_raises(contains="before its last block"):
        _ = stuffed.bit()
    var lone_bytes: List[UInt8] = [0xFF]
    var lone = JpegBitReader(lone_bytes^, 0)
    with assert_raises(contains="before its last block"):
        _ = lone.bit()
    assert_equal(lone.at, 0)
    var many = List[UInt8](length=8, fill=0)
    var buffered = JpegBitReader(many^, 0)
    assert_equal(buffered.bit(), 0)
    assert_equal(buffered.at, 7)
    assert_equal(buffered.count, 55)


def test_public_jpeg_restart_success_and_error_states() raises:
    var bytes: List[UInt8] = [0xFF, 0xD0, 0x80]
    var reader = JpegBitReader(bytes^, 0)
    reader.held = 7
    reader.count = 3
    reader.stopped = True
    reader.restart(UInt8(0xD0))
    assert_equal(reader.at, 2)
    assert_equal(reader.held, 0)
    assert_equal(reader.count, 0)
    assert_equal(reader.stopped, False)
    assert_equal(reader.bit(), 1)
    for kind in range(4):
        var bad: List[UInt8] = [0xFF, 0xD1]
        if kind == 0:
            bad = [0, 0xD0]
        elif kind == 1:
            bad = [0xFF]
        var broken = JpegBitReader(bad^, 0)
        broken.held = 15
        broken.count = 8 if kind == 2 else 3
        broken.stopped = True
        with assert_raises():
            broken.restart(UInt8(0xD0))
        assert_equal(broken.at, 0)
        assert_equal(broken.count, 0)
        assert_equal(broken.held, 0)
        assert_equal(broken.stopped, False)


def test_public_jpeg_end_success_and_error_states() raises:
    var bytes: List[UInt8] = [0xFF, 0xD9]
    var reader = JpegBitReader(bytes^, 0)
    reader.held = 7
    reader.count = 3
    reader.stopped = True
    assert_equal(reader.end(), 0)
    assert_equal(reader.count, 0)
    assert_equal(reader.held, 0)
    assert_equal(reader.stopped, False)
    for kind in range(3):
        var bad: List[UInt8] = [0xFF, 0xD9]
        if kind == 0:
            bad = [0, 0xD9]
        elif kind == 1:
            bad = [0xFF]
        var broken = JpegBitReader(bad^, 0)
        broken.held = 15
        broken.count = 8 if kind == 2 else 3
        broken.stopped = True
        with assert_raises(contains="without a marker"):
            _ = broken.end()
        assert_equal(broken.at, 0)
        assert_equal(broken.count, 0)
        assert_equal(broken.held, 0)
        assert_equal(broken.stopped, False)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
