# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.exr`.

Every file is assembled here, a header and its blocks. An uncompressed
block is written by hand. A compressed block is the bytes the OpenEXR
library itself wrote for a small image, copied out of its file: RLE, ZIPS,
ZIP and PIZ, the last for half and float channels and for widths and
heights that do not halve evenly. The PIZ Huffman streams that test the
table's corners -- long codes, runs, collisions -- were packed by a
reference encoder of OpenEXR's format, and the 16-bit wavelet is checked
against a line-for-line port of three.js's `wav2Decode`.
"""

from render.exr import (
    FLOAT_SAMPLES,
    HALF_SAMPLES,
    NO_COMPRESSION,
    PIZ_COMPRESSION,
    RLE_COMPRESSION,
    UINT_SAMPLES,
    ZIPS_COMPRESSION,
    ZIP_COMPRESSION,
    ExrCompression,
    ExrPixelType,
    decode,
    half_to_float,
    huffman_decode,
    lines_per_block,
    read_header,
    sample_bytes,
    wavelet_decode,
)
from render.float_image import FloatImage
from render.png import zlib_stream
from render.texture import FLOAT_TYPE, float_texture_from
from std.math import isinf, isnan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


# --- building files ---------------------------------------------------------


def push32(mut out: List[UInt8], value: Int):
    """Append a little-endian 32-bit integer."""
    out.append(UInt8(value & 0xFF))
    out.append(UInt8((value >> 8) & 0xFF))
    out.append(UInt8((value >> 16) & 0xFF))
    out.append(UInt8((value >> 24) & 0xFF))


def push_text(mut out: List[UInt8], text: String):
    """Append a string and its null byte."""
    for byte in text.as_bytes():
        out.append(byte)
    out.append(0)


def channel(
    name: String, kind: Int, x_sampling: Int = 1, y_sampling: Int = 1
) -> List[UInt8]:
    """Return one entry of a channel list."""
    var out = List[UInt8]()
    push_text(out, name)
    push32(out, kind)
    for _ in range(4):
        out.append(0)
    push32(out, x_sampling)
    push32(out, y_sampling)
    return out^


def chlist(var entries: List[List[UInt8]]) -> List[UInt8]:
    """Return a channel list: the entries, then a null byte."""
    var out = List[UInt8]()
    for entry in entries:
        out.extend(entry.copy())
    out.append(0)
    return out^


def rgb(kind: Int = 1) -> List[UInt8]:
    """Return a channel list of B, G and R, the order OpenEXR sorts them."""
    return chlist([channel("B", kind), channel("G", kind), channel("R", kind)])


def attribute(
    mut out: List[UInt8], name: String, kind: String, value: List[UInt8]
):
    """Append one header attribute."""
    push_text(out, name)
    push_text(out, kind)
    push32(out, len(value))
    out.extend(value.copy())


def box(x_min: Int, y_min: Int, x_max: Int, y_max: Int) -> List[UInt8]:
    """Return a `box2i` value."""
    var out = List[UInt8]()
    push32(out, x_min)
    push32(out, y_min)
    push32(out, x_max)
    push32(out, y_max)
    return out^


def preamble(version: Int = 2, flags: Int = 0) -> List[UInt8]:
    """Return the magic number and the version field."""
    var out: List[UInt8] = [0x76, 0x2F, 0x31, 0x01]
    out.append(UInt8(version))
    out.append(UInt8(flags))
    out.append(0)
    out.append(0)
    return out^


def exr(
    channels: List[UInt8],
    compression: Int,
    window: List[UInt8],
    lines: List[Int],
    var blocks: List[List[UInt8]],
) -> List[UInt8]:
    """Return a whole file: the header, the offset table and the blocks.

    Args:
        channels: The `chlist` value.
        compression: The compression byte.
        window: The `dataWindow` value.
        lines: Each block's first line, in the file's own numbering.
        blocks: Each block's data.
    """
    var out = preamble()
    attribute(out, "channels", "chlist", channels)
    attribute(out, "compression", "compression", [UInt8(compression)])
    attribute(out, "dataWindow", "box2i", window)
    # An attribute the reader does not need, read past by its size.
    attribute(out, "pixelAspectRatio", "float", [0, 0, 128, 63])
    out.append(0)
    var table_at = len(out)
    for _ in range(len(blocks)):
        push32(out, 0)
        push32(out, 0)
    for index in range(len(blocks)):
        var at = len(out)
        out[table_at + index * 8] = UInt8(at & 0xFF)
        out[table_at + index * 8 + 1] = UInt8((at >> 8) & 0xFF)
        push32(out, lines[index])
        push32(out, len(blocks[index]))
        out.extend(blocks[index].copy())
    return out^


def halves(bits: List[Int]) -> List[UInt8]:
    """Return halves' bits as little-endian bytes."""
    var out = List[UInt8]()
    for value in bits:
        out.append(UInt8(value & 0xFF))
        out.append(UInt8(value >> 8))
    return out^


