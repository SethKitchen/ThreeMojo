# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.dds`: hand-built DDS files read into their levels,
and every file this reader refuses."""

from render.compressed_texture import (
    RED_GREEN_RGTC2_FORMAT,
    RED_RGTC1_FORMAT,
    RGB_BPTC_SIGNED_FORMAT,
    RGB_BPTC_UNSIGNED_FORMAT,
    RGB_ETC1_FORMAT,
    RGB_S3TC_DXT1_FORMAT,
    RGBA_BPTC_FORMAT,
    RGBA_S3TC_DXT1_FORMAT,
    RGBA_S3TC_DXT3_FORMAT,
    RGBA_S3TC_DXT5_FORMAT,
    SIGNED_RED_GREEN_RGTC2_FORMAT,
    SIGNED_RED_RGTC1_FORMAT,
    CompressedFormat,
    RGBA_FORMAT,
)
from loaders.json import parse_json
from render.dds import four_cc, format_of_dxgi, format_of_four_cc, read
from std.pathlib import Path
from render.srgb import LINEAR, SRGB
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def red_block() -> List[UInt8]:
    """Return one red BC1 block: two red 565 colors, every index zero."""
    return [0x00, 0xF8, 0x00, 0xF8, 0, 0, 0, 0]


def put(mut bytes: List[UInt8], at: Int, value: Int):
    """Write a little-endian word."""
    for byte in range(4):
        bytes[at + byte] = UInt8((value >> (byte * 8)) & 0xFF)


def dds(
    width: Int,
    height: Int,
    code: String,
    levels: Int = 0,
    caps2: Int = 0,
    dx10: List[Int] = [],
) -> List[UInt8]:
    """Return a DDS header, without data.

    Args:
        width: The width.
        height: The height.
        code: The four-character code.
        levels: The level count, with its flag set if positive.
        caps2: The second capability word.
        dx10: The DX10 header's DXGI format, dimension, flag and array
            size, if the code is `DX10`.
    """
    var bytes = List[UInt8](length=128, fill=0)
    put(bytes, 0, four_cc("DDS "))
    put(bytes, 4, 124)
    var flags = 0x1007
    if levels > 0:
        flags |= 0x20000
    put(bytes, 8, flags)
    put(bytes, 12, height)
    put(bytes, 16, width)
    put(bytes, 28, levels)
    put(bytes, 76, 32)
    put(bytes, 80, 0x4)
    put(bytes, 84, four_cc(code))
    put(bytes, 112, caps2)
    if len(dx10) > 0:
        var extra = List[UInt8](length=20, fill=0)
        put(extra, 0, dx10[0])
        put(extra, 4, dx10[1])
        put(extra, 8, dx10[2])
        put(extra, 12, dx10[3])
        bytes.extend(extra^)
    return bytes^


def blocks(count: Int, size: Int = 8) -> List[UInt8]:
    """Return `count` blocks, each filled with its own number."""
    var out = List[UInt8]()
    for block in range(count):
        for _ in range(size):
            out.append(UInt8(block))
    return out^


def test_a_dxt1_file_reads_into_one_level() raises:
    var file = dds(4, 4, "DXT1")
    file.extend(red_block())
    var image = read(file)
    assert_equal(image.width, 4)
    assert_equal(image.height, 4)
    assert_equal(image.format, RGB_S3TC_DXT1_FORMAT)
    assert_equal(image.color_space, LINEAR)
    assert_equal(image.faces, 1)
    assert_equal(image.levels, 1)
    assert_equal(len(image.mipmaps), 1)
    var texture = image.texture()
    assert_equal(texture.texel(0, 0).r, UInt8(255))
    assert_equal(texture.color_space, LINEAR)


def test_a_mip_chain_is_read_largest_first() raises:
    # 8x8 is four blocks, then one for 4x4, 2x2 and 1x1.
    var file = dds(8, 8, "DXT1", levels=4)
    file.extend(blocks(7))
    var image = read(file)
    assert_equal(image.levels, 4)
    assert_equal(len(image.mipmaps[0]), 32)
    for level in range(1, 4):
        assert_equal(len(image.mipmaps[level]), 8)
        assert_equal(Int(image.mipmaps[level][0]), 3 + level)
    # A level count of zero with its flag set is one level; a count
    # without its flag is ignored.
    var zero = dds(4, 4, "DXT1", levels=0)
    put(zero, 8, 0x21007)
    zero.extend(red_block())
    assert_equal(read(zero).levels, 1)
    var unflagged = dds(4, 4, "DXT1")
    put(unflagged, 28, 3)
    unflagged.extend(red_block())
    assert_equal(read(unflagged).levels, 1)


def test_a_cube_holds_six_faces_face_major() raises:
    var file = dds(4, 4, "DXT1", levels=2, caps2=0x200 | 0xFC00)
    file.extend(blocks(12))
    var image = read(file)
    assert_equal(image.faces, 6)
    assert_equal(len(image.mipmaps), 12)
    # Face 2's second level is the file's sixth block.
    assert_equal(Int(image.mipmaps[2 * 2 + 1][0]), 5)
    with assert_raises(contains="all six faces"):
        _ = read(dds(4, 4, "DXT1", caps2=0x200 | 0x0C00))


def test_every_four_character_code_names_its_format() raises:
    var codes: List[String] = [
        "DXT1", "DXT3", "DXT5", "ATI1", "BC4U", "BC4S", "ATI2", "BC5U",
        "BC5S", "ETC1",
    ]  # fmt: skip
    var formats: List[CompressedFormat] = [
        RGB_S3TC_DXT1_FORMAT,
        RGBA_S3TC_DXT3_FORMAT,
        RGBA_S3TC_DXT5_FORMAT,
        RED_RGTC1_FORMAT,
        RED_RGTC1_FORMAT,
        SIGNED_RED_RGTC1_FORMAT,
        RED_GREEN_RGTC2_FORMAT,
        RED_GREEN_RGTC2_FORMAT,
        SIGNED_RED_GREEN_RGTC2_FORMAT,
        RGB_ETC1_FORMAT,
    ]
    for index in range(len(codes)):
        assert_equal(format_of_four_cc(four_cc(codes[index])), formats[index])
    with assert_raises(contains="not ported"):
        _ = format_of_four_cc(four_cc("DXT2"))


def test_every_dxgi_number_names_its_format_and_space() raises:
    var numbers: List[Int] = [
        71,
        72,
        74,
        75,
        77,
        78,
        80,
        81,
        83,
        84,
        95,
        96,
        98,
        99,
    ]
    var formats: List[CompressedFormat] = [
        RGBA_S3TC_DXT1_FORMAT,
        RGBA_S3TC_DXT1_FORMAT,
        RGBA_S3TC_DXT3_FORMAT,
        RGBA_S3TC_DXT3_FORMAT,
        RGBA_S3TC_DXT5_FORMAT,
        RGBA_S3TC_DXT5_FORMAT,
        RED_RGTC1_FORMAT,
        SIGNED_RED_RGTC1_FORMAT,
        RED_GREEN_RGTC2_FORMAT,
        SIGNED_RED_GREEN_RGTC2_FORMAT,
        RGB_BPTC_UNSIGNED_FORMAT,
        RGB_BPTC_SIGNED_FORMAT,
        RGBA_BPTC_FORMAT,
        RGBA_BPTC_FORMAT,
    ]
    var srgb: List[Int] = [72, 75, 78, 99]
    for index in range(len(numbers)):
        var named = format_of_dxgi(numbers[index])
        assert_equal(named[0], formats[index])
        if numbers[index] in srgb:
            assert_equal(named[1], SRGB)
        else:
            assert_equal(named[1], LINEAR)
    with assert_raises(contains="BC1 to BC7"):
        _ = format_of_dxgi(28)


def test_a_dx10_file_names_its_format_by_dxgi() raises:
    var file = dds(4, 4, "DX10", dx10=[99, 3, 0, 1])
    file.extend(blocks(1, 16))
    var image = read(file)
    assert_equal(image.format, RGBA_BPTC_FORMAT)
    assert_equal(image.color_space, SRGB)
    assert_equal(len(image.mipmaps[0]), 16)
    # A DX10 cube is marked in the extra header.
    var cube = dds(4, 4, "DX10", dx10=[71, 3, 0x4, 1])
    cube.extend(blocks(6))
    assert_equal(read(cube).faces, 6)
    with assert_raises(contains="only 2D"):
        _ = read(dds(4, 4, "DX10", dx10=[71, 4, 0, 1]))
    with assert_raises(contains="arrays"):
        _ = read(dds(4, 4, "DX10", dx10=[71, 3, 0, 2]))
    with assert_raises(contains="DX10 header"):
        _ = read(dds(4, 4, "DX10"))


def test_a_malformed_file_is_refused() raises:
    with assert_raises(contains="shorter than its header"):
        _ = read(List[UInt8](length=100, fill=0))
    var magic = dds(4, 4, "DXT1")
    magic[0] = 0
    with assert_raises(contains="magic"):
        _ = read(magic)
    var header = dds(4, 4, "DXT1")
    put(header, 4, 120)
    with assert_raises(contains="wrong size"):
        _ = read(header)
    var pixel_format = dds(4, 4, "DXT1")
    put(pixel_format, 76, 24)
    with assert_raises(contains="wrong size"):
        _ = read(pixel_format)
    with assert_raises(contains="positive"):
        _ = read(dds(0, 4, "DXT1"))
    with assert_raises(contains="positive"):
        _ = read(dds(4, 0, "DXT1"))
    # The flags are not read: a known code is a block format even when the
    # flags say RGB, as in three.js.
    var masks = dds(4, 4, "DXT1")
    put(masks, 80, 0x41)
    masks.extend(red_block())
    assert_true(read(masks).format == RGB_S3TC_DXT1_FORMAT)
    with assert_raises(contains="more levels"):
        _ = read(dds(4, 4, "DXT1", levels=4))
    with assert_raises(contains="ends before"):
        _ = read(dds(4, 4, "DXT1"))
    with assert_raises(contains="MAX_DECODED_BYTES"):
        _ = read(dds(100000, 100000, "DXT1"))
    with assert_raises(contains="not ported"):
        _ = read(dds(4, 4, "DXT2"))
    # Thirty-two bits with no alpha mask, and twenty-four with no blue
    # mask, are neither of three.js's uncompressed layouts.
    var no_alpha = dds(1, 1, "NONE")
    put(no_alpha, 88, 32)
    put(no_alpha, 92, 0xFF0000)
    put(no_alpha, 96, 0xFF00)
    put(no_alpha, 100, 0xFF)
    with assert_raises(contains="not ported"):
        _ = read(no_alpha)
    var no_color = dds(1, 1, "NONE")
    put(no_color, 88, 32)
    put(no_color, 104, 0xFF000000)
    with assert_raises(contains="not ported"):
        _ = read(no_color)
    var no_blue = dds(1, 1, "NONE")
    put(no_blue, 88, 24)
    put(no_blue, 92, 0xFF0000)
    put(no_blue, 96, 0xFF00)
    with assert_raises(contains="not ported"):
        _ = read(no_blue)
    var short = dds(2, 2, "NONE")
    put(short, 88, 24)
    put(short, 92, 0xFF0000)
    put(short, 96, 0xFF00)
    put(short, 100, 0xFF)
    short.extend(List[UInt8](length=11, fill=0))
    with assert_raises(contains="ends before"):
        _ = read(short)


def test_uncompressed_files_are_read_as_three_js_reads_them() raises:
    var doc = parse_json(Path("assets/dds/dds.json").read_text())
    for name in ["bgra.dds", "bgr.dds"]:
        var image = read(Path("assets/dds/" + name).read_bytes())
        var want = doc.get(doc.root(), name)
        assert_true(image.format == RGBA_FORMAT)
        assert_equal(image.width, doc.integer(doc.get(want, "width")))
        assert_equal(image.levels, doc.integer(doc.get(want, "mipmapCount")))
        var mipmaps = doc.get(want, "mipmaps")
        assert_equal(len(image.mipmaps), doc.length(mipmaps))
        for level in range(len(image.mipmaps)):
            var data = doc.get(doc.at(mipmaps, level), "data")
            ref got = image.mipmaps[level]
            assert_equal(len(got), doc.length(data), name)
            for k in range(len(got)):
                assert_equal(Int(got[k]), doc.integer(doc.at(data, k)), name)
    # An RGBA level decodes to its own bytes.
    var bgra = read(Path("assets/dds/bgra.dds").read_bytes())
    var texture = bgra.texture(level=1)
    assert_equal(texture.width, 2)
    assert_equal(texture.pixels[0], bgra.mipmaps[1][0])
    assert_equal(texture.pixels[7], bgra.mipmaps[1][7])
    assert_equal(String(RGBA_FORMAT), "RGBAFormat")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
