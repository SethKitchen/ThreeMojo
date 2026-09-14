# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.inflate` and `render.png`'s decoder.

The fixtures are real PNG files, written by a conforming encoder and embedded
here as bytes. That is deliberate and is the only way this can be tested
honestly: a decoder checked solely against this project's own encoder would
only ever see DEFLATE *stored* blocks and filter 0, which is the one corner
real files never occupy. These cover fixed and dynamic Huffman codes, all five
row filters, an overlapping back-reference, and every colour type.
"""

from render.framebuffer import Color, Framebuffer
from render.inflate import BitReader, Huffman, inflate, zlib_inflate
from render.png import decode, encode
from render.srgb import SRGB
from render.texture import NEAREST, REPEAT, texture_from
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)


def rgba_png() -> List[UInt8]:
    """A 4x4 RGBA PNG, zlib level 9 (dynamic Huffman)."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(4),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(4),
        UInt8(8),
        UInt8(6),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(169),
        UInt8(241),
        UInt8(158),
        UInt8(126),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(61),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(13),
        UInt8(202),
        UInt8(49),
        UInt8(1),
        UInt8(192),
        UInt8(48),
        UInt8(16),
        UInt8(2),
        UInt8(64),
        UInt8(228),
        UInt8(68),
        UInt8(4),
        UInt8(34),
        UInt8(94),
        UInt8(14),
        UInt8(35),
        UInt8(82),
        UInt8(94),
        UInt8(4),
        UInt8(34),
        UInt8(34),
        UInt8(39),
        UInt8(14),
        UInt8(104),
        UInt8(111),
        UInt8(62),
        UInt8(0),
        UInt8(40),
        UInt8(113),
        UInt8(44),
        UInt8(76),
        UInt8(3),
        UInt8(25),
        UInt8(224),
        UInt8(49),
        UInt8(57),
        UInt8(21),
        UInt8(229),
        UInt8(112),
        UInt8(11),
        UInt8(104),
        UInt8(74),
        UInt8(201),
        UInt8(210),
        UInt8(54),
        UInt8(186),
        UInt8(255),
        UInt8(136),
        UInt8(204),
        UInt8(108),
        UInt8(149),
        UInt8(235),
        UInt8(228),
        UInt8(245),
        UInt8(3),
        UInt8(102),
        UInt8(93),
        UInt8(30),
        UInt8(185),
        UInt8(72),
        UInt8(90),
        UInt8(125),
        UInt8(231),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def grey_all_filters_png() -> List[UInt8]:
    """An 8x8 greyscale PNG using all five row filters, one per row."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(8),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(8),
        UInt8(8),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(225),
        UInt8(100),
        UInt8(225),
        UInt8(87),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(46),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(96),
        UInt8(144),
        UInt8(183),
        UInt8(139),
        UInt8(173),
        UInt8(153),
        UInt8(189),
        UInt8(235),
        UInt8(38),
        UInt8(163),
        UInt8(160),
        UInt8(60),
        UInt8(4),
        UInt8(48),
        UInt8(9),
        UInt8(66),
        UInt8(1),
        UInt8(179),
        UInt8(146),
        UInt8(4),
        UInt8(4),
        UInt8(176),
        UInt8(192),
        UInt8(68),
        UInt8(24),
        UInt8(66),
        UInt8(75),
        UInt8(38),
        UInt8(111),
        UInt8(186),
        UInt8(248),
        UInt8(129),
        UInt8(95),
        UInt8(143),
        UInt8(49),
        UInt8(13),
        UInt8(93),
        UInt8(49),
        UInt8(0),
        UInt8(210),
        UInt8(148),
        UInt8(12),
        UInt8(9),
        UInt8(238),
        UInt8(114),
        UInt8(42),
        UInt8(52),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def palette_png() -> List[UInt8]:
    """A 4x2 palette PNG with a short tRNS; the last entry stays opaque."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(4),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(2),
        UInt8(8),
        UInt8(3),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(72),
        UInt8(118),
        UInt8(141),
        UInt8(81),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(12),
        UInt8(80),
        UInt8(76),
        UInt8(84),
        UInt8(69),
        UInt8(255),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(255),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(255),
        UInt8(255),
        UInt8(255),
        UInt8(0),
        UInt8(214),
        UInt8(2),
        UInt8(143),
        UInt8(123),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(3),
        UInt8(116),
        UInt8(82),
        UInt8(78),
        UInt8(83),
        UInt8(255),
        UInt8(128),
        UInt8(0),
        UInt8(127),
        UInt8(109),
        UInt8(104),
        UInt8(120),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(14),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(96),
        UInt8(96),
        UInt8(100),
        UInt8(98),
        UInt8(6),
        UInt8(99),
        UInt8(0),
        UInt8(0),
        UInt8(66),
        UInt8(0),
        UInt8(13),
        UInt8(104),
        UInt8(0),
        UInt8(236),
        UInt8(241),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def grey_alpha_png() -> List[UInt8]:
    """A 2x2 greyscale-with-alpha PNG."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(2),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(2),
        UInt8(8),
        UInt8(4),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(216),
        UInt8(191),
        UInt8(197),
        UInt8(175),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(18),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(224),
        UInt8(250),
        UInt8(127),
        UInt8(130),
        UInt8(129),
        UInt8(33),
        UInt8(170),
        UInt8(225),
        UInt8(255),
        UInt8(127),
        UInt8(0),
        UInt8(19),
        UInt8(185),
        UInt8(4),
        UInt8(170),
        UInt8(253),
        UInt8(74),
        UInt8(176),
        UInt8(154),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def rgb_keyed_png() -> List[UInt8]:
    """A 2x2 RGB PNG whose pure red is keyed transparent by tRNS."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(2),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(2),
        UInt8(8),
        UInt8(2),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(253),
        UInt8(212),
        UInt8(154),
        UInt8(115),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(6),
        UInt8(116),
        UInt8(82),
        UInt8(78),
        UInt8(83),
        UInt8(0),
        UInt8(255),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(164),
        UInt8(194),
        UInt8(192),
        UInt8(29),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(18),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(248),
        UInt8(207),
        UInt8(192),
        UInt8(192),
        UInt8(0),
        UInt8(194),
        UInt8(12),
        UInt8(255),
        UInt8(129),
        UInt8(36),
        UInt8(0),
        UInt8(28),
        UInt8(241),
        UInt8(3),
        UInt8(253),
        UInt8(215),
        UInt8(96),
        UInt8(180),
        UInt8(71),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def fixed_huffman_png() -> List[UInt8]:
    """A 1x1 RGBA PNG whose DEFLATE stream uses fixed Huffman codes."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(8),
        UInt8(6),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(31),
        UInt8(21),
        UInt8(196),
        UInt8(137),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(1),
        UInt8(99),
        UInt8(96),
        UInt8(100),
        UInt8(98),
        UInt8(254),
        UInt8(15),
        UInt8(0),
        UInt8(1),
        UInt8(20),
        UInt8(1),
        UInt8(6),
        UInt8(36),
        UInt8(201),
        UInt8(37),
        UInt8(183),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def run_png() -> List[UInt8]:
    """A 64x1 RGB PNG of one repeated colour: an overlapping LZ77 run."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(64),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(8),
        UInt8(2),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(225),
        UInt8(15),
        UInt8(63),
        UInt8(64),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(12),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(96),
        UInt8(31),
        UInt8(226),
        UInt8(0),
        UInt8(0),
        UInt8(251),
        UInt8(112),
        UInt8(5),
        UInt8(65),
        UInt8(171),
        UInt8(39),
        UInt8(119),
        UInt8(225),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def test_a_stored_block_round_trips_through_our_own_encoder() raises:
    # The easy half: what this project writes, read back. Catches nothing
    # about Huffman codes, which is exactly why the fixtures below exist.
    var image = Framebuffer(3, 2, Color(10, 20, 30))
    var back = decode(encode(image))
    assert_equal(back.width, 3)
    assert_equal(back.height, 2)
    assert_equal(back.get_pixel(2, 1).r, UInt8(10))
    assert_equal(back.get_pixel(2, 1).b, UInt8(30))