def floats(values: List[Float32]) -> List[UInt8]:
    """Return floats as little-endian bytes."""
    var out = List[UInt8]()
    for value in values:
        push32(out, Int(bitcast[DType.uint32](value)))
    return out^


def plus(var bytes: List[UInt8], more: List[UInt8]) -> List[UInt8]:
    """Return `bytes` with `more` after them."""
    bytes.extend(more.copy())
    return bytes^


def assert_pixel(
    image: FloatImage,
    x: Int,
    y: Int,
    r: Float32,
    g: Float32,
    b: Float32,
    a: Float32,
) raises:
    """Assert the pixel at (x, y) holds these four floats exactly."""
    var seen = image.get_pixel(x, y)
    assert_equal(seen[0], r)
    assert_equal(seen[1], g)
    assert_equal(seen[2], b)
    assert_equal(seen[3], a)


def refused(bytes: List[UInt8], contains: String) raises:
    """Assert the reader refuses `bytes`, saying `contains`."""
    with assert_raises(contains=contains):
        _ = decode(bytes)


def half_rgb_file(
    compression: Int, var blocks: List[List[UInt8]], lines: List[Int]
) -> List[UInt8]:
    """Return a 3x2 half RGB file, the image the OpenEXR blocks below hold."""
    return exr(rgb(), compression, box(0, 0, 2, 1), lines, blocks^)


def assert_half_rgb(image: FloatImage) raises:
    """Assert `image` is the 3x2 picture `half_rgb_file` names."""
    assert_equal(image.width, 3)
    assert_equal(image.height, 2)
    assert_pixel(image, 0, 0, 0.5, 0.25, 1, 1)
    assert_pixel(image, 1, 0, 1, 0, 2, 1)
    assert_pixel(image, 2, 0, 2, 3, 3, 1)
    assert_pixel(image, 0, 1, 4, 0.125, 4, 1)
    assert_pixel(image, 1, 1, -1.5, 65504, 5, 1)
    assert_pixel(image, 2, 1, 1000, Float32(17) * Float32(2.0**-24), 6, 1)


def raw_row(b: List[Int], g: List[Int], r: List[Int]) -> List[UInt8]:
    """Return one uncompressed scanline of B, G and R halves."""
    return plus(plus(halves(b), halves(g)), halves(r))


# Row 0 and row 1 of the 3x2 picture, as halves: B, G, R.
def row_zero() -> List[UInt8]:
    """Return the first scanline, uncompressed."""
    return raw_row(
        [0x3C00, 0x4000, 0x4200], [0x3400, 0, 0x4200], [0x3800, 0x3C00, 0x4000]
    )


def row_one() -> List[UInt8]:
    """Return the second scanline, uncompressed."""
    return raw_row(
        [0x4400, 0x4500, 0x4600],
        [0x3000, 0x7BFF, 0x0011],
        [0x4400, 0xBE00, 0x63D0],
    )


# --- the types --------------------------------------------------------------


def test_a_compression_says_how_many_lines_a_block_holds() raises:
    assert_equal(lines_per_block(NO_COMPRESSION), 1)
    assert_equal(lines_per_block(RLE_COMPRESSION), 1)
    assert_equal(lines_per_block(ZIPS_COMPRESSION), 1)
    assert_equal(lines_per_block(ZIP_COMPRESSION), 16)
    assert_equal(lines_per_block(PIZ_COMPRESSION), 32)
    # PXR24, and a byte below the named ones: not read.
    assert_false(ExrCompression(5).is_valid())
    assert_false(ExrCompression(-1).is_valid())
    with assert_raises(contains="PXR24"):
        _ = lines_per_block(ExrCompression(5))
    with assert_raises(contains="PXR24"):
        _ = lines_per_block(ExrCompression(-1))


def test_a_pixel_type_says_how_wide_a_sample_is() raises:
    assert_equal(sample_bytes(UINT_SAMPLES), 4)
    assert_equal(sample_bytes(HALF_SAMPLES), 2)
    assert_equal(sample_bytes(FLOAT_SAMPLES), 4)
    assert_false(ExrPixelType(3).is_valid())
    with assert_raises(contains="UINT, HALF or FLOAT"):
        _ = sample_bytes(ExrPixelType(3))


