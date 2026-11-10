# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.png`.

The checks here decode the encoder's own output by hand rather than trusting
it, including recomputing every chunk CRC and walking the stored DEFLATE
blocks back to the original scanlines.
"""

from core.binary import big_endian_u32
from render.framebuffer import Color, Framebuffer
from render.png import (
    FILTER_AVERAGE,
    FILTER_NONE,
    FILTER_PAETH,
    FILTER_SUB,
    FILTER_UP,
    TEXTURE_LEVEL,
    decode,
    encode,
    filtered_scanlines,
    zlib_stream,
)
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

comptime SIGNATURE_LENGTH = 8


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
        var length = big_endian_u32(png, position)
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
        var length = big_endian_u32(png, position)
        # The CRC covers the type and data, but not the length field.
        var expected = crc32_of(png, position + 4, length + 4)
        var stored = big_endian_u32(png, position + 8 + length)
        assert_equal(Int(expected), stored)
        checked += 1
        position += 12 + length
    assert_equal(checked, 3)


def test_header_describes_an_rgba_image() raises:
    var png = encode(Framebuffer(3, 2, Color(0, 0, 0)))
    var data = SIGNATURE_LENGTH + 8
    assert_equal(big_endian_u32(png, data), 3)  # width
    assert_equal(big_endian_u32(png, data + 4), 2)  # height
    assert_equal(Int(png[data + 8]), 8)  # bit depth
    assert_equal(Int(png[data + 9]), 6)  # color type 6 = truecolor + alpha
    assert_equal(Int(png[data + 10]), 0)  # compression
    assert_equal(Int(png[data + 11]), 0)  # filter
    assert_equal(Int(png[data + 12]), 0)  # interlace


def test_iend_is_empty() raises:
    var png = encode(Framebuffer(1, 1, Color(0, 0, 0)))
    assert_equal(big_endian_u32(png, len(png) - 12), 0)
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
        var length = big_endian_u32(png, position)
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


def test_rgb_transparency_key_requires_all_three_channels() raises:
    from render.png import push_chunk

    var bytes: List[UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    var header: List[UInt8] = [0, 0, 0, 3, 0, 0, 0, 1, 8, 2, 0, 0, 0]
    push_chunk(bytes, "IHDR", header)
    push_chunk(bytes, "tRNS", [UInt8(0), 10, 0, 20, 0, 30])
    # Key match, same red with different green, same red/green with different blue.
    var row: List[UInt8] = [0, 10, 20, 30, 10, 21, 30, 10, 20, 31]
    push_chunk(bytes, "IDAT", zlib_stream(row))
    push_chunk(bytes, "IEND", List[UInt8]())
    var image = decode(bytes)
    assert_equal(image.pixels[3], UInt8(0))
    assert_equal(image.pixels[7], UInt8(255))
    assert_equal(image.pixels[11], UInt8(255))


def _gray_rows(rows: List[List[Int]]) raises -> Framebuffer:
    """Return a buffer whose pixel at (x, y) has `rows[y][x]` in each of
    its four channels."""
    var buffer = Framebuffer(len(rows[0]), len(rows), Color(0, 0, 0, 0))
    for y in range(len(rows)):
        for x in range(len(rows[y])):
            var v = UInt8(rows[y][x])
            buffer.set_pixel(x, y, Color(v, v, v, v))
    return buffer^


def _filter_rows() -> List[List[Int]]:
    """Return six rows of eight pixels. Each of the five filters leaves
    the smallest bytes for one of them."""
    return [
        # Nothing to guess: every filter leaves zeros, and the first wins.
        [0, 0, 0, 0, 0, 0, 0, 0],
        # A ramp over a row of zeros. The pixel to the left is the guess.
        [10, 30, 50, 70, 90, 110, 130, 150],
        # The row above again.
        [10, 30, 50, 70, 90, 110, 130, 150],
        # Each pixel is the average of its left and the pixel above.
        [5, 17, 33, 51, 70, 90, 110, 130],
        # A row for the next one to stand on.
        [200, 13, 150, 77, 40, 40, 40, 40],
        # The row above on the left, and one level on the right. Paeth's
        # guess is right on both sides. No other filter's is.
        [200, 13, 150, 77, 90, 90, 90, 90],
    ]


def test_each_row_gets_the_filter_that_leaves_the_least() raises:
    var buffer = _gray_rows(_filter_rows())
    var rows = filtered_scanlines(buffer)
    var stride = 8 * 4 + 1
    assert_equal(len(rows), 6 * stride)
    assert_equal(Int(rows[0]), FILTER_NONE)
    assert_equal(Int(rows[stride]), FILTER_SUB)
    assert_equal(Int(rows[2 * stride]), FILTER_UP)
    assert_equal(Int(rows[3 * stride]), FILTER_AVERAGE)
    assert_equal(Int(rows[5 * stride]), FILTER_PAETH)
    # The ramp is its first pixel and then a step of 20, in each channel.
    assert_equal(Int(rows[stride + 1]), 10)
    assert_equal(Int(rows[stride + 5]), 20)
    # The row above again, and the average, are all zeros.
    for at in range(1, stride):
        assert_equal(Int(rows[2 * stride + at]), 0)
        assert_equal(Int(rows[3 * stride + at]), 0)
    # Paeth's one wrong guess is where the two sides meet: 90 less 40.
    for at in range(1, stride):
        var want = 50 if (at - 1) // 4 == 4 else 0
        assert_equal(Int(rows[5 * stride + at]), want)


def test_a_filtered_file_reads_back_at_every_level() raises:
    var buffer = _gray_rows(_filter_rows())
    for level in range(1, 10):
        var image = decode(encode(buffer, level))
        assert_equal(image.width, 8)
        assert_equal(image.height, 6)
        assert_true(image.pixels == buffer.pixels, String(level))


def test_a_level_makes_a_smaller_file() raises:
    # A ramp across and a ramp down, as a rendered sky has.
    var buffer = Framebuffer(64, 64, Color(0, 0, 0))
    for y in range(64):
        for x in range(64):
            buffer.set_pixel(
                x, y, Color(UInt8(x * 3), UInt8(y * 3), UInt8(x + y), 255)
            )
    var stored = encode(buffer)
    assert_true(len(stored) > 64 * 64 * 4)
    var packed = encode(buffer, TEXTURE_LEVEL)
    assert_true(len(packed) * 20 < len(stored))
    assert_true(decode(packed).pixels == buffer.pixels)


def test_level_zero_is_the_stored_file() raises:
    var buffer = _gray_rows(_filter_rows())
    assert_true(encode(buffer, 0) == encode(buffer))
    # Stored rows have no filter, whatever would suit them.
    var raw = idat_scanlines(buffer)
    for y in range(6):
        assert_equal(Int(raw[y * 33]), FILTER_NONE)


def test_a_level_outside_zero_to_nine_is_refused() raises:
    var buffer = Framebuffer(1, 1, Color(0, 0, 0))
    with assert_raises(contains="a level must be from 0 to 9"):
        _ = encode(buffer, 10)
    with assert_raises(contains="a level must be from 0 to 9"):
        _ = encode(buffer, -1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
