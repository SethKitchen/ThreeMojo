# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.compressed_texture`: hand-built BC1 and BC3 blocks
decoded against worked-out texels."""

from render.compressed_texture import (
    RGB_S3TC_DXT1_FORMAT,
    RGBA_S3TC_DXT1_FORMAT,
    RGBA_S3TC_DXT5_FORMAT,
    CompressedFormat,
    compressed_texture,
    decode_s3tc,
    unpack565,
    widen5,
    widen6,
)
from render.srgb import LINEAR
from render.texture import CLAMP, IGNORED, NEAREST, REPEAT
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

# Pure red and pure blue in RGB565.
comptime RED565 = 0xF800
comptime BLUE565 = 0x001F


def color_block(first: Int, second: Int, indices: List[Int]) -> List[UInt8]:
    """Return one BC1 block: two 565 colors and sixteen two-bit indices,
    row-major."""
    var out: List[UInt8] = [
        UInt8(first & 0xFF),
        UInt8(first >> 8),
        UInt8(second & 0xFF),
        UInt8(second >> 8),
    ]
    for row in range(4):
        var bits = 0
        for column in range(4):
            bits |= indices[row * 4 + column] << (column * 2)
        out.append(UInt8(bits))
    return out^


def alpha_block(a0: Int, a1: Int, indices: List[Int]) -> List[UInt8]:
    """Return one BC3 alpha block: two alphas and sixteen three-bit
    indices, row-major."""
    var out: List[UInt8] = [UInt8(a0), UInt8(a1)]
    var bits = 0
    for texel in range(16):
        bits |= indices[texel] << (texel * 3)
    for byte in range(6):
        out.append(UInt8((bits >> (byte * 8)) & 0xFF))
    return out^


def same(value: Int) -> List[Int]:
    """Return sixteen of one index."""
    return List[Int](length=16, fill=value)


def repeated(pattern: List[Int], times: Int) -> List[Int]:
    """Return `pattern` laid end to end `times` over."""
    var out = List[Int]()
    for _ in range(times):
        for index in range(len(pattern)):
            out.append(pattern[index])
    return out^


def test_565_channels_widen_by_copying_their_top_bits() raises:
    assert_equal(widen5(0), UInt8(0))
    assert_equal(widen5(31), UInt8(255))
    assert_equal(widen5(16), UInt8(132))
    assert_equal(widen6(0), UInt8(0))
    assert_equal(widen6(63), UInt8(255))
    assert_equal(widen6(32), UInt8(130))
    var red = unpack565(RED565)
    assert_equal(red[0], UInt8(255))
    assert_equal(red[1], UInt8(0))
    assert_equal(red[2], UInt8(0))
    var blue = unpack565(BLUE565)
    assert_equal(blue[2], UInt8(255))
    assert_equal(blue[0], UInt8(0))


def test_a_four_color_block_blends_two_thirds_and_one_third() raises:
    # Red sorts above blue, so the two extra entries are blends.
    var indices = repeated([0, 1, 2, 3], 4)
    var pixels = decode_s3tc(
        4, 4, color_block(RED565, BLUE565, indices), RGB_S3TC_DXT1_FORMAT
    )
    # Column 0 red, 1 blue, 2 two-thirds red, 3 one-third red.
    assert_equal(pixels[0], UInt8(255))
    assert_equal(pixels[2], UInt8(0))
    assert_equal(pixels[4 + 2], UInt8(255))
    assert_equal(pixels[8], UInt8(170))
    assert_equal(pixels[8 + 2], UInt8(85))
    assert_equal(pixels[12], UInt8(85))
    assert_equal(pixels[12 + 2], UInt8(170))
    # Every alpha is opaque, and the fourth row matches the first.
    for texel in range(16):
        assert_equal(pixels[texel * 4 + 3], UInt8(255))
    assert_equal(pixels[12 * 4], UInt8(255))


def test_a_three_color_block_has_one_blend_and_a_transparent_index() raises:
    # Blue sorts below red: first < second, so three colors and a hole.
    var indices = repeated([0, 1, 2, 3], 4)
    var rgba = decode_s3tc(
        4, 4, color_block(BLUE565, RED565, indices), RGBA_S3TC_DXT1_FORMAT
    )
    assert_equal(rgba[2], UInt8(255))
    assert_equal(rgba[4], UInt8(255))
    # The blend is the midpoint, rounded.
    assert_equal(rgba[8], UInt8(128))
    assert_equal(rgba[8 + 2], UInt8(128))
    # Index three is transparent black under the RGBA format...
    assert_equal(rgba[12], UInt8(0))
    assert_equal(rgba[12 + 3], UInt8(0))
    assert_equal(rgba[3], UInt8(255))
    # ...and opaque black under the RGB one.
    var rgb = decode_s3tc(
        4, 4, color_block(BLUE565, RED565, indices), RGB_S3TC_DXT1_FORMAT
    )
    assert_equal(rgb[12], UInt8(0))
    assert_equal(rgb[12 + 3], UInt8(255))


def test_a_dxt5_block_carries_its_own_alphas() raises:
    # Eight alphas from 240 down to 30, one per texel index, over a color
    # block whose two colors sort the three-color way: BC3 reads it as
    # four colors anyway, so index three is a blend and not a hole.
    var alpha_indices = repeated([0, 1, 2, 3, 4, 5, 6, 7], 2)
    var color_indices = same(3)
    var data = alpha_block(240, 30, alpha_indices)
    data.extend(color_block(BLUE565, RED565, color_indices))
    var pixels = decode_s3tc(4, 4, data, RGBA_S3TC_DXT5_FORMAT)
    var alphas: List[Int] = [240, 30, 210, 180, 150, 120, 90, 60]
    for texel in range(16):
        assert_equal(pixels[texel * 4 + 3], UInt8(alphas[texel % 8]))
        # One-third blue and two-thirds red, opaque in the color block.
        assert_equal(pixels[texel * 4], UInt8(170))
        assert_equal(pixels[texel * 4 + 2], UInt8(85))


def test_a_dxt5_alpha_block_sorted_the_other_way_has_two_ends() raises:
    # a0 below a1: four blends, then zero and full.
    var alpha_indices = repeated([0, 1, 2, 3, 4, 5, 6, 7], 2)
    var data = alpha_block(50, 200, alpha_indices)
    data.extend(color_block(RED565, RED565, same(0)))
    var pixels = decode_s3tc(4, 4, data, RGBA_S3TC_DXT5_FORMAT)
    var alphas: List[Int] = [50, 200, 80, 110, 140, 170, 0, 255]
    for texel in range(16):
        assert_equal(pixels[texel * 4 + 3], UInt8(alphas[texel % 8]))


def test_an_image_need_not_be_whole_blocks() raises:
    # A 5x3 image spans two blocks across and one down; the texels past
    # the edge are decoded and dropped.
    var data = color_block(RED565, RED565, same(0))
    data.extend(color_block(BLUE565, BLUE565, same(0)))
    var pixels = decode_s3tc(5, 3, data, RGB_S3TC_DXT1_FORMAT)
    assert_equal(len(pixels), 5 * 3 * 4)
    # Row 1: four red, then one blue from the second block.
    assert_equal(pixels[(5 + 3) * 4], UInt8(255))
    assert_equal(pixels[(5 + 4) * 4 + 2], UInt8(255))
    assert_equal(pixels[(5 + 4) * 4], UInt8(0))


def test_a_payload_must_match_the_block_grid_and_the_format() raises:
    var data = color_block(RED565, RED565, same(0))
    with assert_raises():
        _ = decode_s3tc(8, 4, data, RGB_S3TC_DXT1_FORMAT)
    with assert_raises():
        _ = decode_s3tc(4, 4, data, RGBA_S3TC_DXT5_FORMAT)
    with assert_raises():
        _ = decode_s3tc(0, 4, data, RGB_S3TC_DXT1_FORMAT)
    with assert_raises():
        _ = decode_s3tc(4, -1, data, RGB_S3TC_DXT1_FORMAT)
    with assert_raises():
        _ = decode_s3tc(4, 4, data, CompressedFormat(9))
    assert_false(CompressedFormat(9).is_valid())
    assert_equal(CompressedFormat(9).block_bytes(), 8)
    for format in [
        RGB_S3TC_DXT1_FORMAT,
        RGBA_S3TC_DXT1_FORMAT,
        RGBA_S3TC_DXT5_FORMAT,
    ]:
        assert_true(format.is_valid())
    assert_equal(RGBA_S3TC_DXT5_FORMAT.block_bytes(), 16)


def test_a_compressed_texture_takes_threejs_defaults() raises:
    var data = color_block(RED565, BLUE565, same(1))
    var image = compressed_texture(4, 4, data, RGB_S3TC_DXT1_FORMAT)
    assert_equal(image.width, 4)
    assert_equal(image.wrap, CLAMP)
    assert_equal(image.levels, 1)
    assert_equal(image.texel(3, 3).b, UInt8(255))
    var custom = compressed_texture(
        4, 4, data, RGB_S3TC_DXT1_FORMAT, REPEAT, NEAREST, LINEAR, True, IGNORED
    )
    assert_equal(custom.wrap, REPEAT)
    assert_equal(custom.filter, NEAREST)
    assert_equal(custom.color_space, LINEAR)
    assert_equal(custom.levels, 3)
    assert_equal(custom.alpha, IGNORED)
    with assert_raises():
        _ = compressed_texture(4, 4, data, CompressedFormat(4))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