def test_a_half_widens_to_the_same_number() raises:
    assert_equal(half_to_float(0x0000), 0)
    assert_equal(half_to_float(0x3C00), 1)
    assert_equal(half_to_float(0xC000), -2)
    assert_equal(half_to_float(0x3555), Float32(0.333251953125))
    assert_equal(half_to_float(0x7BFF), 65504)
    # Subnormals: the fraction times two to the minus twenty-four.
    assert_equal(half_to_float(0x0001), Float32(2.0**-24))
    assert_equal(half_to_float(0x8003), -3 * Float32(2.0**-24))
    assert_equal(half_to_float(0x03FF), 1023 * Float32(2.0**-24))
    # The smallest normal.
    assert_equal(half_to_float(0x0400), Float32(2.0**-14))
    assert_true(isinf(half_to_float(0x7C00)))
    assert_true(half_to_float(0xFC00) < 0)
    assert_true(isinf(half_to_float(0xFC00)))
    assert_true(isnan(half_to_float(0x7E00)))


# --- uncompressed files -----------------------------------------------------


def test_an_uncompressed_file_reads_every_half() raises:
    var image = decode(half_rgb_file(0, [row_zero(), row_one()], [0, 1]))
    assert_half_rgb(image)


def test_blocks_are_placed_by_the_line_they_name() raises:
    # Written bottom line first, as a DECREASING_Y file is.
    var image = decode(half_rgb_file(0, [row_one(), row_zero()], [1, 0]))
    assert_half_rgb(image)


def test_the_data_window_can_start_anywhere() raises:
    # The window starts at a negative column and line five: the first line
    # of the window is the first row out.
    var bytes = exr(
        rgb(), 0, box(-4, 5, -2, 6), [5, 6], [row_zero(), row_one()]
    )
    var header = read_header(bytes)
    assert_equal(header.x_min, -4)
    assert_equal(header.width(), 3)
    assert_half_rgb(decode(bytes))


def test_float_channels_and_alpha_are_read_as_they_are() raises:
    var channels = chlist(
        [
            channel("A", 2),
            channel("B", 2),
            channel("G", 1),
            channel("R", 2),
            # An id channel: read past, never shown.
            channel("id", 0),
        ]
    )
    var line = plus(
        plus(
            plus(floats([0.5, 0.0]), floats([3.0, 4.0])),
            halves([0x3C00, 0x4000]),
        ),
        plus(floats([1e6, -7.25]), [9, 9, 9, 9, 9, 9, 9, 9]),
    )
    var image = decode(exr(channels, 0, box(0, 0, 1, 0), [0], [line^]))
    assert_pixel(image, 0, 0, 1e6, 1, 3, 0.5)
    assert_pixel(image, 1, 0, -7.25, 2, 4, 0)


def test_a_luminance_image_is_gray() raises:
    # Y alone is gray, alpha one; an A beside it is read past, as three.js
    # reads Y alone.
    var channels = chlist([channel("A", 1), channel("Y", 1)])
    var line = plus(halves([0x3800, 0x3800]), halves([0x3C00, 0x4400]))
    var image = decode(exr(channels, 0, box(0, 0, 1, 0), [0], [line^]))
    assert_pixel(image, 0, 0, 1, 1, 1, 1)
    assert_pixel(image, 1, 0, 4, 4, 4, 1)


def test_an_hdr_image_becomes_a_float_texture() raises:
    var image = decode(half_rgb_file(0, [row_zero(), row_one()], [0, 1]))
    var texture = float_texture_from(image)
    assert_true(texture.texel_type == FLOAT_TYPE)
    # 1000 survives: a float texture does not clip light at one.
    assert_equal(texture.wrapped_texel(2, 1).r, 1000)


# --- compressed files, as OpenEXR wrote them --------------------------------


def test_an_rle_file_reads_as_the_uncompressed_one() raises:
    # Row zero compressed to fourteen bytes; row one did not compress and
    # is stored as it stands, as OpenEXR stores any block that grows.
    var compressed: List[UInt8] = [
        255,
        0,
        7,
        128,
        247,
        188,
        132,
        130,
        114,
        76,
        194,
        118,
        132,
        132,
    ]
    assert_half_rgb(decode(half_rgb_file(1, [compressed^, row_one()], [0, 1])))


