# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.rgbe`.

Every file is assembled here, a header of text and pixels of bytes, flat
or run-length encoded, and every expected number is three.js's arithmetic
worked by hand.
"""

from render.float_image import FloatImage
from render.rgbe import decode, read_header, read_pixels, rgbe_to_float
from render.texture import FLOAT_TYPE, LINEAR, float_texture_from
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)


def text(line: String) -> List[UInt8]:
    """Return a string's bytes."""
    var out = List[UInt8]()
    for byte in line.as_bytes():
        out.append(byte)
    return out^


def plus(var bytes: List[UInt8], more: List[UInt8]) -> List[UInt8]:
    """Return `bytes` with `more` after them."""
    bytes.extend(more.copy())
    return bytes^


def header(width: Int, height: Int) -> List[UInt8]:
    """Return a whole header for an image of that size."""
    return text(
        "#?RADIANCE\n# made by hand\nGAMMA=1.0\nEXPOSURE=1.0\n"
        + "FORMAT=32-bit_rle_rgbe\n\n-Y "
        + String(height)
        + " +X "
        + String(width)
        + "\n"
    )


def refused(bytes: List[UInt8], contains: String) raises:
    """Assert the reader refuses `bytes`, saying `contains`."""
    with assert_raises(contains=contains):
        _ = decode(bytes)


def assert_pixel(
    image: FloatImage, x: Int, y: Int, r: Float32, g: Float32, b: Float32
) raises:
    """Assert the pixel at (x, y) holds these three floats and alpha one."""
    var seen = image.get_pixel(x, y)
    assert_equal(seen[0], r)
    assert_equal(seen[1], g)
    assert_equal(seen[2], b)
    assert_equal(seen[3], 1)


def test_a_pixel_is_its_mantissas_times_a_shared_power_of_two() raises:
    # 128 at exponent 129: 128 / 255 * 2, three.js's scale.
    var light = rgbe_to_float(128, 64, 0, 129)
    assert_equal(light[0], Float32(Float64(128) * 2 / 255))
    assert_equal(light[1], Float32(Float64(64) * 2 / 255))
    assert_equal(light[2], 0)
    assert_equal(light[3], 1)
    # The brightest a file can say, and the dimmest: both finite.
    var sun = rgbe_to_float(255, 255, 255, 255)
    assert_equal(sun[0], Float32(Float64(2) ** 127))
    var dark = rgbe_to_float(1, 0, 0, 0)
    assert_equal(dark[0], Float32(Float64(2) ** -128 / 255))


def test_a_flat_file_reads_its_pixels_from_the_top() raises:
    # Two pixels wide, below the width run-length encoding needs.
    var file = plus(
        header(2, 2),
        [128, 64, 0, 129, 255, 0, 0, 128, 0, 0, 128, 130, 1, 2, 3, 128],
    )
    var image = decode(file)
    assert_equal(image.width, 2)
    assert_equal(image.height, 2)
    assert_pixel(
        image,
        0,
        0,
        Float32(Float64(128) * 2 / 255),
        Float32(Float64(64) * 2 / 255),
        0,
    )
    assert_pixel(image, 1, 0, 1, 0, 0)
    assert_pixel(image, 0, 1, 0, 0, Float32(Float64(128) * 4 / 255))
    assert_pixel(
        image,
        1,
        1,
        Float32(Float64(1) / 255),
        Float32(Float64(2) / 255),
        Float32(Float64(3) / 255),
    )


def test_the_header_can_name_the_size_before_the_format() raises:
    var file = plus(
        # Space around and between the words, and a carriage return.
        text("#?RGBE\n  -Y 1\t +X 1 \r\nFORMAT=32-bit_rle_rgbe\n"),
        [255, 255, 255, 128],
    )
    assert_equal(read_header(file).start, len(file) - 4)
    assert_pixel(decode(file), 0, 0, 1, 1, 1)


def encoded_scanline() -> List[UInt8]:
    """Return one scanline of eight pixels, run-length encoded: red runs,
    green copies, blue a run then a copy, exponent one run."""
    return [
        2,
        2,
        0,
        8,
        # Red: eight of 255.
        136,
        255,
        # Green: eight bytes as they stand.
        8,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        # Blue: four of 10, then four as they stand.
        132,
        10,
        4,
        20,
        30,
        40,
        50,
        # Exponent: eight of 128.
        136,
        128,
    ]


def test_an_encoded_file_reads_each_channel_in_runs() raises:
    var file = plus(plus(header(8, 2), encoded_scanline()), encoded_scanline())
    var image = decode(file)
    for y in range(2):
        for x in range(8):
            var blue = 10
            if x >= 4:
                blue = (x - 3) * 10 + 10
            assert_pixel(
                image,
                x,
                y,
                1,
                Float32(Float64(x) / 255),
                Float32(Float64(blue) / 255),
            )


