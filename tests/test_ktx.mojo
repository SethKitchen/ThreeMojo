# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.ktx`: hand-built KTX 1 files, in both byte orders,
read into their levels, and every file this reader refuses."""

from render.compressed_texture import (
    R11_EAC_FORMAT,
    RED_GREEN_RGTC2_FORMAT,
    RED_RGTC1_FORMAT,
    RG11_EAC_FORMAT,
    RGB_BPTC_SIGNED_FORMAT,
    RGB_BPTC_UNSIGNED_FORMAT,
    RGB_ETC1_FORMAT,
    RGB_ETC2_FORMAT,
    RGB_S3TC_DXT1_FORMAT,
    RGBA_BPTC_FORMAT,
    RGBA_ETC2_EAC_FORMAT,
    RGBA_S3TC_DXT1_FORMAT,
    RGBA_S3TC_DXT3_FORMAT,
    RGBA_S3TC_DXT5_FORMAT,
    SIGNED_R11_EAC_FORMAT,
    SIGNED_RED_GREEN_RGTC2_FORMAT,
    SIGNED_RED_RGTC1_FORMAT,
    SIGNED_RG11_EAC_FORMAT,
    CompressedFormat,
)
from render.ktx import format_of_gl, identifier, read
from render.srgb import LINEAR, SRGB
from std.testing import TestSuite, assert_equal, assert_raises


def word(value: Int, big_endian: Bool) -> List[UInt8]:
    """Return a word in the given byte order."""
    var out = List[UInt8]()
    for byte in range(4):
        var shift = byte * 8
        if big_endian:
            shift = (3 - byte) * 8
        out.append(UInt8((value >> shift) & 0xFF))
    return out^


def ktx(
    internal: Int,
    width: Int,
    height: Int,
    faces: Int = 1,
    levels: Int = 1,
    big_endian: Bool = False,
    gl_type: Int = 0,
    depth: Int = 0,
    elements: Int = 0,
    key_values: Int = 0,
) -> List[UInt8]:
    """Return a KTX 1 header, the key and value data as zeros, and no
    levels."""
    var out = identifier()
    var fields: List[Int] = [
        0x04030201, gl_type, 1, 0, internal, 0, width, height, depth,
        elements, faces, levels, key_values,
    ]  # fmt: skip
    for index in range(len(fields)):
        out.extend(word(fields[index], big_endian))
    for _ in range(key_values):
        out.append(0)
    return out^


def level(
    mut file: List[UInt8], size: Int, faces: Int, first: Int, big_endian: Bool
):
    """Append a level: its size, then each face's bytes, face `f` filled
    with `first + f`."""
    file.extend(word(size, big_endian))
    for face in range(faces):
        for _ in range(size):
            file.append(UInt8(first + face))


def test_a_little_endian_file_reads_into_its_levels() raises:
    # An 8x4 DXT1 image: two blocks, then one for 4x2, 2x1 and 1x1.
    var file = ktx(0x83F0, 8, 4, levels=4, key_values=8)
    level(file, 16, 1, 1, False)
    for index in range(3):
        level(file, 8, 1, 2 + index, False)
    var image = read(file)
    assert_equal(image.width, 8)
    assert_equal(image.height, 4)
    assert_equal(image.format, RGB_S3TC_DXT1_FORMAT)
    assert_equal(image.color_space, LINEAR)
    assert_equal(image.levels, 4)
    assert_equal(len(image.mipmaps[0]), 16)
    assert_equal(Int(image.mipmaps[3][0]), 4)
    assert_equal(image.texture(level=1).width, 4)


def test_a_big_endian_cube_is_stored_face_major() raises:
    # The file stores each level's six faces together; the image keeps
    # each face's levels together.
    var file = ktx(0x9278, 4, 4, faces=6, levels=2, big_endian=True)
    level(file, 16, 6, 10, True)
    level(file, 16, 6, 20, True)
    var image = read(file)
    assert_equal(image.format, RGBA_ETC2_EAC_FORMAT)
    assert_equal(image.faces, 6)
    assert_equal(Int(image.mipmaps[3 * 2][0]), 13)
    assert_equal(Int(image.mipmaps[3 * 2 + 1][0]), 23)
    # A level count of zero is one level.
    var one = ktx(0x83F1, 4, 4, levels=0)
    level(one, 8, 1, 0, False)
    assert_equal(read(one).levels, 1)


def test_every_internal_format_names_its_format_and_space() raises:
    var numbers: List[Int] = [
        0x83F0, 0x83F1, 0x83F2, 0x83F3, 0x8C4C, 0x8C4D, 0x8C4E, 0x8C4F,
        0x8DBB, 0x8DBC, 0x8DBD, 0x8DBE, 0x8E8C, 0x8E8D, 0x8E8E, 0x8E8F,
        0x8D64, 0x9274, 0x9275, 0x9278, 0x9279, 0x9270, 0x9271, 0x9272,
        0x9273,
    ]  # fmt: skip
    var formats: List[CompressedFormat] = [
        RGB_S3TC_DXT1_FORMAT,
        RGBA_S3TC_DXT1_FORMAT,
        RGBA_S3TC_DXT3_FORMAT,
        RGBA_S3TC_DXT5_FORMAT,
        RGB_S3TC_DXT1_FORMAT,
        RGBA_S3TC_DXT1_FORMAT,
        RGBA_S3TC_DXT3_FORMAT,
        RGBA_S3TC_DXT5_FORMAT,
        RED_RGTC1_FORMAT,
        SIGNED_RED_RGTC1_FORMAT,
        RED_GREEN_RGTC2_FORMAT,
        SIGNED_RED_GREEN_RGTC2_FORMAT,
        RGBA_BPTC_FORMAT,
        RGBA_BPTC_FORMAT,
        RGB_BPTC_SIGNED_FORMAT,
        RGB_BPTC_UNSIGNED_FORMAT,
        RGB_ETC1_FORMAT,
        RGB_ETC2_FORMAT,
        RGB_ETC2_FORMAT,
        RGBA_ETC2_EAC_FORMAT,
        RGBA_ETC2_EAC_FORMAT,
        R11_EAC_FORMAT,
        SIGNED_R11_EAC_FORMAT,
        RG11_EAC_FORMAT,
        SIGNED_RG11_EAC_FORMAT,
    ]
    var srgb: List[Int] = [
        0x8C4C,
        0x8C4D,
        0x8C4E,
        0x8C4F,
        0x8E8D,
        0x9275,
        0x9279,
    ]
    for index in range(len(numbers)):
        var named = format_of_gl(numbers[index])
        assert_equal(named[0], formats[index])
        if numbers[index] in srgb:
            assert_equal(named[1], SRGB)
        else:
            assert_equal(named[1], LINEAR)
    # ASTC 4x4 and PVRTC are not ported.
    for number in [0x93B0, 0x8C00]:
        with assert_raises(contains="not ported"):
            _ = format_of_gl(number)


def test_a_malformed_file_is_refused() raises:
    with assert_raises(contains="shorter than its header"):
        _ = read(List[UInt8](length=60, fill=0))
    var magic = ktx(0x83F0, 4, 4)
    magic[5] = 0x32
    with assert_raises(contains="identifier"):
        _ = read(magic)
    var order = ktx(0x83F0, 4, 4)
    order[12] = 9
    with assert_raises(contains="endianness"):
        _ = read(order)
    with assert_raises(contains="OpenGL type"):
        _ = read(ktx(0x83F0, 4, 4, gl_type=0x1401))
    with assert_raises(contains="positive"):
        _ = read(ktx(0x83F0, 0, 4))
    with assert_raises(contains="positive"):
        _ = read(ktx(0x83F0, 4, 0))
    with assert_raises(contains="depth"):
        _ = read(ktx(0x83F0, 4, 4, depth=1))
    with assert_raises(contains="arrays"):
        _ = read(ktx(0x83F0, 4, 4, elements=2))
    with assert_raises(contains="one face or six"):
        _ = read(ktx(0x83F0, 4, 4, faces=2))
    with assert_raises(contains="more levels"):
        _ = read(ktx(0x83F0, 4, 4, levels=4))
    with assert_raises(contains="MAX_DECODED_BYTES"):
        _ = read(ktx(0x83F0, 100000, 100000))
    with assert_raises(contains="ends before"):
        _ = read(ktx(0x83F0, 4, 4))
    var wrong = ktx(0x83F0, 4, 4)
    level(wrong, 16, 1, 0, False)
    with assert_raises(contains="block grid"):
        _ = read(wrong)
    var short = ktx(0x83F0, 4, 4)
    short.extend(word(8, False))
    short.append(0)
    with assert_raises(contains="ends before"):
        _ = read(short)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
