# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.jpeg`.

The files under `assets/jpeg/` were written by PIL, libjpeg behind it, and
each `_ref.png` beside one is what libjpeg decoded it to. The decoder here
uses the float inverse transform and the standard's triangle filter where
libjpeg uses integer approximations of both, so the two agree to within two
levels and never to the bit; the comparisons below say so. The refusals
are made by patching one byte of a good file, or by assembling a small
gray file by hand.
"""

from render.framebuffer import Color
from render.jpeg import (
    BLOCK_SAMPLES,
    BitReader,
    HuffmanTable,
    clamp_sample,
    cosine_table,
    decode,
    inverse_dct,
    receive_extend,
    upsampled,
    ycbcr_to_rgb,
    zigzag_order,
)
from render.png import DecodedImage
from render.png import decode as decode_png
from render.srgb import SRGB
from render.texture import BILINEAR, REPEAT, texture_from
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def fixture(name: String) raises -> List[UInt8]:
    """Return one of the files under assets/jpeg/."""
    return Path("assets/jpeg/" + name).read_bytes()


def segment(bytes: List[UInt8], marker: UInt8, nth: Int = 0) raises -> Int:
    """Return where the `nth` segment with `marker` begins: the offset of
    its 0xFF byte. Walks the segments as the decoder does, so a test can
    patch a field by its offset within the segment."""
    var at = 2
    var passed = 0
    while at + 3 < len(bytes):
        if bytes[at + 1] == marker:
            if passed == nth:
                return at
            passed += 1
        var length = (Int(bytes[at + 2]) << 8) | Int(bytes[at + 3])
        at += 2 + length
    raise Error("No such segment in the fixture")


def patched(bytes: List[UInt8], at: Int, value: Int) -> List[UInt8]:
    """Return a copy of `bytes` with one byte replaced."""
    var copy = bytes.copy()
    copy[at] = UInt8(value)
    return copy^


def without(
    bytes: List[UInt8], marker: UInt8, nth: Int = 0
) raises -> List[UInt8]:
    """Return a copy of `bytes` with the `nth` segment of `marker` cut out."""
    var at = segment(bytes, marker, nth)
    var length = (Int(bytes[at + 2]) << 8) | Int(bytes[at + 3])
    var copy = List[UInt8]()
    for index in range(len(bytes)):
        if index < at or index >= at + 2 + length:
            copy.append(bytes[index])
    return copy^


def spliced(bytes: List[UInt8], at: Int, insert: List[UInt8]) -> List[UInt8]:
    """Return a copy of `bytes` with `insert` placed before offset `at`."""
    var copy = List[UInt8]()
    for index in range(at):
        copy.append(bytes[index])
    for index in range(len(insert)):
        copy.append(insert[index])
    for index in range(at, len(bytes)):
        copy.append(bytes[index])
    return copy^


def cut(bytes: List[UInt8], length: Int) -> List[UInt8]:
    """Return the first `length` bytes."""
    var copy = List[UInt8]()
    for index in range(length):
        copy.append(bytes[index])
    return copy^


def refused(bytes: List[UInt8]) raises:
    """Assert the decoder refuses `bytes`."""
    with assert_raises():
        _ = decode(bytes)


def worst_difference(
    image: DecodedImage, reference: DecodedImage
) raises -> Int:
    """Return the largest difference in any color channel of any pixel."""
    assert_equal(image.width, reference.width)
    assert_equal(image.height, reference.height)
    var worst = 0
    for y in range(image.height):
        for x in range(image.width):
            var a = image.get_pixel(x, y)
            var b = reference.get_pixel(x, y)
            assert_equal(a.a, UInt8(255))
            for pair in [
                (Int(a.r), Int(b.r)),
                (Int(a.g), Int(b.g)),
                (Int(a.b), Int(b.b)),
            ]:
                var apart = pair[0] - pair[1]
                if apart < 0:
                    apart = -apart
                if apart > worst:
                    worst = apart
    return worst


def push_segment(mut out: List[UInt8], marker: Int, payload: List[Int]):
    """Append a marker segment holding `payload`."""
    out.append(0xFF)
    out.append(UInt8(marker))
    var length = len(payload) + 2
    out.append(UInt8(length >> 8))
    out.append(UInt8(length & 0xFF))
    for value in payload:
        out.append(UInt8(value))


def huffman_payload(
    kind: Int, counts: List[Int], symbols: List[Int]
) -> List[Int]:
    """Return a DHT payload: one table of `kind` with id zero."""
    var payload = List[Int]()
    payload.append(kind << 4)
    for length in range(16):
        var count = 0
        if length < len(counts):
            count = counts[length]
        payload.append(count)
    for symbol in symbols:
        payload.append(symbol)
    return payload^


def gray_jpeg(
    width: Int,
    height: Int,
    dc_symbols: List[Int],
    ac_symbols: List[Int],
    data: List[Int],
    restart_interval: Int = 0,
    end: Bool = True,
) -> List[UInt8]:
    """Assemble a gray baseline JPEG by hand.

    Every quantization step is one. The DC and AC tables each hold their
    symbols at one-bit codes, so a table of one symbol reads it at `0`
    and a table of two reads them at `0` and `1`. `data` is the scan's
    bytes as they stand, markers included, and `end` says whether the
    end marker follows.
    """
    var out = List[UInt8]()
    out.append(0xFF)
    out.append(0xD8)
    var quant = List[Int]()
    quant.append(0)
    for _ in range(BLOCK_SAMPLES):
        quant.append(1)
    push_segment(out, 0xDB, quant)
    if restart_interval > 0:
        push_segment(
            out, 0xDD, [restart_interval >> 8, restart_interval & 0xFF]
        )
    push_segment(
        out,
        0xC0,
        [
            8,
            height >> 8,
            height & 0xFF,
            width >> 8,
            width & 0xFF,
            1,
            1,
            0x11,
            0,
        ],
    )
    push_segment(out, 0xC4, huffman_payload(0, [len(dc_symbols)], dc_symbols))
    push_segment(out, 0xC4, huffman_payload(1, [len(ac_symbols)], ac_symbols))
    push_segment(out, 0xDA, [1, 1, 0x00, 0, 63, 0])
    for value in data:
        out.append(UInt8(value))
    if end:
        out.append(0xFF)
        out.append(0xD9)
    return out^


# --- the arithmetic ---------------------------------------------------------


def test_the_zigzag_visits_every_position_once() raises:
    var order = zigzag_order()
    assert_equal(len(order), BLOCK_SAMPLES)
    var seen = List[Bool](length=BLOCK_SAMPLES, fill=False)
    for index in range(BLOCK_SAMPLES):
        assert_false(seen[order[index]])
        seen[order[index]] = True
    # The standard's first row: along, down, and back up the diagonal.
    assert_equal(order[1], 1)
    assert_equal(order[2], 8)
    assert_equal(order[3], 16)
    assert_equal(order[63], 63)


def test_a_dc_only_block_is_flat_at_an_eighth_of_its_coefficient() raises:
    # Both passes scale the zero frequency by a half over root two, so a
    # DC coefficient of eight raises every sample by one.
    var cosines = cosine_table()
    assert_equal(len(cosines), BLOCK_SAMPLES)
    var coefficients = List[Float32](length=BLOCK_SAMPLES, fill=0)
    coefficients[0] = 8
    var samples = inverse_dct(coefficients, cosines)
    for index in range(BLOCK_SAMPLES):
        assert_almost_equal(samples[index], Float32(129), atol=1e-4)
    # A first horizontal frequency makes the left brighter than the right.
    coefficients[0] = 0
    coefficients[1] = 8
    var ramp = inverse_dct(coefficients, cosines)
    assert_true(ramp[0] > ramp[7], "the cosine did not fall across the row")
    assert_almost_equal(ramp[0] + ramp[7], Float32(256), atol=1e-4)


def test_a_sample_is_rounded_and_clamped() raises:
    assert_equal(clamp_sample(0.49), UInt8(0))
    assert_equal(clamp_sample(0.5), UInt8(1))
    assert_equal(clamp_sample(127.6), UInt8(128))
    assert_equal(clamp_sample(-3), UInt8(0))
    assert_equal(clamp_sample(300), UInt8(255))


def test_neutral_chroma_is_gray_and_the_extremes_clamp() raises:
    var gray = ycbcr_to_rgb(90, 128, 128)
    assert_equal(gray.r, UInt8(90))
    assert_equal(gray.g, UInt8(90))
    assert_equal(gray.b, UInt8(90))
    assert_equal(gray.a, UInt8(255))
    var red = ycbcr_to_rgb(128, 128, 255)
    assert_equal(red.r, UInt8(255))
    assert_true(red.g < 60, "a full red difference left green bright")
    var blue = ycbcr_to_rgb(128, 255, 128)
    assert_equal(blue.b, UInt8(255))
    var black = ycbcr_to_rgb(0, 0, 0)
    assert_equal(black.r, UInt8(0))
    assert_equal(black.b, UInt8(0))


def test_a_leading_zero_bit_means_a_negative_coefficient() raises:
    assert_equal(receive_extend(1, 1), 1)
    assert_equal(receive_extend(0, 1), -1)
    assert_equal(receive_extend(16, 5), 16)
    assert_equal(receive_extend(15, 5), -16)
    assert_equal(receive_extend(0, 5), -31)


def test_upsampling_reads_full_resolution_as_it_is_and_halves_by_thirds() raises:
    # A four-by-two plane of two rows: read whole, each sample is its
    # own; read at twice the width, the pixel nearer a sample takes three
    # quarters of it, and the edge repeats.
    var plane: List[UInt8] = [0, 100, 200, 40, 10, 110, 210, 50]
    assert_equal(upsampled(plane, 4, 2, 1, 1, 1), UInt8(210))
    assert_equal(upsampled(plane, 4, 0, 0, 2, 1), UInt8(0))
    assert_equal(upsampled(plane, 4, 1, 0, 2, 1), UInt8(25))
    assert_equal(upsampled(plane, 4, 2, 0, 2, 1), UInt8(75))
    assert_equal(upsampled(plane, 4, 3, 0, 2, 1), UInt8(125))
    # Down as well: the top edge repeats, and the second row leans down.
    assert_equal(upsampled(plane, 4, 0, 0, 1, 2), UInt8(0))
    assert_equal(upsampled(plane, 4, 1, 1, 1, 2), UInt8(103))
    assert_equal(upsampled(plane, 4, 1, 2, 1, 2), UInt8(108))
    # Both ways at once.
    assert_equal(upsampled(plane, 4, 0, 0, 2, 2), UInt8(0))
    assert_equal(upsampled(plane, 4, 1, 1, 2, 2), UInt8(28))


def test_a_huffman_table_is_checked_as_it_is_built() raises:
    with assert_raises():
        _ = HuffmanTable([1, 0, 0], [UInt8(0)])
    var counts = List[Int](length=16, fill=0)
    counts[0] = 1
    with assert_raises():
        _ = HuffmanTable(counts, [UInt8(0), UInt8(1)])
    var crowded = List[Int](length=16, fill=0)
    crowded[0] = 3
    with assert_raises():
        _ = HuffmanTable(crowded, [UInt8(0), UInt8(1), UInt8(2)])
    var table = HuffmanTable(counts, [UInt8(7)])
    assert_true(table.defined)
    assert_false(HuffmanTable().defined)
    # One code of one bit: `0` is the symbol and `1` is nothing at all.
    var reader = BitReader([UInt8(0x00)], 0)
    assert_equal(reader.decode(table), UInt8(7))
    var wrong = BitReader(
        [UInt8(0xFF), UInt8(0x00), UInt8(0xFF), UInt8(0x00)], 0
    )
    with assert_raises():
        _ = wrong.decode(table)


# --- files libjpeg wrote ----------------------------------------------------


def test_a_solid_file_decodes_to_its_color() raises:
    # Eight by eight of one color at quality one hundred: every block is
    # a DC coefficient alone, and libjpeg reads the same bytes back.
    var image = decode(fixture("solid.jpg"))
    assert_equal(image.width, 8)
    assert_equal(image.height, 8)
    assert_equal(image.color_space, SRGB)
    for y in range(8):
        for x in range(8):
            var seen = image.get_pixel(x, y)
            assert_equal(seen.r, UInt8(199))
            assert_equal(seen.g, UInt8(60))
            assert_equal(seen.b, UInt8(29))
            assert_equal(seen.a, UInt8(255))


def test_a_full_resolution_gradient_matches_libjpeg_to_a_level() raises:
    var image = decode(fixture("gradient444.jpg"))
    var reference = decode_png(fixture("gradient444_ref.png"))
    assert_true(worst_difference(image, reference) <= 1, "further than a level")
    # And it really is a gradient: red rises across, green down.
    assert_true(image.get_pixel(23, 0).r > image.get_pixel(0, 0).r + 200)
    assert_true(image.get_pixel(0, 15).g > image.get_pixel(0, 0).g + 200)


def test_a_subsampled_odd_sized_gradient_matches_to_two_levels() raises:
    # Twenty-one by thirteen with the chroma at half the luma's size: the
    # image is not whole blocks each way, the chroma is read through the
    # triangle filter, and libjpeg's fancy upsampling agrees to two levels.
    var image = decode(fixture("gradient420.jpg"))
    assert_equal(image.width, 21)
    assert_equal(image.height, 13)
    var reference = decode_png(fixture("gradient420_ref.png"))
    assert_true(
        worst_difference(image, reference) <= 2, "further than two levels"
    )


def test_a_gray_file_decodes_to_equal_channels() raises:
    var image = decode(fixture("gray.jpg"))
    var reference = decode_png(fixture("gray_ref.png"))
    assert_equal(worst_difference(image, reference), 0)
    for x in range(16):
        var seen = image.get_pixel(x, 3)
        assert_equal(seen.r, seen.g)
        assert_equal(seen.g, seen.b)
    assert_true(image.get_pixel(15, 0).r > image.get_pixel(0, 0).r + 200)


def test_restart_markers_are_followed_and_the_predictors_reset() raises:
    var image = decode(fixture("restart.jpg"))
    var reference = decode_png(fixture("restart_ref.png"))
    assert_true(
        worst_difference(image, reference) <= 2, "further than two levels"
    )


def test_a_decoded_file_becomes_a_texture() raises:
    var image = decode(fixture("gradient444.jpg"))
    var skin = texture_from(image, REPEAT, BILINEAR)
    assert_equal(skin.width, 24)
    assert_equal(skin.height, 16)
    assert_equal(skin.color_space, SRGB)


def test_progressive_and_cmyk_files_are_refused_by_name() raises:
    with assert_raises(contains="baseline"):
        _ = decode(fixture("progressive.jpg"))
    with assert_raises(contains="CMYK"):
        _ = decode(fixture("cmyk.jpg"))


# --- files assembled by hand ------------------------------------------------


def test_a_hand_made_gray_block_decodes_its_dc_coefficient() raises:
    # The DC table reads a size of five at `0`, and the AC table reads
    # end-of-block at `0`. Five bits of `10000` are sixteen, which lifts
    # the block by two levels; `01111` is minus sixteen.
    var lifted = decode(gray_jpeg(8, 8, [5], [0x00], [0x40]))
    assert_equal(lifted.get_pixel(0, 0).r, UInt8(130))
    assert_equal(lifted.get_pixel(7, 7).b, UInt8(130))
    var lowered = decode(gray_jpeg(8, 8, [5], [0x00], [0x3C]))
    assert_equal(lowered.get_pixel(3, 3).g, UInt8(126))
    # A size of zero carries no bits: the block is flat at the middle.
    var flat = decode(gray_jpeg(8, 8, [0], [0x00], [0x00]))
    assert_equal(flat.get_pixel(4, 4).r, UInt8(128))
    # Two blocks across, the second predicted from the first, and a
    # stuffed zero after the 0xFF the bits make: a size of eight read at
    # `1`, then eight ones, is 255 in the first block and 510 in the next.
    var pair = decode(
        gray_jpeg(16, 8, [0, 8], [0x00], [0xFF, 0x00, 0xBF, 0xEF])
    )
    assert_equal(pair.get_pixel(0, 0).r, UInt8(160))
    assert_equal(pair.get_pixel(15, 0).r, UInt8(192))


def test_a_run_past_the_block_is_refused() raises:
    # The AC table reads a run of sixteen zeros at `0` and a run of
    # fifteen with a one-bit value at `1`: three runs of sixteen reach
    # forty-nine, and fifteen more reach sixty-four.
    refused(gray_jpeg(8, 8, [0], [0xF0, 0xF1], [0x08]))
    # Three runs of sixteen and an end-of-block is fine, and so are four
    # runs of sixteen, which reach the end without one.
    var image = decode(gray_jpeg(8, 8, [0], [0xF0, 0x00], [0x08]))
    assert_equal(image.get_pixel(0, 0).r, UInt8(128))
    var run_out = decode(gray_jpeg(8, 8, [0], [0xF0, 0x00], [0x00]))
    assert_equal(run_out.get_pixel(7, 7).r, UInt8(128))
    # A table with no symbols at all is a table, and decodes nothing.
    refused(gray_jpeg(8, 8, [], [0x00], [0x00]))


def test_a_scan_that_ends_early_is_refused() raises:
    # No data before the end marker; no data and no end marker; a 0xFF
    # as the last byte; and a marker other than a stuffed zero after one.
    refused(gray_jpeg(8, 8, [5], [0x00], []))
    refused(gray_jpeg(8, 8, [5], [0x00], [], end=False))
    refused(gray_jpeg(8, 8, [5], [0x00], [0xFF], end=False))
    refused(gray_jpeg(8, 8, [5], [0x00], [0x40, 0xFF, 0xD8, 0x00]))
    # A code the table does not define: sixteen ones.
    refused(gray_jpeg(8, 8, [5], [0x00], [0xFF, 0x00, 0xFF, 0x00]))


def test_the_end_marker_must_close_the_file() raises:
    # Data then nothing; data then a byte that is no marker; the wrong
    # marker; and bytes after the end marker.
    refused(gray_jpeg(8, 8, [5], [0x00], [0x40], end=False))
    refused(gray_jpeg(8, 8, [5], [0x00], [0x40, 0x12]))
    refused(gray_jpeg(8, 8, [5], [0x00], [0x40, 0xFF, 0xD8], end=False))
    var whole = gray_jpeg(8, 8, [5], [0x00], [0x40])
    whole.append(0)
    refused(whole)


def test_restart_intervals_by_hand_wrap_and_must_be_kept() raises:
    # Nine blocks across with an interval of one: eight markers, RST0
    # through RST7, and the ninth block needs none after it.
    var data = List[Int]()
    for index in range(9):
        if index > 0:
            data.append(0xFF)
            data.append(0xD0 + (index - 1) % 8)
        data.append(0x40)
    var image = decode(gray_jpeg(72, 8, [5], [0x00], data, restart_interval=1))
    assert_equal(image.get_pixel(70, 5).r, UInt8(130))
    # The marker missing, out of order, or the file ending before it.
    refused(gray_jpeg(16, 8, [5], [0x00], [0x40, 0x40], restart_interval=1))
    refused(
        gray_jpeg(
            16, 8, [5], [0x00], [0x40, 0xFF, 0xD1, 0x40], restart_interval=1
        )
    )
    refused(
        gray_jpeg(16, 8, [5], [0x00], [0x40], restart_interval=1, end=False)
    )
    # A restart interval segment holds one number and nothing else.
    var long = gray_jpeg(8, 8, [5], [0x00], [0x40], restart_interval=1)
    var at = segment(long, 0xDD)
    refused(spliced(patched(long, at + 3, 5), at + 4, [UInt8(0)]))


def test_fill_bytes_and_comments_are_passed_over() raises:
    var plain = gray_jpeg(8, 8, [5], [0x00], [0x40])
    var at = segment(plain, 0xC0)
    var filled = spliced(plain, at, [UInt8(0xFF)])
    assert_equal(decode(filled).get_pixel(0, 0).r, UInt8(130))
    var commented = spliced(
        plain, at, [UInt8(0xFF), UInt8(0xFE), 0, 4, 72, 105]
    )
    assert_equal(decode(commented).get_pixel(0, 0).r, UInt8(130))


# --- structure, one byte at a time ------------------------------------------


def test_a_file_that_is_not_a_jpeg_is_refused() raises:
    refused(List[UInt8]())
    refused(cut(fixture("gradient444_ref.png"), 64))
    refused([UInt8(0xFF), UInt8(0xDB), UInt8(0), UInt8(0)])
    # Ended right after a marker, before its length; ended after one
    # segment, before the scan; a byte that is no marker where one is
    # due; a marker where a segment is due.
    var whole = fixture("gradient444.jpg")
    refused([UInt8(0xFF), UInt8(0xD8), UInt8(0xFF), UInt8(0xDB)])
    refused(cut(whole, segment(whole, 0xDB)))
    var quant = segment(whole, 0xDB)
    refused(patched(whole, quant, 0x00))
    for marker in [0xD8, 0xD3, 0xD9]:
        refused(patched(whole, quant + 1, marker))
    # An unknown marker: arithmetic coding, and a reserved one past the
    # application segments.
    var frame = segment(whole, 0xC0)
    refused(patched(whole, frame + 1, 0xC9))
    refused(patched(whole, frame + 1, 0xF0))
    # A segment length below two, or past the end of the file.
    refused(patched(patched(whole, quant + 2, 0), quant + 3, 1))
    refused(patched(patched(whole, quant + 2, 0xFF), quant + 3, 0xFF))


def test_a_frame_header_is_checked_field_by_field() raises:
    var whole = fixture("gradient444.jpg")
    var frame = segment(whole, 0xC0)
    # Extended sequential Huffman coding at eight bits is baseline with
    # another name, and decodes.
    var extended = decode(patched(whole, frame + 1, 0xC1))
    assert_equal(extended.width, 24)
    # Length 7 leaves no room for the size; twelve bits a sample; a
    # height or width of zero; too many pixels; two components; four.
    refused(patched(patched(whole, frame + 2, 0), frame + 3, 7))
    refused(patched(whole, frame + 4, 12))
    refused(patched(patched(whole, frame + 5, 0), frame + 6, 0))
    refused(patched(patched(whole, frame + 7, 0), frame + 8, 0))
    var huge = patched(patched(whole, frame + 5, 0xFF), frame + 6, 0xFF)
    refused(patched(patched(huge, frame + 7, 0xFF), frame + 8, 0xFF))
    refused(patched(whole, frame + 9, 2))
    # A component count the length does not match.
    var gray = fixture("gray.jpg")
    var gray_frame = segment(gray, 0xC0)
    refused(patched(gray, gray_frame + 9, 3))
    # A sampling factor of zero or three, each way.
    for factors in [0x01, 0x10, 0x31, 0x13]:
        refused(patched(whole, frame + 11, factors))
    # A quantization table id past three, and two components sharing an id.
    refused(patched(whole, frame + 12, 4))
    refused(patched(whole, frame + 13, Int(whole[frame + 10])))
    # A second frame header, and none at all.
    var length = (Int(whole[frame + 2]) << 8) | Int(whole[frame + 3])
    var copy = List[UInt8]()
    for index in range(frame, frame + 2 + length):
        copy.append(whole[index])
    refused(spliced(whole, frame, copy))
    refused(without(whole, 0xC0))


def test_a_scan_header_is_checked_field_by_field() raises:
    var whole = fixture("gradient444.jpg")
    var scan = segment(whole, 0xDA)
    # Length 2 holds nothing; one component of three; a length off by
    # one; a Huffman table id past three, DC and AC; a component the
    # frame lacks; a spectral end other than sixty-three.
    refused(patched(patched(whole, scan + 2, 0), scan + 3, 2))
    refused(patched(whole, scan + 4, 1))
    refused(patched(whole, scan + 3, Int(whole[scan + 3]) + 1))
    refused(patched(whole, scan + 6, 0x40))
    refused(patched(whole, scan + 6, 0x04))
    refused(patched(whole, scan + 5, 9))
    refused(patched(whole, scan + 11, 1))
    refused(patched(whole, scan + 12, 0))
    refused(patched(whole, scan + 13, 1))
    # A scan whose tables were never defined: the quantization tables,
    # the DC table, the AC table.
    refused(without(without(whole, 0xDB), 0xDB))
    refused(without(whole, 0xC4))
    refused(without(whole, 0xC4, 1))


def test_a_table_segment_is_checked_field_by_field() raises:
    var whole = fixture("gradient444.jpg")
    var quant = segment(whole, 0xDB)
    # A sixteen-bit table; an id past three; a table cut short.
    refused(patched(whole, quant + 4, 0x10))
    refused(patched(whole, quant + 4, 0x04))
    refused(patched(patched(whole, quant + 2, 0), quant + 3, 4))
    var huffman = segment(whole, 0xC4)
    # A class past one; an id past three; a segment too short for the
    # counts; counts the symbols do not fill; more codes of one bit than
    # one bit can hold.
    refused(patched(whole, huffman + 4, 0x20))
    refused(patched(whole, huffman + 4, 0x04))
    refused(patched(patched(whole, huffman + 2, 0), huffman + 3, 3))
    refused(patched(whole, huffman + 6, Int(whole[huffman + 6]) + 1))
    var crowded = patched(patched(whole, huffman + 5, 3), huffman + 6, 3)
    refused(patched(crowded, huffman + 7, 0))
    # A truncated scan.
    var scan = segment(whole, 0xDA)
    refused(cut(whole, scan + 40))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
