# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The public DEFLATE reader owns its snapshot; decoding borrows internally."""

from render.inflate import BitReader, Huffman, inflate
from render.jpeg import BitReader as JpegBitReader
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