def test_a_dynamic_huffman_rgba_file_decodes() raises:
    var image = decode(rgba_png())
    assert_equal(image.width, 4)
    assert_equal(image.height, 4)
    # Worked out from the fixture's own generator: red is x * 60.
    assert_equal(image.get_pixel(0, 0).r, UInt8(0))
    assert_equal(image.get_pixel(2, 0).r, UInt8(120))
    assert_equal(image.get_pixel(1, 1).g, UInt8(60))
    # Alpha alternates 255, 128 along the diagonal parity.
    assert_equal(image.get_pixel(0, 0).a, UInt8(255))
    assert_equal(image.get_pixel(1, 0).a, UInt8(128))


def test_a_fixed_huffman_file_decodes() raises:
    # The other compressed block type, which a normal encoder only picks for
    # very short streams.
    var image = decode(fixed_huffman_png())
    assert_equal(image.width, 1)
    assert_equal(image.get_pixel(0, 0).r, UInt8(1))
    assert_equal(image.get_pixel(0, 0).g, UInt8(2))
    assert_equal(image.get_pixel(0, 0).b, UInt8(3))
    assert_equal(image.get_pixel(0, 0).a, UInt8(255))


def test_every_row_filter_is_undone() raises:
    # Eight rows, cycling through filters 0 to 4. The generated value is
    # (x * 31 + y * 17) & 255, so every pixel has an independently known
    # answer -- a filter applied but not undone shows up immediately.
    var image = decode(grey_all_filters_png())
    assert_equal(image.width, 8)
    assert_equal(image.height, 8)
    for y in range(8):
        for x in range(8):
            var want = UInt8((x * 31 + y * 17) & 255)
            assert_equal(image.get_pixel(x, y).r, want)
            # Greyscale widens to RGB, and is opaque with no tRNS.
            assert_equal(image.get_pixel(x, y).b, want)
            assert_equal(image.get_pixel(x, y).a, UInt8(255))


