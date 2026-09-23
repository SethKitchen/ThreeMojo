# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.etc`: ETC1, ETC2 and EAC blocks against worked-out
texels and against a reference decoder.

The hand-built blocks spell each mode's bits, and their texels are worked
out in the comments. The reference vectors are blocks of every ETC2 mode,
and ETC2 blocks with EAC alpha, each with the texels the ETC decoder of
`texture2ddecoder` gives for it: the block in hex, then sixty-four RGBA
bytes in hex.
"""

from render.compressed_texture import (
    R11_EAC_FORMAT,
    RG11_EAC_FORMAT,
    RGB_ETC1_FORMAT,
    RGB_ETC2_FORMAT,
    RGBA_ETC2_EAC_FORMAT,
    SIGNED_R11_EAC_FORMAT,
    SIGNED_RG11_EAC_FORMAT,
    compressed_texture,
    decode_compressed,
)
from render.etc import (
    EtcTables,
    eac_alpha_block,
    eac_r11_block,
    etc2_color_block,
)
from render.srgb import LINEAR, SRGB
from render.texture import FLOAT_TYPE, UNSIGNED_BYTE_TYPE
from std.testing import TestSuite, assert_equal, assert_raises


def hex_bytes(text: String, at: Int, count: Int) raises -> List[UInt8]:
    """Return `count` bytes spelled in hex in `text` from digit `at`."""
    var out = List[UInt8]()
    var bytes = text.as_bytes()
    for index in range(count * 2):
        var c = Int(bytes[at + index])
        var digit = c - 48
        if c >= 97:
            digit = c - 87
        if index % 2 == 0:
            out.append(UInt8(digit * 16))
        else:
            out[len(out) - 1] += UInt8(digit)
    return out^


def texel(texels: List[UInt8], x: Int, y: Int) -> List[Int]:
    """Return one texel's red, green and blue."""
    var at = (y * 4 + x) * 4
    return [Int(texels[at]), Int(texels[at + 1]), Int(texels[at + 2])]


def gray(value: Int) -> List[Int]:
    """Return a gray texel's three channels."""
    return [value, value, value]


def assert_texel(texels: List[UInt8], x: Int, y: Int, rgb: List[Int]) raises:
    """Check one texel's red, green and blue, and that it is opaque."""
    var got = texel(texels, x, y)
    for channel in range(3):
        assert_equal(got[channel], rgb[channel])
    assert_equal(texels[(y * 4 + x) * 4 + 3], UInt8(255))


def test_etc2_vectors_match_the_reference_decoder() raises:
    var tables = EtcTables()
    var vectors = etc2_vectors()
    for vector in range(len(vectors)):
        var block = hex_bytes(vectors[vector], 0, 8)
        var expected = hex_bytes(vectors[vector], 16, 64)
        var texels = etc2_color_block(block, 0, tables)
        for index in range(64):
            assert_equal(texels[index], expected[index])


def test_etc2_eac_vectors_match_the_reference_decoder() raises:
    var vectors = etc2_eac_vectors()
    for vector in range(len(vectors)):
        var block = hex_bytes(vectors[vector], 0, 16)
        var expected = hex_bytes(vectors[vector], 32, 64)
        var decoded = decode_compressed(4, 4, block, RGBA_ETC2_EAC_FORMAT)
        for index in range(64):
            assert_equal(decoded.pixels[index], expected[index])


def test_an_individual_block_has_two_four_bit_halves() raises:
    # Left half gray 8 (136), right half gray 0; tables 0 and 7; no flip.
    # Texel (0, 0) has index 1, +8; (1, 0) index 3, -8; (2, 0) index 2,
    # -47; (3, 0) index 1, +183. Every other texel is index 0: +2 on the
    # left, +47 on the right.
    var block: List[UInt8] = [0x80, 0x80, 0x80, 0x1C, 0x01, 0x10, 0x10, 0x11]
    var texels = etc2_color_block(block, 0, EtcTables())
    assert_texel(texels, 0, 0, gray(144))
    assert_texel(texels, 1, 0, gray(128))
    assert_texel(texels, 2, 0, gray(0))
    assert_texel(texels, 3, 0, gray(183))
    assert_texel(texels, 1, 3, gray(138))
    assert_texel(texels, 2, 3, gray(47))


