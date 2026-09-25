# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.texture_utils` and `render.data_utils`.

The expected numbers come from three.js 0.180's `TextureUtils` and
`DataUtils`, run in Node on the same inputs. The half-float tests also
build three.js's own conversion tables here and hold both functions to
them for every half and for every float exponent.
"""

from render.data_utils import from_half_float, to_half_float
from render.texture import Texture
from render.texture_utils import (
    TextureDataType,
    TextureFormat,
    byte_length,
    contain,
    cover,
    fill,
)
from std.math import inf, isnan, nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime TOLERANCE = Float64(1e-6)


def _sized(width: Int, height: Int) -> Texture:
    """Return a blank texture that reports a size, which is all the fitting
    functions read."""
    var texture = Texture()
    texture.width = width
    texture.height = height
    return texture^


def assert_fit(
    texture: Texture,
    repeat_x: Float64,
    repeat_y: Float64,
    offset_x: Float64,
    offset_y: Float64,
) raises:
    """Assert a texture's repeat and offset, within tolerance.

    Args:
        texture: The texture to check.
        repeat_x: Expected horizontal repeat.
        repeat_y: Expected vertical repeat.
        offset_x: Expected horizontal offset.
        offset_y: Expected vertical offset.

    Raises:
        Error: If any of the four differs.
    """
    assert_almost_equal(texture.repeat.x, Float32(repeat_x), atol=TOLERANCE)
    assert_almost_equal(texture.repeat.y, Float32(repeat_y), atol=TOLERANCE)
    assert_almost_equal(texture.offset.x, Float32(offset_x), atol=TOLERANCE)
    assert_almost_equal(texture.offset.y, Float32(offset_y), atol=TOLERANCE)


def test_contain_and_cover_match_three_js() raises:
    var wide = _sized(400, 200)
    contain(wide, 1.5)
    assert_fit(wide, 1, 1.3333333333333333, 0, -0.16666666666666663)
    cover(wide, 1.5)
    assert_fit(wide, 0.75, 1, 0.125, 0)
    var tall = _sized(200, 400)
    contain(tall, 1.5)
    assert_fit(tall, 3, 1, -1, 0)
    cover(tall, 1.5)
    assert_fit(tall, 1, 0.3333333333333333, 0, 0.33333333333333337)
    var same = _sized(300, 200)
    contain(same, 1.5)
    assert_fit(same, 1, 1, 0, 0)
    cover(same, 1.5)
    assert_fit(same, 1, 1, 0, 0)
    # No image is an aspect of one, as three.js's `imageAspect` has it.
    var blank = Texture()
    contain(blank, 2)
    assert_fit(blank, 2, 1, -0.5, 0)
    fill(blank)
    assert_fit(blank, 1, 1, 0, 0)


def test_an_aspect_that_is_not_a_positive_number_is_refused() raises:
    var texture = _sized(400, 200)
    with assert_raises():
        contain(texture, 0)
    with assert_raises():
        cover(texture, -1)
    with assert_raises():
        contain(texture, inf[DType.float64]())
    assert_fit(texture, 1, 1, 0, 0)


def _formats() -> List[TextureFormat]:
    """Return every format, in the order the Node fixtures list them."""
    return [
        TextureFormat.ALPHA,
        TextureFormat.RED,
        TextureFormat.RED_INTEGER,
        TextureFormat.RG,
        TextureFormat.RG_INTEGER,
        TextureFormat.RGB,
        TextureFormat.RGBA,
        TextureFormat.RGBA_INTEGER,
        TextureFormat.RGB_S3TC_DXT1,
        TextureFormat.RGBA_S3TC_DXT1,
        TextureFormat.RGBA_S3TC_DXT3,
        TextureFormat.RGBA_S3TC_DXT5,
        TextureFormat.RGB_PVRTC_2BPPV1,
        TextureFormat.RGBA_PVRTC_2BPPV1,
        TextureFormat.RGB_PVRTC_4BPPV1,
        TextureFormat.RGBA_PVRTC_4BPPV1,
        TextureFormat.RGB_ETC1,
        TextureFormat.RGB_ETC2,
        TextureFormat.RGBA_ETC2_EAC,
        TextureFormat.RGBA_ASTC_4X4,
        TextureFormat.RGBA_ASTC_5X4,
        TextureFormat.RGBA_ASTC_5X5,
        TextureFormat.RGBA_ASTC_6X5,
        TextureFormat.RGBA_ASTC_6X6,
        TextureFormat.RGBA_ASTC_8X5,
        TextureFormat.RGBA_ASTC_8X6,
        TextureFormat.RGBA_ASTC_8X8,
        TextureFormat.RGBA_ASTC_10X5,
        TextureFormat.RGBA_ASTC_10X6,
        TextureFormat.RGBA_ASTC_10X8,
        TextureFormat.RGBA_ASTC_10X10,
        TextureFormat.RGBA_ASTC_12X10,
        TextureFormat.RGBA_ASTC_12X12,
        TextureFormat.RGBA_BPTC,
        TextureFormat.RGB_BPTC_SIGNED,
        TextureFormat.RGB_BPTC_UNSIGNED,
        TextureFormat.RED_RGTC1,
        TextureFormat.SIGNED_RED_RGTC1,
        TextureFormat.RED_GREEN_RGTC2,
        TextureFormat.SIGNED_RED_GREEN_RGTC2,
    ]


def _types() -> List[TextureDataType]:
    """Return every type, in the order the Node fixtures list them."""
    return [
        TextureDataType.UNSIGNED_BYTE,
        TextureDataType.BYTE,
        TextureDataType.SHORT,
        TextureDataType.UNSIGNED_SHORT,
        TextureDataType.INT,
        TextureDataType.UNSIGNED_INT,
        TextureDataType.FLOAT,
        TextureDataType.HALF_FLOAT,
        TextureDataType.UNSIGNED_SHORT_4444,
        TextureDataType.UNSIGNED_SHORT_5551,
        TextureDataType.UNSIGNED_INT_248,
        TextureDataType.UNSIGNED_INT_5999,
        TextureDataType.UNSIGNED_INT_101111,
    ]


def test_the_values_are_three_js_numbers() raises:
    var formats: List[Int] = [
        1021, 1028, 1029, 1030, 1031, 1022, 1023, 1033, 33776, 33777,
        33778, 33779, 35841, 35843, 35840, 35842, 36196, 37492, 37496,
        37808, 37809, 37810, 37811, 37812, 37813, 37814, 37815, 37816,
        37817, 37818, 37819, 37820, 37821, 36492, 36494, 36495, 36283,
        36284, 36285, 36286,
    ]  # fmt: skip
    var types: List[Int] = [
        1009, 1010, 1011, 1012, 1013, 1014, 1015, 1016, 1017, 1018, 1020,
        35902, 35899,
    ]  # fmt: skip
    var all_formats = _formats()
    for index in range(len(formats)):
        assert_equal(all_formats[index].value, formats[index])
        assert_true(all_formats[index].is_valid())
    var all_types = _types()
    for index in range(len(types)):
        assert_equal(all_types[index].value, types[index])
        assert_true(all_types[index].is_valid())
    assert_false(TextureFormat(1024).is_valid())
    assert_false(TextureFormat(40000).is_valid())
    assert_false(TextureDataType(1019).is_valid())
    assert_false(TextureDataType(1008).is_valid())
    assert_equal(String(TextureFormat.RGBA), "TextureFormat(1023)")
    assert_equal(String(TextureDataType.FLOAT), "TextureDataType(1015)")


def test_byte_length_matches_three_js_for_every_format() raises:
    var odd: List[Float64] = [
        153, 153, 153, 306, 306, 459, 612, 612, 120, 120, 240, 240, 38.25,
        38.25, 76.5, 76.5, 120, 120, 240, 240, 192, 128, 96, 96, 96, 96,
        96, 64, 64, 64, 32, 32, 32, 240, 240, 240, 120, 120, 240, 240,
    ]  # fmt: skip
    var one: List[Float64] = [
        1, 1, 1, 2, 2, 3, 4, 4, 8, 8, 16, 16, 32, 32, 32, 32, 8, 8, 16, 16,
        16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 8,
        8, 16, 16,
    ]  # fmt: skip
    var formats = _formats()
    for index in range(len(formats)):
        assert_equal(
            byte_length(17, 9, formats[index], TextureDataType.UNSIGNED_BYTE),
            odd[index],
        )
        assert_equal(
            byte_length(1, 1, formats[index], TextureDataType.UNSIGNED_BYTE),
            one[index],
        )


def test_byte_length_matches_three_js_for_every_type() raises:
    # -1 is where three.js throws: `UnsignedInt248Type`.
    var red: List[Float64] = [
        15,
        15,
        30,
        30,
        60,
        60,
        60,
        30,
        7.5,
        7.5,
        -1,
        20,
        20,
    ]
    var rgba: List[Float64] = [
        60,
        60,
        120,
        120,
        240,
        240,
        240,
        120,
        30,
        30,
        -1,
        80,
        80,
    ]
    var types = _types()
    for index in range(len(types)):
        if red[index] < 0:
            with assert_raises():
                _ = byte_length(5, 3, TextureFormat.RED, types[index])
            continue
        assert_equal(
            byte_length(5, 3, TextureFormat.RED, types[index]), red[index]
        )
        assert_equal(
            byte_length(5, 3, TextureFormat.RGBA, types[index]), rgba[index]
        )


def test_byte_length_refuses_what_is_not_a_size_format_or_type() raises:
    var ok = TextureDataType.UNSIGNED_BYTE
    assert_equal(byte_length(0, 0, TextureFormat.RGBA, ok), 0)
    with assert_raises():
        _ = byte_length(-1, 1, TextureFormat.RGBA, ok)
    with assert_raises():
        _ = byte_length(1, -1, TextureFormat.RGBA, ok)
    with assert_raises():
        _ = byte_length(1, 1, TextureFormat(1024), ok)
    with assert_raises():
        _ = byte_length(1, 1, TextureFormat.RGBA, TextureDataType(1019))


def test_half_floats_match_three_js() raises:
    var values: List[Float64] = [
        0, -0.0, 1, -2, 65504, 1e6, -1e6, 1e-10, -1e-10, 2.0**-20, 0.1,
        1.0 / 3, 65519, 5.960464477539063e-8, nan[DType.float64](),
        inf[DType.float64](), -inf[DType.float64](), 3.14159, 1e-5, 1.0007,
        -3e-6, 6.1e-5,
    ]  # fmt: skip
    var halves: List[Int] = [
        0, 32768, 15360, 49152, 31743, 31743, 64511, 0, 32768, 16, 11878,
        13653, 31743, 1, 65024, 31743, 64511, 16968, 167, 15360, 32818,
        1023,
    ]  # fmt: skip
    for index in range(len(values)):
        assert_equal(Int(to_half_float(values[index])), halves[index])
    var bits: List[Int] = [
        0, 0x8000, 0x3C00, 0xC000, 0x7BFF, 0x0001, 0x03FF, 0x8001, 0x0400,
        0x7C00, 0xFC00, 0x3555, 0x1234,
    ]  # fmt: skip
    var numbers: List[Float32] = [
        0, -0.0, 1, -2, 65504, 5.960464477539063e-8,
        0.00006097555160522461, -5.960464477539063e-8, 0.00006103515625,
        inf[DType.float32](), -inf[DType.float32](), 0.333251953125,
        0.0007572174072265625,
    ]  # fmt: skip
    for index in range(len(bits)):
        assert_equal(
            bitcast[DType.uint32](from_half_float(UInt16(bits[index]))),
            bitcast[DType.uint32](numbers[index]),
        )
    assert_true(isnan(from_half_float(0x7E00)))


def _mantissa(index: Int) -> UInt32:
    """Return three.js's `mantissaTable` entry, built as three.js builds
    it."""
    if index == 0:
        return 0
    if index >= 1024:
        return UInt32(0x38000000 + ((index - 1024) << 13))
    var m = UInt32(index << 13)
    var e = UInt32(0)
    while (m & 0x00800000) == 0:
        m <<= 1
        e -= 0x00800000
    m &= ~UInt32(0x00800000)
    e += 0x38800000
    return m | e


def _exponent(index: Int) -> UInt32:
    """Return three.js's `exponentTable` entry."""
    if index == 0:
        return 0
    if index < 31:
        return UInt32(index << 23)
    if index == 31:
        return 0x47800000
    if index == 32:
        return 0x80000000
    if index < 63:
        return UInt32(0x80000000) + UInt32((index - 32) << 23)
    return 0xC7800000