def test_an_overlapping_back_reference_repeats_correctly() raises:
    # A run of one colour is stored as a byte and a distance of one, so the
    # copy reads bytes it is itself producing. Capturing the source up front
    # gives three bytes and then garbage.
    var image = decode(run_png())
    assert_equal(image.width, 64)
    for x in range(64):
        assert_equal(image.get_pixel(x, 0).r, UInt8(7))
        assert_equal(image.get_pixel(x, 0).g, UInt8(7))


def test_a_palette_image_is_expanded() raises:
    var image = decode(palette_png())
    assert_equal(image.width, 4)
    # Entry 0 is red, 1 green, 2 blue, 3 yellow; index is (x + y) % 4.
    assert_equal(image.get_pixel(0, 0).r, UInt8(255))
    assert_equal(image.get_pixel(0, 0).g, UInt8(0))
    assert_equal(image.get_pixel(1, 0).g, UInt8(255))
    assert_equal(image.get_pixel(2, 0).b, UInt8(255))


def test_a_short_trns_leaves_the_rest_of_the_palette_opaque() raises:
    # Three alphas for four entries: the fourth is opaque by omission, which
    # the specification says and a naive reader gets wrong by indexing past
    # the end.
    var image = decode(palette_png())
    assert_equal(image.get_pixel(0, 0).a, UInt8(255))
    assert_equal(image.get_pixel(1, 0).a, UInt8(128))
    assert_equal(image.get_pixel(2, 0).a, UInt8(0))
    assert_equal(image.get_pixel(3, 0).a, UInt8(255))


def test_greyscale_with_alpha_decodes() raises:
    var image = decode(grey_alpha_png())
    assert_equal(image.get_pixel(0, 0).r, UInt8(10))
    assert_equal(image.get_pixel(0, 0).a, UInt8(255))
    assert_equal(image.get_pixel(1, 0).r, UInt8(200))
    assert_equal(image.get_pixel(1, 0).a, UInt8(0))
    assert_equal(image.get_pixel(0, 1).a, UInt8(128))


def test_a_colour_key_makes_one_colour_transparent() raises:
    # tRNS on a truecolour image names a single colour rather than a table.
    var image = decode(rgb_keyed_png())
    assert_equal(image.get_pixel(0, 0).r, UInt8(255))
    assert_equal(image.get_pixel(0, 0).a, UInt8(0))
    assert_equal(image.get_pixel(1, 0).g, UInt8(255))
    assert_equal(image.get_pixel(1, 0).a, UInt8(255))
    assert_equal(image.get_pixel(1, 1).a, UInt8(0))


# --- Refusals ---------------------------------------------------------------


def test_a_file_that_is_not_a_png_is_rejected() raises:
    with assert_raises():
        _ = decode(List[UInt8]())
    var wrong = List[UInt8](length=32, fill=0)
    with assert_raises():
        _ = decode(wrong)


def test_a_corrupt_chunk_is_rejected_rather_than_mis_decoded() raises:
    # A flipped byte in the pixel data would otherwise produce a plausible
    # wrong image, which is far harder to trace than a refusal.
    var damaged = rgba_png()
    damaged[len(damaged) - 12] ^= UInt8(0xFF)
    with assert_raises():
        _ = decode(damaged)


def test_a_truncated_file_is_rejected() raises:
    var whole = rgba_png()
    var cut = List[UInt8]()
    for index in range(len(whole) - 8):  # pragma: no branch
        cut.append(whole[index])
    with assert_raises():
        _ = decode(cut)


def test_an_unsupported_feature_is_refused_by_name() raises:
    # Sixteen bits and interlacing are legal PNG that this decoder does not
    # have. Refusing beats decoding them as something else.
    var deep = rgba_png()
    # Byte 24 is the bit depth, inside IHDR; the CRC must be fixed to match,
    # so instead assert the header check fires at all by corrupting depth and
    # expecting a raise from either the CRC or the depth check.
    deep[24] = UInt8(16)
    with assert_raises():
        _ = decode(deep)


def test_a_zlib_stream_must_be_deflate() raises:
    var bogus: List[UInt8] = [UInt8(0x18), UInt8(0x57)]
    with assert_raises():
        _ = zlib_inflate(bogus)
    var short: List[UInt8] = [UInt8(0x78)]
    with assert_raises():
        _ = zlib_inflate(short)


def test_a_zlib_header_check_is_enforced() raises:
    var bad: List[UInt8] = [UInt8(0x78), UInt8(0x00)]
    with assert_raises():
        _ = zlib_inflate(bad)


