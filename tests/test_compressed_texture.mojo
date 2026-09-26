# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.compressed_texture`: hand-built BC1 and BC3 blocks
decoded against worked-out texels."""

from render.compressed_texture import (
    MAX_DECODED_BYTES,
    RED_GREEN_RGTC2_FORMAT,
    RED_RGTC1_FORMAT,
    RGB_S3TC_DXT1_FORMAT,
    RGBA_BPTC_FORMAT,
    RGBA_S3TC_DXT1_FORMAT,
    RGBA_S3TC_DXT3_FORMAT,
    RGBA_S3TC_DXT5_FORMAT,
    SIGNED_RED_GREEN_RGTC2_FORMAT,
    SIGNED_RED_RGTC1_FORMAT,
    SIGNED_RG11_EAC_FORMAT,
    CompressedFormat,
    CompressedImage,
    chain_length,
    check_decoded_size,
    compressed_texture,
    decode_compressed,
    decode_s3tc,
    level_bytes,
    signed_rgtc_block,
    unpack565,
    widen5,
    widen6,
)
from render.srgb import LINEAR, SRGB
from render.texture import (
    CLAMP,
    FLOAT_TYPE,
    IGNORED,
    NEAREST,
    REPEAT,
    UNSIGNED_BYTE_TYPE,
)
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
        _ = decode_s3tc(4, 4, data, CompressedFormat(99))
    with assert_raises(contains="use decode_compressed"):
        _ = decode_s3tc(4, 4, data, RED_RGTC1_FORMAT)
    with assert_raises(contains="CompressedFormat(23)"):
        _ = decode_compressed(4, 4, data, CompressedFormat(23))
    with assert_raises():
        _ = decode_compressed(4, 4, data, CompressedFormat(-1))
    assert_false(CompressedFormat(99).is_valid())
    assert_false(CompressedFormat(-1).is_valid())
    assert_equal(CompressedFormat(99).block_bytes(), 16)
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
    assert_equal(image.wrap_s, CLAMP)
    assert_equal(image.levels, 1)
    assert_equal(image.texel(3, 3).b, UInt8(255))
    # A block cannot be flipped on upload: three.js's `flipY` is off.
    assert_false(image.flip_y)
    var custom = compressed_texture(
        4, 4, data, RGB_S3TC_DXT1_FORMAT, REPEAT, NEAREST, LINEAR, True, IGNORED
    )
    assert_equal(custom.wrap_s, REPEAT)
    assert_equal(custom.mag_filter, NEAREST)
    assert_equal(custom.color_space, LINEAR)
    assert_equal(custom.levels, 3)
    assert_equal(custom.alpha, IGNORED)
    with assert_raises():
        _ = compressed_texture(4, 4, data, CompressedFormat(23))


# --- more than one block, and not square ------------------------------------


def channel(
    pixels: List[UInt8], width: Int, x: Int, y: Int, lane: Int
) -> UInt8:
    """Return one channel of one decoded texel, row-major from the top."""
    return pixels[(y * width + x) * 4 + lane]


def test_blocks_land_in_the_right_place_across_several_rows() raises:
    # A 12 by 8 image is three blocks across and two down, and the two
    # dimensions differ, so a decoder that walked the grid the other way
    # round -- or that multiplied by the wrong stride -- gives a different
    # picture rather than the same one transposed.
    #
    # Each of the six blocks is one flat color, so every texel of a block
    # names the block it came from and the whole grid is checkable.
    var flat: List[Int] = [RED565, BLUE565, 0x07E0, 0xFFFF, 0x0000, 0xF81F]
    var data = List[UInt8]()
    for block in range(6):
        var one = color_block(flat[block], flat[block], same(0))
        for byte in range(len(one)):
            data.append(one[byte])
    var pixels = decode_s3tc(12, 8, data, RGBA_S3TC_DXT1_FORMAT)
    assert_equal(len(pixels), 12 * 8 * 4)
    # Block (0, 0) is red, (1, 0) blue, (2, 0) green; the second row is
    # white, black and magenta.
    assert_equal(channel(pixels, 12, 0, 0, 0), UInt8(255))
    assert_equal(channel(pixels, 12, 3, 3, 0), UInt8(255))
    assert_equal(channel(pixels, 12, 4, 0, 2), UInt8(255))
    assert_equal(channel(pixels, 12, 7, 3, 2), UInt8(255))
    assert_equal(channel(pixels, 12, 8, 0, 1), UInt8(255))
    assert_equal(channel(pixels, 12, 11, 3, 1), UInt8(255))
    assert_equal(channel(pixels, 12, 0, 4, 0), UInt8(255))
    assert_equal(channel(pixels, 12, 0, 4, 1), UInt8(255))
    assert_equal(channel(pixels, 12, 0, 4, 2), UInt8(255))
    assert_equal(channel(pixels, 12, 5, 7, 0), UInt8(0))
    assert_equal(channel(pixels, 12, 5, 7, 1), UInt8(0))
    assert_equal(channel(pixels, 12, 5, 7, 2), UInt8(0))
    assert_equal(channel(pixels, 12, 8, 4, 0), UInt8(255))
    assert_equal(channel(pixels, 12, 8, 4, 1), UInt8(0))
    assert_equal(channel(pixels, 12, 8, 4, 2), UInt8(255))
    # Every texel is opaque: the blocks are four-color, so no index is
    # the transparent one.
    for y in range(8):
        for x in range(12):
            assert_equal(channel(pixels, 12, x, y, 3), UInt8(255))


def test_a_tall_image_of_partial_blocks_drops_what_hangs_off() raises:
    # Three across and nine down is one block wide and three tall with one
    # texel of the last block row showing, and the width is not a multiple
    # of four either. A decoder writing whole blocks would run past the
    # buffer or shear the rows.
    var data = List[UInt8]()
    var tones: List[Int] = [RED565, BLUE565, 0x07E0]
    for block in range(3):
        var one = color_block(tones[block], tones[block], same(0))
        for byte in range(len(one)):
            data.append(one[byte])
    var pixels = decode_s3tc(3, 9, data, RGBA_S3TC_DXT1_FORMAT)
    assert_equal(len(pixels), 3 * 9 * 4)
    # The first four rows are red, the next four blue, and the ninth --
    # the one texel row of the last block -- is green.
    assert_equal(pixels[0], UInt8(255))
    assert_equal(pixels[(3 * 3 + 2) * 4], UInt8(255))
    assert_equal(pixels[(4 * 3) * 4 + 2], UInt8(255))
    assert_equal(pixels[(7 * 3 + 2) * 4 + 2], UInt8(255))
    assert_equal(pixels[(8 * 3) * 4 + 1], UInt8(255))
    assert_equal(pixels[(8 * 3 + 2) * 4 + 1], UInt8(255))


def test_dimensions_that_would_decode_to_too_much_are_refused() raises:
    # The width and the height come from a file. Their product decides an
    # allocation, so it is bounded by name rather than left to fail inside
    # an allocator.
    with assert_raises(contains="MAX_DECODED_BYTES"):
        _ = decode_s3tc(100000, 100000, List[UInt8](), RGBA_S3TC_DXT1_FORMAT)
    # The bound is not so tight that a real texture trips it: the payload
    # length is what refuses this one, which means the size passed.
    with assert_raises(contains="payload length"):
        _ = decode_s3tc(16384, 16384, List[UInt8](), RGBA_S3TC_DXT1_FORMAT)


# --- BC2, the RGTC formats, and what every format is -------------------------


def test_a_dxt3_block_carries_sixteen_explicit_alphas() raises:
    # Texel i's alpha is the nibble i, widened to i * 17; the first texel
    # is the low half of the first byte. The color block's two colors sort
    # the three-color way, and BC2 reads four colors anyway.
    var data = List[UInt8]()
    for byte in range(8):
        data.append(UInt8(((byte * 2 + 1) << 4) | (byte * 2)))
    data.extend(color_block(BLUE565, RED565, same(3)))
    var pixels = decode_s3tc(4, 4, data, RGBA_S3TC_DXT3_FORMAT)
    for texel in range(16):
        assert_equal(pixels[texel * 4 + 3], UInt8(texel * 17))
        assert_equal(pixels[texel * 4], UInt8(170))


def test_rgtc_blocks_are_red_and_green_channels() raises:
    # BC4 is BC3's alpha block read as red: green and blue zero, alpha one.
    var red = alpha_block(240, 30, repeated([0, 1, 2, 3, 4, 5, 6, 7], 2))
    var one = decode_compressed(4, 4, red, RED_RGTC1_FORMAT)
    assert_equal(one.texel_type, UNSIGNED_BYTE_TYPE)
    var reds: List[Int] = [240, 30, 210, 180, 150, 120, 90, 60]
    for texel in range(16):
        assert_equal(one.pixels[texel * 4], UInt8(reds[texel % 8]))
        assert_equal(one.pixels[texel * 4 + 1], UInt8(0))
        assert_equal(one.pixels[texel * 4 + 2], UInt8(0))
        assert_equal(one.pixels[texel * 4 + 3], UInt8(255))
    # BC5 is two: red, then green.
    var pair = red.copy()
    pair.extend(alpha_block(50, 200, same(7)))
    var two = decode_compressed(4, 4, pair, RED_GREEN_RGTC2_FORMAT)
    assert_equal(two.pixels[0], UInt8(240))
    assert_equal(two.pixels[1], UInt8(255))
    # Data, not color: LINEAR by default, and SRGB is refused.
    var image = compressed_texture(4, 4, pair, RED_GREEN_RGTC2_FORMAT)
    assert_equal(image.color_space, LINEAR)
    with assert_raises(contains="RED_GREEN_RGTC2_Format holds data"):
        _ = compressed_texture(
            4, 4, pair, RED_GREEN_RGTC2_FORMAT, color_space=SRGB
        )


def test_signed_rgtc_blocks_decode_to_floats() raises:
    # 127 above -127: six blends from 1 down to -1, worked in floats.
    var above = alpha_block(127, 0x81, repeated([0, 1, 2, 3, 4, 5, 6, 7], 2))
    var falling = signed_rgtc_block(above, 0)
    var expected: List[Float32] = [
        1, -1, Float32(5) / 7, Float32(3) / 7, Float32(1) / 7,
        Float32(-1) / 7, Float32(-3) / 7, Float32(-5) / 7,
    ]  # fmt: skip
    for texel in range(16):
        assert_equal(falling[texel], expected[texel % 8])
    # -128, read as -127, not above 0: four blends, then -1 and 1.
    var below = alpha_block(0x80, 0, repeated([0, 1, 2, 3, 4, 5, 6, 7], 2))
    var rising = signed_rgtc_block(below, 0)
    var ends: List[Float32] = [
        -1, 0, Float32(-4) / 5, Float32(-3) / 5, Float32(-2) / 5,
        Float32(-1) / 5, -1, 1,
    ]  # fmt: skip
    for texel in range(16):
        assert_equal(rising[texel], ends[texel % 8])
    var one = decode_compressed(4, 4, above, SIGNED_RED_RGTC1_FORMAT)
    assert_equal(one.texel_type, FLOAT_TYPE)
    assert_equal(one.floats[0], Float32(1))
    assert_equal(one.floats[1], Float32(0))
    assert_equal(one.floats[3], Float32(1))
    var pair = above.copy()
    pair.extend(below^)
    var two = compressed_texture(4, 4, pair, SIGNED_RED_GREEN_RGTC2_FORMAT)
    assert_false(two.flip_y)
    assert_equal(two.texel_type, FLOAT_TYPE)
    assert_equal(two.data[1], Float32(-1))


def test_every_format_says_what_it_is() raises:
    # Eighteen formats: the byte size of a block, whether they decode to
    # floats, whether they hold color, and their three.js names.
    var eight: List[Int] = [0, 1, 4, 5, 11, 12, 14, 15]
    var floats: List[Int] = [5, 7, 8, 9, 14, 15, 16, 17]
    var colors: List[Int] = [0, 1, 2, 3, 10, 11, 12, 13]
    for value in range(18):
        var format = CompressedFormat(value)
        assert_true(format.is_valid())
        assert_equal(format.block_bytes() == 8, value in eight)
        assert_equal(format.is_float(), value in floats)
        assert_equal(format.is_color(), value in colors)
        assert_equal(format.is_s3tc(), value <= 3)
    assert_false(CompressedFormat(-1).is_s3tc())
    assert_equal(String(RGBA_BPTC_FORMAT), "RGBA_BPTC_Format")
    assert_equal(String(SIGNED_RG11_EAC_FORMAT), "SIGNED_RG11_EAC_Format")
    assert_equal(String(CompressedFormat(99)), "CompressedFormat(99)")


def test_a_color_format_can_be_read_as_linear() raises:
    var data = color_block(RED565, BLUE565, same(0))
    assert_equal(
        compressed_texture(4, 4, data, RGB_S3TC_DXT1_FORMAT).color_space, SRGB
    )
    var linear = compressed_texture(
        4, 4, data, RGB_S3TC_DXT1_FORMAT, color_space=LINEAR
    )
    assert_equal(linear.color_space, LINEAR)


def test_a_float_decode_is_bounded_more_tightly() raises:
    # Sixteen bytes a texel instead of four.
    check_decoded_size(16384, 16384, False)
    with assert_raises(contains="MAX_DECODED_BYTES"):
        check_decoded_size(16384, 16384, True)
    check_decoded_size(8192, 8192, True)
    assert_equal(MAX_DECODED_BYTES, 1 << 30)


def test_chains_and_level_sizes() raises:
    assert_equal(chain_length(1, 1), 1)
    assert_equal(chain_length(8, 2), 4)
    assert_equal(chain_length(5, 9), 4)
    # Whole blocks, rounded up.
    assert_equal(level_bytes(1, 1, RGB_S3TC_DXT1_FORMAT), 8)
    assert_equal(level_bytes(5, 3, RGBA_BPTC_FORMAT), 32)


def test_a_compressed_image_names_its_faces_and_levels() raises:
    # Two levels of an 8 by 4 image: two blocks, then one.
    var image = CompressedImage(8, 4, RGB_S3TC_DXT1_FORMAT, LINEAR, 1, 2)
    var first = color_block(RED565, RED565, same(0))
    first.extend(color_block(BLUE565, BLUE565, same(0)))
    image.mipmaps.append(first^)
    image.mipmaps.append(color_block(BLUE565, BLUE565, same(0)))
    assert_equal(image.level_width(1), 4)
    assert_equal(image.level_height(1), 2)
    assert_equal(image.level_width(5), 1)
    assert_equal(image.level_height(5), 1)
    var top = image.texture()
    assert_equal(top.width, 8)
    assert_equal(top.color_space, LINEAR)
    assert_equal(top.texel(7, 0).b, UInt8(255))
    var small = image.texture(0, 1, REPEAT, NEAREST, True, IGNORED)
    assert_equal(small.width, 4)
    assert_equal(small.height, 2)
    assert_equal(small.wrap_s, REPEAT)
    assert_equal(small.levels, 3)
    for face in [-1, 1]:
        with assert_raises(contains="no face"):
            _ = image.texture(face)
    for level in [-1, 2]:
        with assert_raises(contains="no level"):
            _ = image.texture(0, level)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