def test_from_half_float_is_three_js_table_for_every_half() raises:
    for half in range(65536):
        var m = half >> 10
        var offset = 0 if m == 0 or m == 32 else 1024
        var expected = _mantissa(offset + (half & 0x3FF)) + _exponent(m)
        assert_equal(
            bitcast[DType.uint32](from_half_float(UInt16(half))), expected
        )


def _base_and_shift(e: Int) -> Tuple[Int, Int]:
    """Return three.js's `baseTable` and `shiftTable` entries for the top
    nine bits of a float, built as three.js builds them."""
    var i = e & 0xFF
    var sign = 0x8000 if e >= 0x100 else 0
    var exponent = i - 127
    if exponent < -27:
        return (sign, 24)
    if exponent < -14:
        return ((0x0400 >> (-exponent - 14)) | sign, -exponent - 1)
    if exponent <= 15:
        return (((exponent + 15) << 10) | sign, 13)
    if exponent < 128:
        return (0x7C00 | sign, 24)
    return (0x7C00 | sign, 13)


def test_to_half_float_is_three_js_table_for_every_exponent() raises:
    # Four fractions for each sign and exponent a float can have, from the
    # half's range and outside it: the clamp is three.js's too.
    var fractions: List[UInt32] = [0, 1, 0x400000, 0x7FFFFF]
    for e in range(512):
        for index in range(4):
            var f = (UInt32(e) << 23) | fractions[index]
            var value = Float64(bitcast[DType.float32](f))
            if isnan(value):
                # three.js's clamp gives x86-64's NaN, which is negative.
                assert_equal(Int(to_half_float(value)), 0xFE00)
                continue
            var clamped = max(-65504.0, min(65504.0, value))
            var g = bitcast[DType.uint32](Float32(clamped))
            var table = _base_and_shift(Int(g >> 23) & 0x1FF)
            var expected = table[0] + (Int(g & 0x7FFFFF) >> table[1])
            assert_equal(Int(to_half_float(value)), expected)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