def test_a_preset_dictionary_is_refused() raises:
    # FDICT set. There would be no way to supply the dictionary.
    var preset: List[UInt8] = [UInt8(0x78), UInt8(0xBB)]
    with assert_raises():
        _ = zlib_inflate(preset)


def test_the_reserved_block_type_is_refused() raises:
    # BFINAL=1, BTYPE=3 packs to 0b111 in the low bits.
    var reserved: List[UInt8] = [UInt8(0x07)]
    with assert_raises():
        _ = inflate(reserved)


def test_an_over_subscribed_huffman_code_is_refused() raises:
    # Three symbols all one bit long: one bit has room for two codes.
    var lengths: List[Int] = [1, 1, 1]
    with assert_raises():
        _ = Huffman(lengths)


def test_a_truncated_deflate_stream_is_refused() raises:
    with assert_raises():
        _ = inflate(List[UInt8]())


def header_wrong_size_png() -> List[UInt8]:
    """A PNG whose header chunk is twelve bytes instead of thirteen."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(12),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(8),
        UInt8(6),
        UInt8(0),
        UInt8(0),
        UInt8(192),
        UInt8(45),
        UInt8(151),
        UInt8(245),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(96),
        UInt8(100),
        UInt8(98),
        UInt8(254),
        UInt8(15),
        UInt8(0),
        UInt8(1),
        UInt8(20),
        UInt8(1),
        UInt8(6),
        UInt8(9),
        UInt8(231),
        UInt8(180),
        UInt8(85),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def zero_width_png() -> List[UInt8]:
    """A PNG declaring a width of zero."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(8),
        UInt8(6),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(240),
        UInt8(215),
        UInt8(175),
        UInt8(183),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(96),
        UInt8(100),
        UInt8(98),
        UInt8(254),
        UInt8(15),
        UInt8(0),
        UInt8(1),
        UInt8(20),
        UInt8(1),
        UInt8(6),
        UInt8(9),
        UInt8(231),
        UInt8(180),
        UInt8(85),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def deep_png() -> List[UInt8]:
    """A PNG declaring sixteen bits per channel."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(16),
        UInt8(6),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(79),
        UInt8(133),
        UInt8(24),
        UInt8(202),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(96),
        UInt8(100),
        UInt8(98),
        UInt8(254),
        UInt8(15),
        UInt8(0),
        UInt8(1),
        UInt8(20),
        UInt8(1),
        UInt8(6),
        UInt8(9),
        UInt8(231),
        UInt8(180),
        UInt8(85),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def shallow_png() -> List[UInt8]:
    """A PNG declaring four bits per channel: legal, and not supported."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(4),
        UInt8(6),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(218),
        UInt8(229),
        UInt8(41),
        UInt8(136),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(96),
        UInt8(100),
        UInt8(98),
        UInt8(254),
        UInt8(15),
        UInt8(0),
        UInt8(1),
        UInt8(20),
        UInt8(1),
        UInt8(6),
        UInt8(9),
        UInt8(231),
        UInt8(180),
        UInt8(85),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def odd_compression_png() -> List[UInt8]:
    """A PNG declaring a compression method that does not exist."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(8),
        UInt8(6),
        UInt8(1),
        UInt8(0),
        UInt8(0),
        UInt8(30),
        UInt8(215),
        UInt8(174),
        UInt8(190),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(96),
        UInt8(100),
        UInt8(98),
        UInt8(254),
        UInt8(15),
        UInt8(0),
        UInt8(1),
        UInt8(20),
        UInt8(1),
        UInt8(6),
        UInt8(9),
        UInt8(231),
        UInt8(180),
        UInt8(85),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def odd_filter_method_png() -> List[UInt8]:
    """A PNG declaring a filter method that does not exist."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(8),
        UInt8(6),
        UInt8(0),
        UInt8(1),
        UInt8(0),
        UInt8(6),
        UInt8(14),
        UInt8(245),
        UInt8(200),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(96),
        UInt8(100),
        UInt8(98),
        UInt8(254),
        UInt8(15),
        UInt8(0),
        UInt8(1),
        UInt8(20),
        UInt8(1),
        UInt8(6),
        UInt8(9),
        UInt8(231),
        UInt8(180),
        UInt8(85),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def interlaced_png() -> List[UInt8]:
    """An Adam7 interlaced PNG: legal, and not supported."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(8),
        UInt8(6),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(104),
        UInt8(18),
        UInt8(244),
        UInt8(31),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(96),
        UInt8(100),
        UInt8(98),
        UInt8(254),
        UInt8(15),
        UInt8(0),
        UInt8(1),
        UInt8(20),
        UInt8(1),
        UInt8(6),
        UInt8(9),
        UInt8(231),
        UInt8(180),
        UInt8(85),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def odd_colour_type_png() -> List[UInt8]:
    """A PNG declaring a colour type that does not exist."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(8),
        UInt8(5),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(160),
        UInt8(107),
        UInt8(103),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(96),
        UInt8(100),
        UInt8(98),
        UInt8(254),
        UInt8(15),
        UInt8(0),
        UInt8(1),
        UInt8(20),
        UInt8(1),
        UInt8(6),
        UInt8(9),
        UInt8(231),
        UInt8(180),
        UInt8(85),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def palette_without_table_png() -> List[UInt8]:
    """A palette PNG with no PLTE chunk."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(8),
        UInt8(3),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(40),
        UInt8(203),
        UInt8(52),
        UInt8(187),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(10),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(96),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(2),
        UInt8(0),
        UInt8(1),
        UInt8(229),
        UInt8(39),
        UInt8(222),
        UInt8(252),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def palette_index_past_end_png() -> List[UInt8]:
    """A palette PNG naming entry nine of a one-entry palette."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(2),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(8),
        UInt8(3),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(195),
        UInt8(252),
        UInt8(143),
        UInt8(184),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(3),
        UInt8(80),
        UInt8(76),
        UInt8(84),
        UInt8(69),
        UInt8(1),
        UInt8(2),
        UInt8(3),
        UInt8(13),
        UInt8(135),
        UInt8(100),
        UInt8(213),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(11),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(96),
        UInt8(224),
        UInt8(4),
        UInt8(0),
        UInt8(0),
        UInt8(12),
        UInt8(0),
        UInt8(10),
        UInt8(164),
        UInt8(0),
        UInt8(123),
        UInt8(213),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def unknown_row_filter_png() -> List[UInt8]:
    """A PNG whose row declares filter type five."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(8),
        UInt8(6),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(31),
        UInt8(21),
        UInt8(196),
        UInt8(137),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(101),
        UInt8(100),
        UInt8(98),
        UInt8(102),
        UInt8(1),
        UInt8(0),
        UInt8(0),
        UInt8(50),
        UInt8(0),
        UInt8(16),
        UInt8(96),
        UInt8(80),
        UInt8(255),
        UInt8(29),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def short_pixel_data_png() -> List[UInt8]:
    """A PNG whose pixel data is far too small for its declared size."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(4),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(4),
        UInt8(8),
        UInt8(6),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(169),
        UInt8(241),
        UInt8(158),
        UInt8(126),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(11),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(96),
        UInt8(100),
        UInt8(2),
        UInt8(0),
        UInt8(0),
        UInt8(7),
        UInt8(0),
        UInt8(4),
        UInt8(229),
        UInt8(237),
        UInt8(148),
        UInt8(207),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def no_pixel_data_png() -> List[UInt8]:
    """A PNG with a header and an end marker but no IDAT."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(8),
        UInt8(6),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(31),
        UInt8(21),
        UInt8(196),
        UInt8(137),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def no_header_png() -> List[UInt8]:
    """A PNG whose first chunk is not a header."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(156),
        UInt8(99),
        UInt8(96),
        UInt8(100),
        UInt8(98),
        UInt8(254),
        UInt8(15),
        UInt8(0),
        UInt8(1),
        UInt8(20),
        UInt8(1),
        UInt8(6),
        UInt8(214),
        UInt8(185),
        UInt8(166),
        UInt8(69),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def paeth_png() -> List[UInt8]:
    """A 4x2 greyscale PNG, Paeth filtered, chosen so the predictor answers
    with each of its three neighbours: above, above, left, then corner."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(4),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(2),
        UInt8(8),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(90),
        UInt8(195),
        UInt8(34),
        UInt8(191),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(18),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(184),
        UInt8(41),
        UInt8(103),
        UInt8(95),
        UInt8(196),
        UInt8(226),
        UInt8(182),
        UInt8(214),
        UInt8(207),
        UInt8(8),
        UInt8(0),
        UInt8(17),
        UInt8(1),
        UInt8(3),
        UInt8(32),
        UInt8(36),
        UInt8(19),
        UInt8(48),
        UInt8(193),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def backref_before_start() -> List[UInt8]:
    """A DEFLATE stream copying from before the start of its own output."""
    return [
        UInt8(120),
        UInt8(156),
        UInt8(3),
        UInt8(2),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
    ]


def unknown_length_symbol() -> List[UInt8]:
    """A DEFLATE stream naming length symbol 286, which stands for nothing."""
    return [
        UInt8(120),
        UInt8(156),
        UInt8(27),
        UInt8(3),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
    ]


def unknown_distance_symbol() -> List[UInt8]:
    """A DEFLATE stream naming distance symbol 30, which stands for nothing."""
    return [
        UInt8(120),
        UInt8(156),
        UInt8(3),
        UInt8(62),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
    ]


def stored_header_truncated() -> List[UInt8]:
    """A stored block whose length header is cut off."""
    return [
        UInt8(120),
        UInt8(156),
        UInt8(1),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
    ]


def stored_bad_complement() -> List[UInt8]:
    """A stored block whose length and complement disagree."""
    return [
        UInt8(120),
        UInt8(156),
        UInt8(1),
        UInt8(4),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
    ]


def stored_past_end() -> List[UInt8]:
    """A stored block claiming more bytes than the stream holds."""
    return [
        UInt8(120),
        UInt8(156),
        UInt8(1),
        UInt8(16),
        UInt8(0),
        UInt8(239),
        UInt8(255),
        UInt8(97),
        UInt8(98),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
    ]


def reserved_block() -> List[UInt8]:
    """A DEFLATE stream using the reserved block type."""
    return [
        UInt8(120),
        UInt8(156),
        UInt8(7),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
    ]


def repeat_with_nothing() -> List[UInt8]:
    """A dynamic block whose first code length is a repeat of the previous one.
    """
    return [
        UInt8(120),
        UInt8(156),
        UInt8(5),
        UInt8(0),
        UInt8(2),
        UInt8(36),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
    ]


def repeat_past_end() -> List[UInt8]:
    """A dynamic block whose zero-run overshoots the end of its length table."""
    return [
        UInt8(120),
        UInt8(156),
        UInt8(5),
        UInt8(0),
        UInt8(128),
        UInt8(228),
        UInt8(255),
        UInt8(31),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
    ]


# --- Malformed files, each refused by its own check --------------------------
#
# Every fixture below is a real file with correct chunk CRCs, damaged in one
# specific way, so each reaches the check it is aimed at rather than tripping
# an earlier one.


def test_a_header_of_the_wrong_size_is_rejected() raises:
    with assert_raises():
        _ = decode(header_wrong_size_png())


def test_a_zero_dimension_is_rejected() raises:
    with assert_raises():
        _ = decode(zero_width_png())


def test_sixteen_bits_per_channel_is_refused_by_name() raises:
    # Legal PNG this decoder does not have. Refusing beats reading every
    # other byte and producing a plausible half-image.
    with assert_raises():
        _ = decode(deep_png())


def test_a_sub_byte_depth_is_refused() raises:
    with assert_raises():
        _ = decode(shallow_png())


def test_an_unknown_compression_method_is_rejected() raises:
    with assert_raises():
        _ = decode(odd_compression_png())


def test_an_unknown_filter_method_is_rejected() raises:
    with assert_raises():
        _ = decode(odd_filter_method_png())


def test_interlacing_is_refused_by_name() raises:
    with assert_raises():
        _ = decode(interlaced_png())


def test_an_unknown_colour_type_is_rejected() raises:
    with assert_raises():
        _ = decode(odd_colour_type_png())


def test_a_palette_image_without_a_palette_is_rejected() raises:
    with assert_raises():
        _ = decode(palette_without_table_png())


def test_a_palette_index_past_the_palette_is_rejected() raises:
    with assert_raises():
        _ = decode(palette_index_past_end_png())


def test_an_unknown_row_filter_is_rejected() raises:
    with assert_raises():
        _ = decode(unknown_row_filter_png())


def test_pixel_data_of_the_wrong_size_is_rejected() raises:
    with assert_raises():
        _ = decode(short_pixel_data_png())


def test_a_file_with_no_pixel_data_is_rejected() raises:
    with assert_raises():
        _ = decode(no_pixel_data_png())


def test_a_file_with_no_header_is_rejected() raises:
    with assert_raises():
        _ = decode(no_header_png())


def test_the_paeth_predictor_answers_with_each_neighbour() raises:
    # The filter with three outcomes, and the only one where getting the tie
    # order wrong corrupts some images and not others. This row is chosen so
    # the predictor picks above, above, left and then above-left in turn, so
    # every branch is taken by one image.
    var image = decode(paeth_png())
    var want: List[UInt8] = [UInt8(31), UInt8(203), UInt8(25), UInt8(113)]
    for x in range(4):
        assert_equal(image.get_pixel(x, 1).r, want[x])
    var top: List[UInt8] = [UInt8(217), UInt8(30), UInt8(63), UInt8(114)]
    for x in range(4):
        assert_equal(image.get_pixel(x, 0).r, top[x])


# --- Malformed compressed streams -------------------------------------------


def test_a_back_reference_before_the_start_is_rejected() raises:
    with assert_raises():
        _ = zlib_inflate(backref_before_start())


def test_a_length_symbol_that_stands_for_nothing_is_rejected() raises:
    with assert_raises():
        _ = zlib_inflate(unknown_length_symbol())


def test_a_distance_symbol_that_stands_for_nothing_is_rejected() raises:
    # Symbols 30 and 31 exist in the fixed distance alphabet and mean
    # nothing, which is why that alphabet has thirty-two entries here and not
    # thirty: with thirty, this failed as an unmatched code, which says
    # something different and less true.
    with assert_raises():
        _ = zlib_inflate(unknown_distance_symbol())


def test_a_stored_block_with_a_cut_off_header_is_rejected() raises:
    with assert_raises():
        _ = zlib_inflate(stored_header_truncated())


def test_a_stored_block_whose_complement_disagrees_is_rejected() raises:
    # The one integrity check DEFLATE itself carries.
    with assert_raises():
        _ = zlib_inflate(stored_bad_complement())


def test_a_stored_block_claiming_too_much_is_rejected() raises:
    with assert_raises():
        _ = zlib_inflate(stored_past_end())


def test_the_reserved_block_type_is_refused_in_a_stream() raises:
    with assert_raises():
        _ = zlib_inflate(reserved_block())


def test_a_length_repeat_with_nothing_to_repeat_is_rejected() raises:
    with assert_raises():
        _ = zlib_inflate(repeat_with_nothing())


def test_a_length_repeat_past_the_end_of_the_table_is_rejected() raises:
    with assert_raises():
        _ = zlib_inflate(repeat_past_end())


def text_chunk_png() -> List[UInt8]:
    """A valid RGBA PNG carrying a tEXt chunk this decoder has no use for."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(8),
        UInt8(6),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(31),
        UInt8(21),
        UInt8(196),
        UInt8(137),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(10),
        UInt8(116),
        UInt8(69),
        UInt8(88),
        UInt8(116),
        UInt8(67),
        UInt8(111),
        UInt8(109),
        UInt8(109),
        UInt8(101),
        UInt8(110),
        UInt8(116),
        UInt8(0),
        UInt8(104),
        UInt8(105),
        UInt8(162),
        UInt8(162),
        UInt8(88),
        UInt8(102),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(96),
        UInt8(100),
        UInt8(98),
        UInt8(254),
        UInt8(15),
        UInt8(0),
        UInt8(1),
        UInt8(20),
        UInt8(1),
        UInt8(6),
        UInt8(9),
        UInt8(231),
        UInt8(180),
        UInt8(85),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def grey_keyed_png() -> List[UInt8]:
    """A 2x1 greyscale PNG whose darker pixel is keyed transparent."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(2),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(8),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(209),
        UInt8(73),
        UInt8(32),
        UInt8(86),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(2),
        UInt8(116),
        UInt8(82),
        UInt8(78),
        UInt8(83),
        UInt8(0),
        UInt8(40),
        UInt8(67),
        UInt8(38),
        UInt8(101),
        UInt8(194),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(11),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(208),
        UInt8(136),
        UInt8(2),
        UInt8(0),
        UInt8(0),
        UInt8(173),
        UInt8(0),
        UInt8(131),
        UInt8(80),
        UInt8(40),
        UInt8(64),
        UInt8(62),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def zero_height_png() -> List[UInt8]:
    """A PNG declaring a height of zero."""
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(8),
        UInt8(6),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(212),
        UInt8(73),
        UInt8(23),
        UInt8(44),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(96),
        UInt8(100),
        UInt8(98),
        UInt8(254),
        UInt8(15),
        UInt8(0),
        UInt8(1),
        UInt8(20),
        UInt8(1),
        UInt8(6),
        UInt8(9),
        UInt8(231),
        UInt8(180),
        UInt8(85),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def paeth_corner_png() -> List[UInt8]:
    """A 2x2 greyscale PNG whose Paeth row needs the above-left neighbour: left 0, above 10, above-left 5.
    """
    return [
        UInt8(137),
        UInt8(80),
        UInt8(78),
        UInt8(71),
        UInt8(13),
        UInt8(10),
        UInt8(26),
        UInt8(10),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(13),
        UInt8(73),
        UInt8(72),
        UInt8(68),
        UInt8(82),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(2),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(2),
        UInt8(8),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(87),
        UInt8(221),
        UInt8(82),
        UInt8(248),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(14),
        UInt8(73),
        UInt8(68),
        UInt8(65),
        UInt8(84),
        UInt8(120),
        UInt8(218),
        UInt8(99),
        UInt8(96),
        UInt8(229),
        UInt8(98),
        UInt8(249),
        UInt8(253),
        UInt8(27),
        UInt8(0),
        UInt8(3),
        UInt8(68),
        UInt8(2),
        UInt8(10),
        UInt8(82),
        UInt8(190),
        UInt8(58),
        UInt8(107),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(73),
        UInt8(69),
        UInt8(78),
        UInt8(68),
        UInt8(174),
        UInt8(66),
        UInt8(96),
        UInt8(130),
    ]


def two_stored_blocks() -> List[UInt8]:
    """Two stored blocks, the first not final: the loop must continue past it.
    """
    return [
        UInt8(120),
        UInt8(156),
        UInt8(0),
        UInt8(1),
        UInt8(0),
        UInt8(254),
        UInt8(255),
        UInt8(65),
        UInt8(1),
        UInt8(1),
        UInt8(0),
        UInt8(254),
        UInt8(255),
        UInt8(66),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
    ]


def dynamic_with_repeat() -> List[UInt8]:
    """A dynamic block whose header uses code-length symbol 16 to repeat a length. Expands to three zero bytes.
    """
    return [
        UInt8(120),
        UInt8(156),
        UInt8(5),
        UInt8(195),
        UInt8(5),
        UInt8(1),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(128),
        UInt8(32),
        UInt8(254),
        UInt8(175),
        UInt8(198),
        UInt8(64),
        UInt8(0),
        UInt8(0),
        UInt8(0),
        UInt8(1),
    ]


def test_a_chunk_this_decoder_does_not_know_is_skipped() raises:
    # tEXt and friends are legal and carry nothing this renderer needs. An
    # unknown chunk must be stepped over by its length, not guessed at.
    var image = decode(text_chunk_png())
    assert_equal(image.get_pixel(0, 0).r, UInt8(1))


def test_a_greyscale_colour_key_is_honoured() raises:
    var image = decode(grey_keyed_png())
    assert_equal(image.get_pixel(0, 0).r, UInt8(40))
    assert_equal(image.get_pixel(0, 0).a, UInt8(0))
    assert_equal(image.get_pixel(1, 0).a, UInt8(255))


def test_a_zero_height_is_rejected() raises:
    # Each operand of the dimension check has to be able to decide alone.
    with assert_raises():
        _ = decode(zero_height_png())


def test_the_paeth_predictor_can_answer_with_the_corner() raises:
    # Left 0, above 10, above-left 5: the estimate is 5, which is nearer the
    # corner than either of the other two. The third branch, and the one a
    # gradient never reaches.
    var image = decode(paeth_corner_png())
    assert_equal(image.get_pixel(0, 1).r, UInt8(0))
    assert_equal(image.get_pixel(1, 1).r, UInt8(0))


def test_a_stream_continues_past_a_block_that_is_not_the_last() raises:
    var bytes = zlib_inflate(two_stored_blocks())
    assert_equal(len(bytes), 2)
    assert_equal(bytes[0], UInt8(65))
    assert_equal(bytes[1], UInt8(66))


def test_a_length_can_be_repeated_by_code_length_symbol_sixteen() raises:
    # The success case of the repeat whose failure is tested above.
    var bytes = zlib_inflate(dynamic_with_repeat())
    assert_equal(len(bytes), 3)
    assert_equal(bytes[0], UInt8(0))


def test_a_stored_block_header_cut_off_by_the_stream_end_is_rejected() raises:
    # Straight to `inflate`, with no zlib wrapper: the four trailing checksum
    # bytes of a wrapped stream would otherwise be read as the header, and
    # this would fail later and for a different reason.
    var only_a_header: List[UInt8] = [UInt8(0x01)]
    with assert_raises():
        _ = inflate(only_a_header)


def test_a_zlib_method_other_than_deflate_is_rejected() raises:
    # Method 9 rather than 8. The earlier fixture had method 8 with a broken
    # header check, so it was refused for a different reason than its name.
    var method_nine: List[UInt8] = [UInt8(0x19), UInt8(0x8D)]
    with assert_raises():
        _ = zlib_inflate(method_nine)


def test_bits_are_read_low_to_high_and_align_stops_at_a_boundary() raises:
    # `align` is a no-op when the reader already sits on a byte boundary, and
    # a stored block reached from a compressed one can arrive either way.
    var bytes: List[UInt8] = [UInt8(0b10110101), UInt8(0xFF)]
    var reader = BitReader(bytes, 0)
    assert_equal(reader.read_bits(3), 5)
    reader.align()
    assert_equal(reader.position, 1)
    # Already aligned: this must not skip a byte.
    reader.align()
    assert_equal(reader.position, 1)
    assert_equal(reader.read_bits(8), 255)


def test_an_incomplete_huffman_code_refuses_bits_it_cannot_match() raises:
    # One symbol two bits long leaves three of the four two-bit codes unused.
    # Reading one of those matches nothing, which is a corrupt stream rather
    # than a symbol.
    var lengths: List[Int] = [2]
    var code = Huffman(lengths)
    var ones: List[UInt8] = [UInt8(0xFF), UInt8(0xFF), UInt8(0xFF)]
    var reader = BitReader(ones, 0)
    with assert_raises():
        _ = code.decode(reader)


def test_a_decoded_image_becomes_a_texture() raises:
    # The join the whole decoder exists for. No conversion: both sides already
    # hold eight-bit RGBA rows from the top, which is why decoding widens
    # every colour type rather than carrying five shapes into the renderer.
    var image = decode(rgba_png())
    var skin = texture_from(image, REPEAT, NEAREST, SRGB, True)
    assert_equal(skin.width, 4)
    assert_equal(skin.height, 4)
    # 4 -> 2 -> 1 is three levels.
    assert_equal(skin.levels, 3)
    assert_equal(skin.texel(2, 0).r, UInt8(120))
    assert_equal(skin.texel(1, 0).a, UInt8(128))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