def test_a_differential_block_flipped_has_a_top_and_a_bottom() raises:
    # A five-bit 16 in each channel, widened to 132. The bottom half adds
    # three to red, 19 widening to 156, and takes four from green, 12
    # widening to 99. Table 0 and index 0 add two.
    var block: List[UInt8] = [0x83, 0x84, 0x80, 0x03, 0, 0, 0, 0]
    var texels = etc2_color_block(block, 0, EtcTables())
    assert_texel(texels, 3, 1, gray(134))
    assert_texel(texels, 0, 2, [158, 101, 134])


def test_a_red_overflow_is_the_t_mode() raises:
    # Red 1 plus -3 leaves the range. The first color is (5, 10, 3), the
    # second gray 8, and the distance index 5 is 32. The first column
    # takes each paint color in turn; the rest take the first.
    var block: List[UInt8] = [0x0D, 0xA3, 0x88, 0x8B, 0x00, 0x0C, 0x00, 0x0A]
    var texels = etc2_color_block(block, 0, EtcTables())
    assert_texel(texels, 0, 0, [85, 170, 51])
    assert_texel(texels, 0, 1, gray(168))
    assert_texel(texels, 0, 2, gray(136))
    assert_texel(texels, 0, 3, gray(104))
    assert_texel(texels, 3, 3, [85, 170, 51])


def test_a_green_overflow_is_the_h_mode() raises:
    # Green 0 plus -2 leaves the range. The colors are (4, 6, 5) and
    # (12, 9, 2); the first sorts below the second, so the distance's low
    # bit is zero and the distance index 4 is 23.
    var block: List[UInt8] = [0x23, 0x06, 0xE4, 0x96, 0x00, 0x0C, 0x00, 0x0A]
    var texels = etc2_color_block(block, 0, EtcTables())
    assert_texel(texels, 0, 0, [91, 125, 108])
    assert_texel(texels, 0, 1, [45, 79, 62])
    assert_texel(texels, 0, 2, [227, 176, 57])
    assert_texel(texels, 0, 3, [181, 130, 11])


def test_a_blue_overflow_is_the_planar_mode() raises:
    # Blue 0 plus -4 leaves the range. The origin is (32, 64, 0), widened
    # to (130, 129, 0); one step right has a red of zero, and one step
    # down is the origin again. Red falls across and nothing changes down.
    var block: List[UInt8] = [0x41, 0x00, 0x04, 0x02, 0x80, 0x04, 0x10, 0x00]
    var texels = etc2_color_block(block, 0, EtcTables())
    var reds: List[Int] = [130, 98, 65, 33]
    for x in range(4):
        for y in range(4):
            assert_texel(texels, x, y, [reds[x], 129, 0])


def eac_block(base: Int, fields: Int, indices: List[Int]) -> List[UInt8]:
    """Return an EAC block: a base, the multiplier and table byte, and
    sixteen three-bit indices in column-major order, the first on top."""
    var bits = 0
    for index in range(16):
        bits = (bits << 3) | indices[index]
    var out: List[UInt8] = [UInt8(base), UInt8(fields)]
    for byte in range(6):
        out.append(UInt8((bits >> ((5 - byte) * 8)) & 0xFF))
    return out^


def column_major(first: Int, second: Int, rest: Int) -> List[Int]:
    """Return sixteen indices: `first` and `second` down the first column,
    then `rest`."""
    var out = List[Int](length=16, fill=rest)
    out[0] = first
    out[1] = second
    return out^


def test_an_eac_alpha_block_adds_offsets_times_the_multiplier() raises:
    # Base 100, multiplier 2, table 13: -1, -2, -3, -10, 0, 1, 2, 9.
    var block = eac_block(100, 0x2D, column_major(7, 3, 4))
    var alphas = eac_alpha_block(block, 0, EtcTables())
    assert_equal(alphas[0], UInt8(118))
    assert_equal(alphas[4], UInt8(80))
    assert_equal(alphas[1], UInt8(100))
    # Base 250, multiplier 15, table 0: past the top and far down.
    var edge = eac_block(250, 0xF0, column_major(7, 3, 7))
    var clamped = eac_alpha_block(edge, 0, EtcTables())
    assert_equal(clamped[0], UInt8(255))
    assert_equal(clamped[4], UInt8(25))