def pattern(x: Int, y: Int, k: Int) -> Float32:
    """Return the test picture OpenEXR compressed: five values in bands."""
    var values: List[Float32] = [0, 0.5, 1, 2, 8]
    return values[(x // 2 + y // 2 + k) % 5]


def test_a_zips_file_reads_its_bands() raises:
    var block: List[UInt8] = [
        120,
        94,
        99,
        104,
        32,
        13,
        236,
        105,
        104,
        105,
        232,
        104,
        176,
        104,
        216,
        1,
        164,
        65,
        172,
        2,
        40,
        13,
        19,
        113,
        128,
        203,
        64,
        68,
        0,
        242,
        152,
        47,
        189,
    ]
    var image = decode(
        exr(rgb(), 2, box(0, 0, 15, 1), [0, 1], [block.copy(), block.copy()])
    )
    for y in range(2):
        for x in range(16):
            # Both rows are the same bands: y // 2 is zero for both.
            assert_pixel(
                image,
                x,
                y,
                pattern(x, 0, 0),
                pattern(x, 0, 1),
                pattern(x, 0, 2),
                1,
            )


def test_a_zip_file_reads_across_two_blocks() raises:
    # Eighteen lines of Y: sixteen in a compressed block, then two that
    # did not compress and are stored as they stand.
    var first: List[UInt8] = [
        120,
        94,
        99,
        104,
        160,
        20,
        236,
        104,
        240,
        0,
        226,
        134,
        134,
        150,
        134,
        26,
        32,
        70,
        208,
        29,
        13,
        21,
        64,
        220,
        208,
        96,
        209,
        112,
        2,
        136,
        113,
        169,
        3,
        0,
        237,
        225,
        63,
        193,
    ]
    var second: List[UInt8] = [
        0,
        64,
        0,
        64,
        0,
        72,
        0,
        72,
        0,
        64,
        0,
        64,
        0,
        72,
        0,
        72,
    ]
    var image = decode(
        exr(
            chlist([channel("Y", 1)]),
            3,
            box(0, 0, 3, 17),
            [0, 16],
            [first^, second^],
        )
    )
    assert_equal(image.height, 18)
    for y in range(18):
        for x in range(4):
            var gray = pattern(x, y, 0)
            assert_pixel(image, x, y, gray, gray, gray, 1)


def near(x: Int, y: Int, k: Int, wide: Int, tall: Int) -> Float32:
    """Return the picture the PIZ blocks hold: one, a hair more at the
    center and at the top right corner."""
    var bits = 0x3C00
    if x == wide // 2 and y == tall // 2:
        bits += 1 + k
    if x == wide - 1 and y == 0:
        bits += 2
    return half_to_float(UInt16(bits))


def test_a_piz_file_undoes_its_wavelet_on_odd_sides() raises:
    # Five by five: neither side halves evenly.
    var block: List[UInt8] = [
        128,
        7,
        128,
        7,
        15,
        38,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        4,
        0,
        0,
        0,
        4,
        0,
        0,
        0,
        112,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        4,
        32,
        196,
        16,
        121,
        243,
        215,
        66,
        218,
        243,
        231,
        174,
        155,
        107,
        207,
        159,
        123,
        109,
    ]
    var image = decode(exr(rgb(), 4, box(0, 0, 4, 4), [0], [block^]))
    for y in range(5):
        for x in range(5):
            assert_pixel(
                image,
                x,
                y,
                near(x, y, 0, 5, 5),
                near(x, y, 1, 5, 5),
                near(x, y, 2, 5, 5),
                1,
            )


def test_a_piz_file_of_one_channel_taller_than_wide() raises:
    var block: List[UInt8] = [
        128,
        7,
        128,
        7,
        7,
        31,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        3,
        0,
        0,
        0,
        3,
        0,
        0,
        0,
        58,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        4,
        32,
        195,
        120,
        241,
        239,
        222,
        247,
        239,
        219,
        64,
    ]
    var image = decode(
        exr(chlist([channel("Y", 1)]), 4, box(0, 0, 4, 8), [0], [block^])
    )
    for y in range(9):
        for x in range(5):
            var gray = near(x, y, 0, 5, 9)
            assert_pixel(image, x, y, gray, gray, gray, 1)


def test_a_piz_file_of_float_channels() raises:
    var block: List[UInt8] = [
        224,
        7,
        105,
        8,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        53,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        8,
        0,
        0,
        0,
        7,
        0,
        0,
        0,
        204,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        4,
        49,
        4,
        16,
        65,
        5,
        20,
        190,
        251,
        255,
        254,
        251,
        239,
        143,
        46,
        127,
        255,
        203,
        159,
        247,
        199,
        151,
        255,
        241,
        229,
        207,
        250,
        117,
        255,
        254,
        157,
        120,
        48,
    ]
    var channels = chlist(
        [channel("A", 2), channel("B", 2), channel("G", 2), channel("R", 2)]
    )
    var image = decode(exr(channels, 4, box(0, 0, 5, 2), [0], [block^]))
    for y in range(3):
        for x in range(6):
            assert_pixel(
                image,
                x,
                y,
                pattern(x, y, 0) * 100,
                pattern(x, y, 1),
                pattern(x, y, 2),
                0.5,
            )


def test_a_piz_file_of_one_value() raises:
    # Every value one half: a bitmap of one byte, and a wavelet of zeros.
    var block: List[UInt8] = [
        0,
        7,
        0,
        7,
        1,
        28,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        2,
        0,
        0,
        0,
        3,
        0,
        0,
        0,
        39,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        4,
        32,
        128,
        40,
        113,
        67,
        138,
        28,
    ]
    var image = decode(exr(rgb(), 4, box(0, 0, 3, 3), [0], [block^]))
    for y in range(4):
        for x in range(4):
            assert_pixel(image, x, y, 0.5, 0.5, 0.5, 1)


def test_a_piz_file_of_zeros_has_an_empty_bitmap() raises:
    # The smallest nonzero byte past the largest: no bitmap bytes follow.
    var block: List[UInt8] = [
        255,
        31,
        0,
        0,
        24,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        2,
        0,
        0,
        0,
        10,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        4,
        16,
        75,
        192,
    ]
    var image = decode(exr(rgb(), 4, box(0, 0, 3, 3), [0], [block^]))
    for y in range(4):
        for x in range(4):
            assert_pixel(image, x, y, 0, 0, 0, 1)


# --- the Huffman coder and the wavelet --------------------------------------


def long_codes() -> List[UInt8]:
    """Return a stream of a complete code with lengths one to seventeen,
    holding 16, 15, 14, 0, 16 and 3; symbol 17 is the run."""
    return [
        0,
        0,
        0,
        0,
        17,
        0,
        0,
        0,
        14,
        0,
        0,
        0,
        70,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        4,
        32,
        196,
        20,
        97,
        200,
        36,
        162,
        204,
        52,
        227,
        208,
        69,
        16,
        0,
        0,
        0,
        0,
        128,
        1,
        128,
        0,
        4,
    ]


def test_long_codes_are_found_past_the_decoding_table() raises:
    var bytes = long_codes()
    var values = huffman_decode(bytes, 0, len(bytes), 6)
    assert_equal(values, [16, 15, 14, 0, 16, 3])


def test_the_run_symbol_repeats_the_value_before_it() raises:
    var bytes: List[UInt8] = [
        0,
        0,
        0,
        0,
        17,
        0,
        0,
        0,
        14,
        0,
        0,
        0,
        55,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        4,
        32,
        196,
        20,
        97,
        200,
        36,
        162,
        204,
        52,
        227,
        208,
        69,
        16,
        16,
        0,
        8,
        32,
        0,
        4,
        2,
    ]
    # Three, four more threes, no more, then zero.
    var values = huffman_decode(bytes, 0, len(bytes), 6)
    assert_equal(values, [3, 3, 3, 3, 3, 0])
    # A run that would pass the end is refused.
    with assert_raises(contains="run runs past"):
        _ = huffman_decode(bytes, 0, len(bytes), 3)
    var second: List[UInt8] = [
        0,
        0,
        0,
        0,
        17,
        0,
        0,
        0,
        14,
        0,
        0,
        0,
        26,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        4,
        32,
        196,
        20,
        97,
        200,
        36,
        162,
        204,
        52,
        227,
        208,
        69,
        16,
        128,
        0,
        64,
        192,
    ]
    assert_equal(huffman_decode(second, 0, len(second), 4), [0, 0, 0, 0])


def test_a_run_needs_a_value_before_it() raises:
    var bytes: List[UInt8] = [
        0,
        0,
        0,
        0,
        17,
        0,
        0,
        0,
        14,
        0,
        0,
        0,
        25,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        4,
        32,
        196,
        20,
        97,
        200,
        36,
        162,
        204,
        52,
        227,
        208,
        69,
        16,
        0,
        0,
        129,
        0,
    ]
    with assert_raises(contains="run runs past"):
        _ = huffman_decode(bytes, 0, len(bytes), 8)


def test_a_value_past_the_end_is_refused() raises:
    var bytes = long_codes()
    with assert_raises(contains="runs past its block"):
        _ = huffman_decode(bytes, 0, len(bytes), 5)
    with assert_raises(contains="does not fill"):
        _ = huffman_decode(bytes, 0, len(bytes), 7)


def test_a_code_the_table_does_not_hold_is_refused() raises:
    # Twenty-bit codes, the data cut after sixteen bits of one.
    var cut: List[UInt8] = [
        0,
        0,
        0,
        0,
        20,
        0,
        0,
        0,
        16,
        0,
        0,
        0,
        16,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        4,
        32,
        196,
        20,
        97,
        200,
        36,
        162,
        204,
        52,
        227,
        208,
        69,
        36,
        212,
        80,
        0,
        0,
    ]
    with assert_raises(contains="not in its table"):
        _ = huffman_decode(cut, 0, len(cut), 1)
    # Eight bits left over at the end that begin only long codes.
    var tail: List[UInt8] = [
        0,
        0,
        0,
        0,
        17,
        0,
        0,
        0,
        14,
        0,
        0,
        0,
        8,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        4,
        32,
        196,
        20,
        97,
        200,
        36,
        162,
        204,
        52,
        227,
        208,
        69,
        16,
        0,
        1,
    ]
    with assert_raises(contains="not in its table"):
        _ = huffman_decode(tail, 0, len(tail), 1)
    # Three two-bit codes leave 11 unclaimed, and the data is all ones.
    var unclaimed: List[UInt8] = [
        0,
        0,
        0,
        0,
        2,
        0,
        0,
        0,
        3,
        0,
        0,
        0,
        16,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        8,
        32,
        128,
        255,
        255,
    ]
    with assert_raises(contains="not in its table"):
        _ = huffman_decode(unclaimed, 0, len(unclaimed), 1)


def test_a_table_whose_codes_collide_is_refused() raises:
    # Three codes of one bit: the third does not fit.
    var misfit: List[UInt8] = [
        0,
        0,
        0,
        0,
        2,
        0,
        0,
        0,
        3,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        4,
        16,
        64,
    ]
    with assert_raises(contains="does not fit"):
        _ = huffman_decode(misfit, 0, len(misfit), 0)
    # A two-bit code, then a one-bit code over it.
    var short: List[UInt8] = [
        0,
        0,
        0,
        0,
        2,
        0,
        0,
        0,
        3,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        8,
        16,
        64,
    ]
    with assert_raises(contains="share a prefix"):
        _ = huffman_decode(short, 0, len(short), 0)
    # A one-bit code, then a sixteen-bit code under it.
    var long_after: List[UInt8] = [
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        2,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        5,
        0,
    ]
    with assert_raises(contains="share a prefix"):
        _ = huffman_decode(long_after, 0, len(long_after), 0)
    # A sixteen-bit code, then a one-bit code over it.
    var short_after: List[UInt8] = [
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        2,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        64,
        16,
    ]
    with assert_raises(contains="share a prefix"):
        _ = huffman_decode(short_after, 0, len(short_after), 0)


def test_runs_of_zero_lengths_in_the_table() raises:
    # Lengths for 0, 4, 15 and 16, with a short run of three zeros and a
    # long run of ten between them.
    var bytes: List[UInt8] = [
        0,
        0,
        0,
        0,
        16,
        0,
        0,
        0,
        6,
        0,
        0,
        0,
        8,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        11,
        192,
        191,
        4,
        8,
        32,
        24,
    ]
    assert_equal(huffman_decode(bytes, 0, len(bytes), 4), [0, 4, 15, 0])
    # A short run of five from the second-to-last symbol, and a long run
    # of six from the first of four: both run past the last symbol.
    var short: List[UInt8] = [
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        248,
    ]
    with assert_raises(contains="run of zeros"):
        _ = huffman_decode(short, 0, len(short), 0)
    var long: List[UInt8] = [
        0,
        0,
        0,
        0,
        3,
        0,
        0,
        0,
        2,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        252,
        0,
    ]
    with assert_raises(contains="run of zeros"):
        _ = huffman_decode(long, 0, len(long), 0)


def test_a_huffman_header_is_checked() raises:
    var bytes = long_codes()
    # Cut short of its twenty bytes, and cut in the table.
    with assert_raises(contains="cut short"):
        _ = huffman_decode(bytes, 0, 19, 6)
    with assert_raises(contains="cut short"):
        _ = huffman_decode(bytes, 0, 24, 6)
    # More bits of code than the block holds.
    with assert_raises(contains="run past their block"):
        _ = huffman_decode(bytes, 0, len(bytes) - 1, 6)
    # A first or last symbol past sixteen bits.
    var first = long_codes()
    first[2] = 2
    with assert_raises(contains="past sixteen bits"):
        _ = huffman_decode(first, 0, len(first), 6)
    var last = long_codes()
    last[6] = 2
    with assert_raises(contains="past sixteen bits"):
        _ = huffman_decode(last, 0, len(last), 6)
    # No symbols and no bits decode to nothing.
    var empty: List[UInt8] = [
        5,
        0,
        0,
        0,
        4,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
    ]
    assert_equal(len(huffman_decode(empty, 0, len(empty), 0)), 0)


def test_the_wavelet_undoes_both_forms() raises:
    var input: List[Int] = [
        31190,
        17094,
        48490,
        62135,
        8588,
        1725,
        61503,
        33994,
        30714,
        25132,
        61638,
        62436,
        52053,
        19741,
        30398,
    ]
    var wide = input.copy()
    wavelet_decode(wide, 0, 5, 1, 3, 5, 20000)
    assert_equal(
        wide,
        [
            39592,
            57282,
            22313,
            10357,
            53922,
            23500,
            4389,
            22114,
            8104,
            61558,
            60088,
            30420,
            29156,
            42183,
            30398,
        ],
    )
    var narrow = input.copy()
    wavelet_decode(narrow, 0, 5, 1, 3, 5, 100)
    assert_equal(
        narrow,
        [
            39592,
            24514,
            38697,
            26741,
            21154,
            39884,
            20773,
            54882,
            8104,
            61558,
            60088,
            63188,
            61924,
            42183,
            30398,
        ],
    )
    # One value has nothing to undo.
    var one: List[Int] = [7]
    wavelet_decode(one, 0, 1, 1, 1, 1, 100)
    assert_equal(one, [7])


# --- refusals ---------------------------------------------------------------


def test_the_preamble_is_checked() raises:
    refused([0x76, 0x2F, 0x31], "cut short")
    var wrong = preamble()
    wrong[0] = 0
    refused(wrong, "not an OpenEXR file")
    refused(preamble(version=1), "version 2")
    refused(preamble(flags=0x02), "tiled")
    refused(preamble(flags=0x08), "tiled")
    refused(preamble(flags=0x10), "tiled")


def header_with(var attributes: List[UInt8]) -> List[UInt8]:
    """Return a preamble, the given attributes and the header's end."""
    var out = preamble()
    out.extend(attributes^)
    out.append(0)
    return out^


def test_a_header_is_checked() raises:
    var good = List[UInt8]()
    attribute(good, "channels", "chlist", rgb())
    attribute(good, "compression", "compression", [0])
    attribute(good, "dataWindow", "box2i", box(0, 0, 0, 0))
    # A name, a type or a size that runs off the end of the file.
    refused(plus(preamble(), [99]), "runs past its end")
    refused(plus(preamble(), [99, 0, 99]), "runs past its end")
    refused(plus(preamble(), [99, 0, 99, 0, 1]), "cut short")
    refused(plus(preamble(), [99, 0, 99, 0, 9, 0, 0, 0, 1]), "cut short")
    # A needed attribute of the wrong type or size.
    var chans = List[UInt8]()
    attribute(chans, "channels", "string", rgb())
    refused(header_with(chans^), "must be a chlist")
    var kind = List[UInt8]()
    attribute(kind, "compression", "int", [0])
    refused(header_with(kind^), "compression attribute")
    var size = List[UInt8]()
    attribute(size, "compression", "compression", [0, 0])
    refused(header_with(size^), "compression attribute")
    var window = List[UInt8]()
    attribute(window, "dataWindow", "box2f", box(0, 0, 0, 0))
    refused(header_with(window^), "dataWindow attribute")
    var short = List[UInt8]()
    attribute(short, "dataWindow", "box2i", [0, 0, 0, 0])
    refused(header_with(short^), "dataWindow attribute")
    # Each needed attribute missing.
    var no_channels = List[UInt8]()
    attribute(no_channels, "compression", "compression", [0])
    attribute(no_channels, "dataWindow", "box2i", box(0, 0, 0, 0))
    refused(header_with(no_channels^), "no channels")
    var no_compression = List[UInt8]()
    attribute(no_compression, "channels", "chlist", rgb())
    attribute(no_compression, "dataWindow", "box2i", box(0, 0, 0, 0))
    refused(header_with(no_compression^), "no compression")
    var no_window = List[UInt8]()
    attribute(no_window, "channels", "chlist", rgb())
    attribute(no_window, "compression", "compression", [0])
    refused(header_with(no_window^), "no data window")
    # The good header, then the table missing.
    refused(header_with(good.copy()), "cut short")


def test_a_header_refuses_what_it_cannot_read() raises:
    refused(exr(rgb(), 5, box(0, 0, 0, 0), [0], [[0]]), "PXR24")
    refused(exr(rgb(), 0, box(1, 0, 0, 0), [0], [[0]]), "at least one pixel")
    refused(exr(rgb(), 0, box(0, 1, 0, 0), [0], [[0]]), "at least one pixel")
    refused(exr(rgb(), 0, box(0, 0, 65535, 65535), [0], [[0]]), "more pixels")


def test_a_channel_list_is_checked() raises:
    # An entry cut short of its sixteen bytes, and a pixel type past FLOAT.
    var cut: List[UInt8] = [82, 0, 1, 0, 0, 0, 0]
    refused(exr(cut, 0, box(0, 0, 0, 0), [0], [[0]]), "cut short")
    refused(
        exr(chlist([channel("R", 3)]), 0, box(0, 0, 0, 0), [0], [[0]]),
        "UINT, HALF or FLOAT",
    )
    # Subsampled across, and down.
    refused(
        exr(chlist([channel("R", 1, 2, 1)]), 0, box(0, 0, 0, 0), [0], [[0]]),
        "subsampled",
    )
    refused(
        exr(chlist([channel("R", 1, 1, 2)]), 0, box(0, 0, 0, 0), [0], [[0]]),
        "subsampled",
    )
    # No channels at all, and no full set of R, G and B.
    refused(
        exr(chlist(List[List[UInt8]]()), 0, box(0, 0, 0, 0), [0], [[0]]),
        "R, G and B",
    )
    var sets: List[List[String]] = [["G", "B"], ["R", "B"], ["R", "G"]]
    for names in sets:
        var entries = List[List[UInt8]]()
        for name in names:
            entries.append(channel(name, 1))
        refused(
            exr(chlist(entries^), 0, box(0, 0, 0, 0), [0], [[0]]),
            "R, G and B",
        )
    # Luminance and chroma.
    refused(
        exr(
            chlist([channel("RY", 1), channel("Y", 1)]),
            0,
            box(0, 0, 0, 0),
            [0],
            [[0]],
        ),
        "luminance-chroma",
    )
    refused(
        exr(
            chlist([channel("BY", 1), channel("Y", 1)]),
            0,
            box(0, 0, 0, 0),
            [0],
            [[0]],
        ),
        "luminance-chroma",
    )
    # Unsigned integers as a color.
    refused(exr(rgb(0), 0, box(0, 0, 0, 0), [0], [[0]]), "HALF or FLOAT")


def test_blocks_are_checked() raises:
    # Cut in a block's header, and in its data.
    var whole = half_rgb_file(0, [row_zero(), row_one()], [0, 1])
    refused(List[UInt8](whole[: len(whole) - 18 - 4]), "cut short")
    refused(List[UInt8](whole[: len(whole) - 1]), "cut short")
    # A line before the window, and one past it.
    refused(half_rgb_file(0, [row_zero(), row_one()], [0, -1]), "outside")
    refused(half_rgb_file(0, [row_zero(), row_one()], [0, 2]), "outside")
    # An uncompressed block short of its line.
    refused(
        half_rgb_file(0, [row_zero(), [0, 0]], [0, 1]), "uncompressed block"
    )


def test_rle_blocks_are_checked() raises:
    # A literal run past the block, and past the line.
    refused(half_rgb_file(1, [[250, 1], row_one()], [0, 1]), "cut short")
    # Seventeen zeros, then a literal of two: one byte past the line.
    refused(
        half_rgb_file(1, [[16, 0, 254, 1, 2], row_one()], [0, 1]),
        "expands past",
    )
    # A repeat with no byte to repeat, and one past the line.
    refused(half_rgb_file(1, [[4], row_one()], [0, 1]), "cut short")
    refused(half_rgb_file(1, [[40, 0], row_one()], [0, 1]), "expands past")
    # A block that expands to less than its line.
    refused(half_rgb_file(1, [[3, 0], row_one()], [0, 1]), "does not expand")
    refused(half_rgb_file(1, [[], row_one()], [0, 1]), "does not expand")


def test_zip_blocks_are_checked() raises:
    # A stream of nothing, and bytes that are not a stream.
    refused(
        half_rgb_file(2, [zlib_stream([]), row_one()], [0, 1]),
        "does not expand",
    )
    refused(half_rgb_file(2, [[1, 2, 3], row_one()], [0, 1]), "zlib")


def piz_file(var block: List[UInt8]) -> List[UInt8]:
    """Return a 3x2 half RGB PIZ file of one block."""
    return exr(rgb(), 4, box(0, 0, 2, 1), [0], [block^])


def test_piz_blocks_are_checked() raises:
    refused(piz_file([0, 0]), "cut short")
    refused(piz_file([0, 0, 0, 32]), "larger than sixteen bits")
    # A bitmap of three bytes with one there.
    refused(piz_file([0, 0, 2, 0, 1]), "cut short")
    # No room for the Huffman data's length, then less data than it says.
    refused(piz_file([255, 31, 0, 0, 1, 0]), "cut short")
    refused(piz_file([255, 31, 0, 0, 9, 0, 0, 0, 1]), "cut short")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
