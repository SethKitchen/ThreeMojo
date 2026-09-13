# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.png`.

The checks here decode the encoder's own output by hand rather than trusting
it, including recomputing every chunk CRC and walking the stored DEFLATE
blocks back to the original scanlines.
"""

from render.framebuffer import Color, Framebuffer
from render.png import encode, zlib_stream
from std.testing import TestSuite, assert_equal, assert_true

comptime SIGNATURE_LENGTH = 8


def be32(bytes: List[UInt8], at: Int) -> Int:
    """Return the big-endian 32-bit integer starting at `at`."""
    return (
        Int(bytes[at]) << 24
        | Int(bytes[at + 1]) << 16
        | Int(bytes[at + 2]) << 8
        | Int(bytes[at + 3])
    )


def chunk_kind(bytes: List[UInt8], at: Int) raises -> String:
    """Return the four-character chunk type starting at `at`."""
    var kind = String("")
    for offset in range(4):
        kind += chr(Int(bytes[at + offset]))
    return kind^


def crc32_of(bytes: List[UInt8], start: Int, size: Int) -> UInt32:
    """Return the PNG CRC-32 over `size` bytes of `bytes` from `start`."""
    var crc = UInt32(0xFFFFFFFF)
    for index in range(start, start + size):
        crc ^= UInt32(bytes[index])
        for _ in range(8):
            if (crc & UInt32(1)) != 0:
                crc = (crc >> 1) ^ UInt32(0xEDB88320)
            else:
                crc = crc >> 1
    return crc ^ UInt32(0xFFFFFFFF)


def inflate_stored(
    png: List[UInt8], start: Int, size: Int
) raises -> List[UInt8]:
    """Undo the stored-block zlib stream inside an IDAT payload.

    Args:
        png: The whole file.
        start: Offset of the zlib stream.
        size: Length of the zlib stream.

    Returns:
        The raw filtered scanlines.

    Raises:
        Error: If a block header or length pair is malformed.
    """
    if png[start] != 0x78:
        raise Error("bad zlib CMF byte")
    var raw = List[UInt8]()
    var position = start + 2
    var limit = start + size - 4  # the trailing Adler-32
    while position < limit:
        var final = png[position] == 1
        var length = Int(png[position + 1]) | (Int(png[position + 2]) << 8)
        var complement = Int(png[position + 3]) | (Int(png[position + 4]) << 8)
        if (length ^ 0xFFFF) != complement:
            raise Error("LEN and NLEN disagree")
        position += 5
        for offset in range(length):
            raw.append(png[position + offset])
        position += length
        if final:
            break
    return raw^


def test_signature_is_correct() raises:
    var png = encode(Framebuffer(1, 1, Color(0, 0, 0)))
    var expected = [137, 80, 78, 71, 13, 10, 26, 10]
    for index in range(SIGNATURE_LENGTH):
        assert_equal(Int(png[index]), expected[index])


def test_chunks_appear_in_order() raises:
    var png = encode(Framebuffer(2, 2, Color(0, 0, 0)))
    var kinds = List[String]()
    var position = SIGNATURE_LENGTH
    while position < len(png):
        var length = be32(png, position)
        kinds.append(chunk_kind(png, position + 4))
        position += 12 + length
    assert_equal(len(kinds), 3)
    assert_equal(kinds[0], String("IHDR"))
    assert_equal(kinds[1], String("IDAT"))
    assert_equal(kinds[2], String("IEND"))


def test_every_chunk_crc_is_correct() raises:
    var png = encode(Framebuffer(2, 2, Color(9, 9, 9, 200)))
    var position = SIGNATURE_LENGTH
    var checked = 0
    while position < len(png):
        var length = be32(png, position)
        # The CRC covers the type and data, but not the length field.
        var expected = crc32_of(png, position + 4, length + 4)
        var stored = be32(png, position + 8 + length)
        assert_equal(Int(expected), stored)
        checked += 1
        position += 12 + length
    assert_equal(checked, 3)


def test_header_describes_an_rgba_image() raises:
    var png = encode(Framebuffer(3, 2, Color(0, 0, 0)))
    var data = SIGNATURE_LENGTH + 8
    assert_equal(be32(png, data), 3)  # width
    assert_equal(be32(png, data + 4), 2)  # height
    assert_equal(Int(png[data + 8]), 8)  # bit depth
    assert_equal(Int(png[data + 9]), 6)  # color type 6 = truecolor + alpha
    assert_equal(Int(png[data + 10]), 0)  # compression
    assert_equal(Int(png[data + 11]), 0)  # filter
    assert_equal(Int(png[data + 12]), 0)  # interlace


def test_iend_is_empty() raises:
    var png = encode(Framebuffer(1, 1, Color(0, 0, 0)))
    assert_equal(be32(png, len(png) - 12), 0)
    assert_equal(chunk_kind(png, len(png) - 8), String("IEND"))


def idat_scanlines(buffer: Framebuffer) raises -> List[UInt8]:
    """Return the filtered scanlines recovered from `buffer`'s encoding.

    Args:
        buffer: The pixels to round-trip.

    Returns:
        The decoded raw scanline bytes.

    Raises:
        Error: If the file holds no IDAT chunk.
    """
    var png = encode(buffer)
    var position = SIGNATURE_LENGTH
    while position < len(png):
        var length = be32(png, position)
        if chunk_kind(png, position + 4) == "IDAT":
            return inflate_stored(png, position + 8, length)
        position += 12 + length
    raise Error("no IDAT chunk")


def test_every_scanline_uses_the_none_filter() raises:
    var buffer = Framebuffer(2, 3, Color(1, 2, 3))
    var raw = idat_scanlines(buffer)
    var stride = 2 * 4 + 1
    for y in range(3):
        assert_equal(Int(raw[y * stride]), 0)


def test_pixels_survive_the_round_trip_with_alpha() raises:
    var buffer = Framebuffer(2, 2, Color(20, 24, 32))
    buffer.set_pixel(0, 0, Color(255, 0, 0))
    buffer.set_pixel(1, 1, Color(0, 255, 0, 128))
    var raw = idat_scanlines(buffer)
    var stride = 2 * 4 + 1

    assert_equal(Int(raw[1]), 255)  # (0,0) red
    assert_equal(Int(raw[4]), 255)  # (0,0) alpha, defaulted opaque
    var last = stride + 1 + 4
    assert_equal(Int(raw[last + 1]), 255)  # (1,1) green
    assert_equal(Int(raw[last + 3]), 128)  # (1,1) alpha preserved


def test_decoded_length_matches_the_buffer() raises:
    var buffer = Framebuffer(2, 2, Color(0, 0, 0))
    # One filter byte per row, plus four channels per pixel.
    assert_equal(len(idat_scanlines(buffer)), 2 * (2 * 4 + 1))


def inflate_bytes(stream: List[UInt8]) raises -> List[UInt8]:
    """Undo a standalone stored-block zlib stream.

    Args:
        stream: A complete zlib stream.

    Returns:
        The bytes it carries.

    Raises:
        Error: If a block header or length pair is malformed.
    """
    var wrapped = List[UInt8]()
    for index in range(len(stream)):
        wrapped.append(stream[index])
    return inflate_stored(wrapped, 0, len(wrapped))


def test_stream_splits_when_data_exceeds_one_block() raises:
    # Testing the real 65535-byte boundary would need a 64 KiB buffer, which
    # is ruinously slow under coverage instrumentation. Lowering the limit
    # exercises exactly the same code path with 100 bytes.
    var raw = List[UInt8]()
    for index in range(100):
        raw.append(UInt8(index))
    var stream = zlib_stream(raw, max_block=16)
    assert_equal(inflate_bytes(stream), raw)


def test_split_stream_marks_only_the_last_block_final() raises:
    var raw = List[UInt8]()
    for index in range(40):
        raw.append(UInt8(index))
    var stream = zlib_stream(raw, max_block=16)
    # Blocks of 16, 16, 8: headers sit after the 2-byte zlib header.
    assert_equal(Int(stream[2]), 0)
    assert_equal(Int(stream[2 + 5 + 16]), 0)
    assert_equal(Int(stream[2 + 2 * (5 + 16)]), 1)


def test_data_landing_exactly_on_a_block_boundary() raises:
    var raw = List[UInt8]()
    for index in range(32):
        raw.append(UInt8(index))
    var stream = zlib_stream(raw, max_block=16)
    assert_equal(inflate_bytes(stream), raw)


def test_empty_stream_still_emits_one_final_block() raises:
    var stream = zlib_stream(List[UInt8]())
    assert_equal(Int(stream[2]), 1)
    assert_equal(len(inflate_bytes(stream)), 0)


def test_single_pixel_image_encodes() raises:
    var raw = idat_scanlines(Framebuffer(1, 1, Color(1, 2, 3, 4)))
    assert_equal(len(raw), 5)
    assert_equal(Int(raw[4]), 4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
