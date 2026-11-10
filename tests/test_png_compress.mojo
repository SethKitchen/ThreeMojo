# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.png_compress`: the filter each row gets, and files
that `render.png.decode` reads back to the same pixels at every level."""

from core.binary import big_endian_u32
from render.framebuffer import Color, Framebuffer
from render.inflate import zlib_inflate
from render.png import decode, encode
from render.png_compress import (
    FILTER_AVERAGE,
    FILTER_NONE,
    FILTER_PAETH,
    FILTER_SUB,
    FILTER_UP,
    TEXTURE_LEVEL,
    compressed_frame_data,
    encode_compressed,
    filtered_scanlines,
)
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


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


def _ramps() raises -> Framebuffer:
    """Return 64 by 64 pixels of a ramp across and a ramp down, as a
    rendered sky has."""
    var buffer = Framebuffer(64, 64, Color(0, 0, 0))
    for y in range(64):
        for x in range(64):
            buffer.set_pixel(
                x, y, Color(UInt8(x * 3), UInt8(y * 3), UInt8(x + y), 255)
            )
    return buffer^


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


def test_the_filters_are_the_type_bytes_of_png() raises:
    assert_equal(FILTER_NONE, 0)
    assert_equal(FILTER_SUB, 1)
    assert_equal(FILTER_UP, 2)
    assert_equal(FILTER_AVERAGE, 3)
    assert_equal(FILTER_PAETH, 4)
    assert_equal(TEXTURE_LEVEL, 6)


def test_a_file_reads_back_at_every_level() raises:
    var buffer = _gray_rows(_filter_rows())
    for level in range(10):
        var image = decode(encode_compressed(buffer, level))
        assert_equal(image.width, 8)
        assert_equal(image.height, 6)
        assert_true(image.pixels == buffer.pixels, String(level))
    # With no level, the file is the file of `TEXTURE_LEVEL`.
    assert_true(
        encode_compressed(buffer) == encode_compressed(buffer, TEXTURE_LEVEL)
    )


def test_the_file_is_one_idat_of_the_filtered_rows() raises:
    var buffer = _ramps()
    var png = encode_compressed(buffer)
    # The signature, a header of 13 bytes, then the pixels and the end.
    assert_equal(Int(png[0]), 137)
    assert_equal(Int(big_endian_u32(png, 8)), 13)
    assert_equal(Int(big_endian_u32(png, 16)), 64)
    assert_equal(Int(big_endian_u32(png, 20)), 64)
    var length = Int(big_endian_u32(png, 33))
    assert_equal(Int(png[37]), 73)
    assert_equal(Int(png[38]), 68)
    assert_equal(Int(png[39]), 65)
    assert_equal(Int(png[40]), 84)
    var stream = List[UInt8]()
    for at in range(41, 41 + length):
        stream.append(png[at])
    assert_true(stream == compressed_frame_data(buffer))
    assert_true(zlib_inflate(stream) == filtered_scanlines(buffer))
    # The data, its checksum, and an end chunk of twelve bytes.
    assert_equal(len(png), 41 + length + 4 + 12)


def test_a_level_makes_a_smaller_file() raises:
    var buffer = _ramps()
    var stored = encode(buffer)
    assert_true(len(stored) > 64 * 64 * 4)
    var packed = encode_compressed(buffer)
    assert_true(len(packed) * 20 < len(stored))
    assert_true(decode(packed).pixels == buffer.pixels)
    # Level 0 stores the filtered rows: as large as the pixels.
    assert_true(len(encode_compressed(buffer, 0)) > 64 * 64 * 4)
    # The smallest level is no larger than the fastest.
    assert_true(
        len(encode_compressed(buffer, 9)) <= len(encode_compressed(buffer, 1))
    )


def test_a_level_outside_zero_to_nine_is_refused() raises:
    var buffer = Framebuffer(1, 1, Color(0, 0, 0))
    with assert_raises(contains="a level must be from 0 to 9"):
        _ = encode_compressed(buffer, 10)
    with assert_raises(contains="a level must be from 0 to 9"):
        _ = compressed_frame_data(buffer, -1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