def test_an_r11_block_keeps_eleven_bits() raises:
    var tables = EtcTables()
    # 128 * 8 + 4 + 9 * 1 * 8 = 1100; and with a multiplier of zero the
    # offset is added once, 1028 + 9.
    var one = eac_r11_block(
        eac_block(128, 0x1D, column_major(7, 7, 7)), 0, False, tables
    )
    assert_equal(one[0], Float32(1100) / 2047)
    var zero = eac_r11_block(
        eac_block(128, 0x0D, column_major(7, 7, 7)), 0, False, tables
    )
    assert_equal(zero[0], Float32(1037) / 2047)
    # Past the top, and past the bottom.
    var edge = eac_r11_block(
        eac_block(255, 0xF0, column_major(7, 3, 7)), 0, False, tables
    )
    assert_equal(edge[0], Float32(1))
    var low = eac_r11_block(
        eac_block(0, 0xF0, column_major(3, 3, 3)), 0, False, tables
    )
    assert_equal(low[0], Float32(0))


def test_a_signed_r11_block_reads_a_signed_base() raises:
    var tables = EtcTables()
    # -128 is read as -127: -1016, plus 9 once with a multiplier of zero.
    var most = eac_r11_block(
        eac_block(0x80, 0x0D, column_major(7, 7, 7)), 0, True, tables
    )
    assert_equal(most[0], Float32(-1007) / 1023)
    # 127 * 8 + 14 * 120 is past 1023, and -127 * 8 - 15 * 120 past -1023.
    var top = eac_r11_block(
        eac_block(127, 0xF0, column_major(7, 7, 7)), 0, True, tables
    )
    assert_equal(top[0], Float32(1))
    var bottom = eac_r11_block(
        eac_block(0x81, 0xF0, column_major(3, 3, 3)), 0, True, tables
    )
    assert_equal(bottom[0], Float32(-1))


def test_etc_formats_decode_through_compressed_texture() raises:
    var color: List[UInt8] = [0x83, 0x84, 0x80, 0x03, 0, 0, 0, 0]
    for format in [RGB_ETC1_FORMAT, RGB_ETC2_FORMAT]:
        var image = compressed_texture(4, 4, color, format)
        assert_equal(image.color_space, SRGB)
        assert_equal(image.texel_type, UNSIGNED_BYTE_TYPE)
        assert_equal(image.texel(0, 3).r, UInt8(158))
    # R11 gives red; RG11 red and green; blue is zero and alpha one.
    var red = eac_block(128, 0x1D, column_major(7, 7, 7))
    var decoded = decode_compressed(4, 4, red, R11_EAC_FORMAT)
    assert_equal(decoded.texel_type, FLOAT_TYPE)
    assert_equal(decoded.floats[0], Float32(1100) / 2047)
    assert_equal(decoded.floats[1], Float32(0))
    assert_equal(decoded.floats[3], Float32(1))
    var pair = red.copy()
    pair.extend(eac_block(0, 0xF0, column_major(3, 3, 3)))
    var both = decode_compressed(4, 4, pair, RG11_EAC_FORMAT)
    assert_equal(both.floats[0], Float32(1100) / 2047)
    assert_equal(both.floats[1], Float32(0))
    var signed = decode_compressed(4, 4, red, SIGNED_R11_EAC_FORMAT)
    # Signed, the same base byte is -128, read as -127: -1016 + 72.
    assert_equal(signed.floats[0], Float32(-944) / 1023)
    var signed_pair = decode_compressed(4, 4, pair, SIGNED_RG11_EAC_FORMAT)
    assert_equal(signed_pair.floats[1], Float32(-1))
    var texture = compressed_texture(4, 4, red, R11_EAC_FORMAT)
    assert_equal(texture.color_space, LINEAR)
    with assert_raises(contains="holds data"):
        _ = compressed_texture(4, 4, red, R11_EAC_FORMAT, color_space=SRGB)


