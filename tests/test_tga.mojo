# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.tga`.

The files under `assets/tga/` were written by PIL from one seven-by-five
picture, and each `_ref.png` beside one is the same picture as a PNG. TGA
is lossless, so the two must agree to the bit. Everything else is a file
assembled by hand, a header and a few pixels.
"""

from render.png import DecodedImage
from render.png import decode as decode_png
from render.srgb import SRGB
from render.texture import BILINEAR, REPEAT, texture_from
from render.tga import (
    COLOR_MAPPED,
    GRAYSCALE,
    RLE_COLOR_MAPPED,
    RLE_GRAYSCALE,
    RLE_TRUE_COLOR,
    TRUE_COLOR,
    TgaImageType,
    decode,
    unpack_pixels,
)
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def fixture(name: String) raises -> List[UInt8]:
    """Return one of the files under assets/tga/."""
    return Path("assets/tga/" + name).read_bytes()


def header(
    kind: Int,
    width: Int,
    height: Int,
    pixel_bits: Int,
    descriptor: Int = 0,
    map_type: Int = 0,
    map_first: Int = 0,
    map_length: Int = 0,
    map_bits: Int = 0,
    id_length: Int = 0,
) -> List[UInt8]:
    """Return an eighteen-byte TGA header, and the image id after it."""
    var out: List[UInt8] = [
        UInt8(id_length),
        UInt8(map_type),
        UInt8(kind),
        UInt8(map_first & 0xFF),
        UInt8(map_first >> 8),
        UInt8(map_length & 0xFF),
        UInt8(map_length >> 8),
        UInt8(map_bits),
        0,
        0,
        0,
        0,
        UInt8(width & 0xFF),
        UInt8(width >> 8),
        UInt8(height & 0xFF),
        UInt8(height >> 8),
        UInt8(pixel_bits),
        UInt8(descriptor),
    ]
    for index in range(id_length):
        out.append(UInt8(65 + index))
    return out^


def plus(bytes: List[UInt8], more: List[Int]) -> List[UInt8]:
    """Return `bytes` with `more` after them."""
    var out = bytes.copy()
    for value in more:
        out.append(UInt8(value))
    return out^


def refused(bytes: List[UInt8]) raises:
    """Assert the reader refuses `bytes`."""
    with assert_raises():
        _ = decode(bytes)


def assert_rgba(
    image: DecodedImage, x: Int, y: Int, r: Int, g: Int, b: Int, a: Int
) raises:
    """Assert the pixel at (x, y) holds these four channels."""
    var seen = image.get_pixel(x, y)
    assert_equal(seen.r, UInt8(r))
    assert_equal(seen.g, UInt8(g))
    assert_equal(seen.b, UInt8(b))
    assert_equal(seen.a, UInt8(a))


def assert_same(image: DecodedImage, reference: DecodedImage) raises:
    """Assert two images agree to the bit."""
    assert_equal(image.width, reference.width)
    assert_equal(image.height, reference.height)
    for index in range(len(reference.pixels)):
        assert_equal(image.pixels[index], reference.pixels[index])


# --- the type ---------------------------------------------------------------


def test_an_image_type_knows_what_its_pixels_are() raises:
    for kind in [
        COLOR_MAPPED,
        TRUE_COLOR,
        GRAYSCALE,
        RLE_COLOR_MAPPED,
        RLE_TRUE_COLOR,
        RLE_GRAYSCALE,
    ]:
        assert_true(kind.is_valid())
    # No image, and Huffman-coded color maps: not types this reads.
    assert_false(TgaImageType(0).is_valid())
    assert_false(TgaImageType(32).is_valid())
    assert_true(RLE_COLOR_MAPPED.is_color_mapped())
    assert_false(TRUE_COLOR.is_color_mapped())
    assert_true(RLE_GRAYSCALE.is_gray())
    assert_false(COLOR_MAPPED.is_gray())
    assert_true(RLE_TRUE_COLOR.is_run_length())
    assert_false(GRAYSCALE.is_run_length())


# --- files PIL wrote --------------------------------------------------------


def test_files_pil_wrote_decode_to_their_pngs_exactly() raises:
    # Run-length true color from the bottom up; 32-bit true color from
    # the top down; run-length gray with alpha; an uncompressed map.
    for name in ["rgb_rle", "rgba_top", "gray_alpha_rle", "palette"]:
        var image = decode(fixture(name + ".tga"))
        assert_equal(image.color_space, SRGB)
        assert_equal(image.width, 7)
        assert_equal(image.height, 5)
        assert_same(image, decode_png(fixture(name + "_ref.png")))


def test_a_decoded_file_becomes_a_texture() raises:
    var skin = texture_from(decode(fixture("rgba_top.tga")), REPEAT, BILINEAR)
    assert_equal(skin.width, 7)
    assert_equal(skin.color_space, SRGB)


# --- files assembled by hand ------------------------------------------------


def test_the_origin_bits_say_which_corner_comes_first() raises:
    # Four pixels in file order: red, green, blue, white.
    var pixels: List[Int] = [0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255]
    # From the bottom left, as TGA's default is: the first row is the
    # bottom one.
    var up = decode(plus(header(2, 2, 2, 24), pixels))
    assert_rgba(up, 0, 1, 255, 0, 0, 255)
    assert_rgba(up, 1, 1, 0, 255, 0, 255)
    assert_rgba(up, 0, 0, 0, 0, 255, 255)
    assert_rgba(up, 1, 0, 255, 255, 255, 255)
    # From the bottom right, the top left and the top right.
    var mirrored = decode(plus(header(2, 2, 2, 24, descriptor=0x10), pixels))
    assert_rgba(mirrored, 1, 1, 255, 0, 0, 255)
    assert_rgba(mirrored, 0, 1, 0, 255, 0, 255)
    var down = decode(plus(header(2, 2, 2, 24, descriptor=0x20), pixels))
    assert_rgba(down, 0, 0, 255, 0, 0, 255)
    assert_rgba(down, 0, 1, 0, 0, 255, 255)
    var both = decode(plus(header(2, 2, 2, 24, descriptor=0x30), pixels))
    assert_rgba(both, 1, 0, 255, 0, 0, 255)
    assert_rgba(both, 0, 1, 255, 255, 255, 255)


def test_every_pixel_kind_widens_to_rgba() raises:
    # 32-bit true color keeps its alpha; the attribute bits are not read.
    var color = decode(plus(header(2, 1, 1, 32, descriptor=0x08), [1, 2, 3, 4]))
    assert_rgba(color, 0, 0, 3, 2, 1, 4)
    # Gray at eight bits is opaque; at sixteen the second byte is alpha.
    var gray = decode(plus(header(3, 1, 1, 8), [77]))
    assert_rgba(gray, 0, 0, 77, 77, 77, 255)
    var gray_alpha = decode(plus(header(3, 1, 1, 16), [77, 9]))
    assert_rgba(gray_alpha, 0, 0, 77, 77, 77, 9)


def test_a_color_map_starts_at_its_first_entry_index() raises:
    # Two entries numbered two and three, after an image id of three
    # bytes: index three is the second, which is blue, green and red.
    var mapped = header(
        1,
        2,
        1,
        8,
        map_type=1,
        map_first=2,
        map_length=2,
        map_bits=24,
        id_length=3,
    )
    var image = decode(plus(mapped, [10, 20, 30, 40, 50, 60, 3, 2]))
    assert_rgba(image, 0, 0, 60, 50, 40, 255)
    assert_rgba(image, 1, 0, 30, 20, 10, 255)
    # An index below the first entry, and one past the last.
    refused(plus(mapped, [10, 20, 30, 40, 50, 60, 1, 2]))
    refused(plus(mapped, [10, 20, 30, 40, 50, 60, 2, 4]))
    # A map of no entries has no index at all.
    refused(
        plus(header(1, 1, 1, 8, map_type=1, map_bits=24), [0]),
    )
    # A map cut short.
    refused(plus(mapped, [10, 20, 30, 40, 50]))


def test_run_length_packets_repeat_or_copy_and_cross_rows() raises:
    # A three-by-two gray image: a packet repeating 9 four times, which
    # crosses into the second row, then a raw packet of 1 and 2.
    var image = decode(
        plus(header(11, 3, 2, 8, descriptor=0x20), [0x83, 9, 0x01, 1, 2])
    )
    assert_rgba(image, 0, 0, 9, 9, 9, 255)
    assert_rgba(image, 0, 1, 9, 9, 9, 255)
    assert_rgba(image, 1, 1, 1, 1, 1, 255)
    assert_rgba(image, 2, 1, 2, 2, 2, 255)
    # A run-length color map.
    var mapped = header(9, 2, 1, 8, map_type=1, map_length=1, map_bits=24)
    var red = decode(plus(mapped, [0, 0, 255, 0x81, 0]))
    assert_rgba(red, 1, 0, 255, 0, 0, 255)
    # A packet past the image; the file ending before a packet, inside
    # a repeated pixel and inside raw pixels.
    var gray = header(11, 2, 1, 8)
    refused(plus(gray, [0x82, 9]))
    refused(plus(gray, [0x80, 9]))
    refused(plus(header(10, 1, 1, 24), [0x80, 1, 2]))
    refused(plus(gray, [0x01, 1]))


def test_unpacking_checks_its_type_and_reads_no_pixels_for_none() raises:
    var bytes: List[UInt8] = [1, 2, 3]
    with assert_raises():
        _ = unpack_pixels(TgaImageType(0), bytes, 0, 1, 1)
    assert_equal(len(unpack_pixels(TRUE_COLOR, bytes, 0, 0, 3)), 0)
    assert_equal(len(unpack_pixels(RLE_TRUE_COLOR, bytes, 0, 0, 3)), 0)
    assert_equal(len(unpack_pixels(GRAYSCALE, bytes, 1, 2, 1)), 2)


def test_a_header_is_checked_field_by_field() raises:
    # Too short; no image; a Huffman-coded type.
    refused(List[UInt8](length=17, fill=0))
    refused(plus(header(0, 1, 1, 24), [0, 0, 0]))
    refused(plus(header(32, 1, 1, 8), [0]))
    # A color-mapped type without a map, with 32-bit entries, with more
    # than 256 entries, or with 16-bit indices.
    refused(plus(header(1, 1, 1, 8), [0]))
    refused(
        plus(
            header(1, 1, 1, 8, map_type=1, map_length=1, map_bits=32),
            [0, 0, 0, 0, 0],
        )
    )
    var long_map = header(1, 1, 1, 8, map_type=1, map_length=257, map_bits=24)
    for _ in range(257 * 3 + 1):
        long_map.append(0)
    refused(long_map)
    refused(
        plus(
            header(1, 1, 1, 16, map_type=1, map_length=1, map_bits=24),
            [0, 0, 0, 0, 0],
        )
    )
    # A map with true color, which three.js refuses too.
    refused(plus(header(2, 1, 1, 24, map_type=1), [0, 0, 0]))
    # Gray that is neither 8 nor 16 bits, and true color that is neither
    # 24 nor 32: 16-bit true color is refused by name.
    refused(plus(header(3, 1, 1, 24), [0, 0, 0]))
    with assert_raises(contains="16-bit"):
        _ = decode(plus(header(2, 1, 1, 16), [0, 0]))
    # No width, no height, and more pixels than any texture here.
    refused(header(2, 0, 1, 24))
    refused(header(2, 1, 0, 24))
    refused(header(2, 65535, 65535, 24))
    # Pixels cut short.
    refused(plus(header(2, 2, 1, 24), [0, 0, 0, 0, 0]))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