def test_a_scanline_that_does_not_begin_two_two_is_flat() raises:
    # Eight wide, but the first bytes are not 2, 2: every pixel as it
    # stands, as three.js reads it. Then the other ways to be flat: the
    # third byte's top bit, and too few bytes to look at.
    var firsts: List[List[UInt8]] = [
        [1, 2, 0, 128],
        [2, 1, 0, 128],
        [2, 2, 128, 128],
    ]
    for first in firsts:
        var pixels = List[UInt8]()
        for _ in range(8):
            pixels.extend(first.copy())
        var image = decode(plus(header(8, 1), pixels))
        assert_equal(image.width, 8)
    refused(plus(header(8, 1), [2, 2, 0]), "cut short")
    # Wider than the scanline header can say: flat as well.
    var wide = header(32768, 1)
    refused(plus(wide^, [2, 2, 0, 8]), "cut short")


def test_an_hdr_image_becomes_a_float_texture() raises:
    var image = decode(plus(header(1, 1), [255, 128, 0, 136]))
    var texture = float_texture_from(image)
    assert_true(texture.texel_type == FLOAT_TYPE)
    assert_true(texture.color_space == LINEAR)
    # 255 / 255 * 2^8: light far above one, kept.
    assert_equal(texture.sample(0.5, 0.5).r, 256)


def test_the_header_is_checked() raises:
    refused(text("#?RADIANCE"), "no header")
    refused(text("RADIANCE\n"), "begins with #?")
    refused(text("#?\n"), "begins with #?")
    refused(text("#? RADIANCE\n"), "begins with #?")
    refused(text("#?RADIANCE\n-Y 1 +X 1\n"), "no format")
    refused(text("#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n"), "no image size")
    refused(text("#?RADIANCE\nFORMAT=32-bit_rle_xyze\n"), "XYZE")
    refused(text("#?RADIANCE\nFORMAT=\n"), "XYZE")
    # Lines that look like a size and are not: other orientations and
    # other word counts are read past, as three.js reads past them.
    refused(
        text(
            "#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n+Y 1 +X 1\n-Y 1 -X 1\n-Y 1\n"
        ),
        "no image size",
    )
    refused(text("#?R\nFORMAT=32-bit_rle_rgbe\n-Y 1a +X 1\n"), "decimal digits")
    refused(text("#?R\nFORMAT=32-bit_rle_rgbe\n-Y 1 +X /\n"), "decimal digits")
    refused(
        text("#?R\nFORMAT=32-bit_rle_rgbe\n-Y 1 +X 1234567890\n"), "nine digits"
    )
    refused(text("#?R\nFORMAT=32-bit_rle_rgbe\n-Y 1 +X 0\n"), "one pixel")
    refused(text("#?R\nFORMAT=32-bit_rle_rgbe\n-Y 0 +X 1\n"), "one pixel")
    refused(
        text("#?R\nFORMAT=32-bit_rle_rgbe\n-Y 20000 +X 20000\n"), "more pixels"
    )


def test_encoded_scanlines_are_checked() raises:
    var start = header(8, 2)
    var one = plus(start.copy(), encoded_scanline())
    # The second scanline missing, cut in its header, and cut in its runs.
    refused(one.copy(), "cut short")
    refused(plus(one.copy(), [2, 2]), "cut short")
    refused(plus(one.copy(), [2, 2, 0, 8, 136]), "cut short")
    refused(plus(one.copy(), [2, 2, 0, 8, 8, 1, 2]), "cut short")
    refused(plus(one.copy(), [2, 2, 0, 8]), "cut short")
    # A second scanline whose header is not 2, 2 and the width.
    refused(plus(one.copy(), [2, 3, 0, 8]), "must begin 2, 2")
    refused(plus(one.copy(), [3, 2, 0, 8]), "must begin 2, 2")
    refused(plus(one.copy(), [2, 2, 0, 9]), "must begin 2, 2")
    # Empty runs, and runs past the scanline.
    refused(plus(one.copy(), [2, 2, 0, 8, 0]), "overflows")
    refused(plus(one.copy(), [2, 2, 0, 8, 128, 1]), "overflows")
    refused(plus(one.copy(), [2, 2, 0, 8, 161, 1]), "overflows")
    refused(plus(one.copy(), [2, 2, 0, 8, 33]), "overflows")
    # read_pixels on its own: two flat pixels exactly.
    assert_equal(len(read_pixels([1, 2, 3, 4, 5, 6, 7, 8], 0, 2, 1)), 8)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