def etc2_vectors() -> List[String]:
    """Return the reference vectors; see the module docstring."""
    return [
        "95054f3083bf5521880033ff94003fff1919c3ff9191ffff94003fff880033ff4343edff6767ffff94003fff9e0549ff9191ffff9191ffff94003fff94003fff6767ffff4343edff",  # individual0
        "297e91fc884cf0e1d9ffffff51a6c8ffc8ff40ffffffc8ff51a6c8ffd9ffffffc8ff40ffffffc8ff00486aff000000ffc8ff40ffffffc8ff00486affd9ffffff6abf00ff003700ff",  # individual0
        "2c2628fdeb943f50515151ff000000ff000000ffd9d9d9ff515151ff515151ff000000ff000000ff9d3759ffffffffffffffffff9d3759fffb95b7ff9d3759ff150000ff9d3759ff",  # individual1
        "8eefa0759cea4273b2ffd4ffb2ffd4ff95fbb7ff7be19dff5ec480ff5ec480ffb2ffd4ff95fbb7ffffff18ff9eaf00ffd6e700ffffff50ffd6e700ffd6e700ffd6e700ffd6e700ff",  # individual1
        "370f64ae87badf6249207bff19004bff000018ff532a6cff000013ff000013ff000018ff360d4fff49207bff8158b3ff000018ff532a6cff19004bff19004bff532a6cff000018ff",  # differential0
        "da82e0e61b902ba2ffb3ffffaf55b8ffde83d6ffea8fe2ffffffffffffffffffde83d6ffffa5f8ffffb3ffffffb3fffff499ecfff499ecffffb3ffff270030ffde83d6fff499ecff",  # differential0
        "a745255b42ddd109882504ff9c3918ffc25f3effc25f3effae4b2affae4b2aff9c3918ffae4b2aff7b0800ff7b0800ffbd4a29ff320000ff320000ff7b0800ffbd4a29ffff9372ff",  # differential1
        "6fe4c9071648d3366de9d0ff73efd6ff73efd6ff63dfc6ff73efd6ff73efd6ff63dfc6ff6de9d0ff74d7e7ff5ec1d1ff5ec1d1ff74d7e7ff5ec1d1ff68cbdbff68cbdbff74d7e7ff",  # differential1
        "fa9b9ca68b57350d8ec19fff99ccaaff8ec19fffa4d7b5ff99ccaaffee99bbff99ccaaffa4d7b5ff8ec19fff99ccaaffa4d7b5ffee99bbffa4d7b5ffee99bbff99ccaaff99ccaaff",  # t
        "067a3c37ceb778ee33cc33ff33cc33ff2277aaff43dc43ff23bc23ff23bc23ff33cc33ff43dc43ff23bc23ff43dc43ff33cc33ff23bc23ff43dc43ff23bc23ff23bc23ff33cc33ff",  # t
        "4b0c88c2da603185936093ff9f6c9fff936093ff0b0b82ff9f6c9fff17178eff17178eff936093ff936093ff17178eff9f6c9fff17178eff9f6c9fff936093ff17178eff17178eff",  # h
        "cd1c8b6e538f4fea3186fdffb9dbb9ff0046bdff3186fdff0046bdff799b79ff0046bdffb9dbb9ff3186fdff799b79ff799b79ff0046bdff0046bdff0046bdff799b79ffb9dbb9ff",  # h
        "332e047a7582eaaa65af00ff89a031ffac9262ffd08392ff63982bff878a5bffaa7b8cffce6cbdff618255ff857386ffa864b7ffcc55e7ff5f6b80ff835cb0ffa64de1ffca3fffff",  # planar
        "eed71c9bab79543cdf56e7ffb46bddff8a81d3ff5f96c8ffb169eaff877ee0ff5c93d6ff31a9cbff847cedff5991e3ff2ea6d9ff03bbceff568ef0ff2ba4e6ff00b9dcff00ced1ff",  # planar
    ]


def etc2_eac_vectors() -> List[String]:
    """Return the reference vectors; see the module docstring."""
    return [
        "be082bb0dea73e25237fb341bfe36320196eb2be2b80c4be055a9ebe196eb2be196eb2be055a9ebe055a9ebe055a9ebe35ff35be31fd31be31fd31be3bff3bbe35ff35be31fd31be31fd31be31fd31be",
        "cc075c6b3c5699531487e21f854ab93a888877ccff6251ccae0000ccff6251ccae0000ccff6251cc888877ccff6251cc888877ccee2211ccee2211cc888877ccae0000cc888877ccff6251ccae0000cc",
        "f9f4ac3c6dc8f1a94c108e56d4784174531995ff2d006fff7960cbff110063cc531995452d006f9f41289381412893ff672da9cc2d006fff1100639f00002bff41078345531995ff412893ff1100639f",
        "9979be164ac42daebb20922ee6541f67ce32a5b5b81c8f53ff4bcfcaff4bcfcace32a5d8ce32a576ac007b76c91498caac1083a0ac108376ac007b8bc91498b5c2269976c2269961ff4bcf61c91498ca",
        "c6f998a43050e03672a4888a6d74c12a85b79ed561937a4e67676f4e8d8d95a8afe1c8ff376950a88d8d95d57b7b83a861937a7b61937aff7b7b837b67676fffafe1c84e85b79ea87b7b83ffa1a1a9ff",
    ]


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
