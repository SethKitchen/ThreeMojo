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
    assert_equal(upsampled(plane, 4, 4, 2, 2, 1, 1, 1), UInt8(210))
    assert_equal(upsampled(plane, 4, 4, 2, 0, 0, 2, 1), UInt8(0))
    assert_equal(upsampled(plane, 4, 4, 2, 1, 0, 2, 1), UInt8(25))
    assert_equal(upsampled(plane, 4, 4, 2, 2, 0, 2, 1), UInt8(75))
    assert_equal(upsampled(plane, 4, 4, 2, 3, 0, 2, 1), UInt8(125))
    # Down as well: the top edge repeats, and the second row leans down.
    assert_equal(upsampled(plane, 4, 4, 2, 0, 0, 1, 2), UInt8(0))
    assert_equal(upsampled(plane, 4, 4, 2, 1, 1, 1, 2), UInt8(103))
    assert_equal(upsampled(plane, 4, 4, 2, 1, 2, 1, 2), UInt8(108))
    # Both ways at once.
    assert_equal(upsampled(plane, 4, 4, 2, 0, 0, 2, 2), UInt8(0))
    assert_equal(upsampled(plane, 4, 4, 2, 1, 1, 2, 2), UInt8(28))
    # The far corner of an image that is whole units across and down
    # leans past the plane's last sample, and reads the edge again.
    assert_equal(upsampled(plane, 4, 4, 2, 7, 3, 2, 2), UInt8(50))
    assert_equal(upsampled(plane, 4, 4, 2, 7, 0, 2, 1), UInt8(40))
    # A component three samples wide in a plane of four: the fourth is
    # padding, and the edge repeats the third rather than read it. The
    # same holds for a component one row tall in a plane of two.
    assert_equal(upsampled(plane, 4, 3, 2, 5, 0, 2, 1), UInt8(200))
    assert_equal(upsampled(plane, 4, 4, 1, 0, 1, 1, 2), UInt8(0))


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


def test_a_cmyk_file_is_refused_by_name() raises:
    with assert_raises(contains="CMYK"):
        _ = decode(fixture("cmyk.jpg"))


# --- progressive files libjpeg wrote ----------------------------------------


def test_a_progressive_file_decodes_to_what_its_baseline_twin_does() raises:
    # PIL saved each picture twice at one quality, once baseline and once
    # progressive. The quantized coefficients are the same, sent in one
    # scan or in ten, so the two decode to the very same samples.
    for name in ["prog420", "prog444", "prog422", "proggray", "progrestart"]:
        var progressive = decode(fixture(name + ".jpg"))
        var baseline = decode(fixture(name + "_baseline.jpg"))
        assert_equal(worst_difference(progressive, baseline), 0)
        assert_equal(progressive.color_space, SRGB)
    var odd = decode(fixture("prog420.jpg"))
    assert_equal(odd.width, 21)
    assert_equal(odd.height, 13)


def test_a_progressive_file_matches_libjpeg_to_two_levels() raises:
    # Spectral selection, successive approximation and end-of-band runs.
    for name in ["prog420", "proggray", "progressive"]:
        var image = decode(fixture(name + ".jpg"))
        var reference = decode_png(fixture(name + "_ref.png"))
        assert_true(
            worst_difference(image, reference) <= 2, "further than two levels"
        )
    # A restart marker after every unit of every scan, in a checkered
    # picture whose sharp chroma edges put one pixel of the upsampled
    # result at three levels: libjpeg rounds its integer filter where
    # this one rounds once, at the end.
    var restarted = decode(fixture("progrestart.jpg"))
    var reference = decode_png(fixture("progrestart_ref.png"))
    assert_true(
        worst_difference(restarted, reference) <= 3, "further than three"
    )


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


def test_components_are_known_by_their_ids_and_not_their_order() raises:
    # The frame lists the blue difference first and the luma second. The
    # scan still names the luma first, and the blocks arrive in the
    # scan's order, so the picture is the same one: the ids say which
    # plane is which, not the frame's order.
    var whole = fixture("gradient444.jpg")
    var reference = decode(whole)
    var frame = segment(whole, 0xC0)
    var swapped_frame = whole.copy()
    for offset in range(3):
        swapped_frame[frame + 10 + offset] = whole[frame + 13 + offset]
        swapped_frame[frame + 13 + offset] = whole[frame + 10 + offset]
    assert_equal(worst_difference(decode(swapped_frame), reference), 0)
    # Three components numbered any other way are not a YCbCr file this
    # decoder can read: Adobe's R, G and B, and a luma numbered zero.
    var adobe = patched(
        patched(patched(whole, frame + 10, 82), frame + 13, 71), frame + 16, 66
    )
    with assert_raises(contains="JFIF"):
        _ = decode(adobe)
    refused(patched(whole, frame + 10, 0))
    # And a scan naming one component twice is refused.
    var scan = segment(whole, 0xDA)
    refused(patched(whole, scan + 7, Int(whole[scan + 5])))


def test_a_quantization_table_holds_no_zero() raises:
    var whole = fixture("gradient444.jpg")
    var quant = segment(whole, 0xDB)
    refused(patched(whole, quant + 5, 0))
    refused(patched(whole, quant + 5 + 63, 0))
    var gray = fixture("gray.jpg")
    refused(patched(gray, segment(gray, 0xDB) + 5 + 20, 0))


def test_a_file_the_macos_encoder_wrote_decodes_to_two_levels() raises:
    # `sips` wrote this one from assets/brick.png: an EXIF segment, a
    # Photoshop segment, 4:2:0 chroma, the tables after the Huffman
    # tables and a restart interval, none of which PIL's files have.
    var image = decode(fixture("brick_sips.jpg"))
    assert_equal(image.width, 64)
    assert_equal(image.height, 64)
    var reference = decode_png(fixture("brick_sips_ref.png"))
    assert_true(
        worst_difference(image, reference) <= 2, "further than two levels"
    )


# --- progressive files assembled by hand ------------------------------------


struct Bits(Movable):
    """Entropy-coded bits written by hand: most significant first, a
    stuffed zero after every 0xFF, and one bits to pad the last byte."""

    var bytes: List[UInt8]
    var held: Int
    var count: Int

    def __init__(out self):
        self.bytes = List[UInt8]()
        self.held = 0
        self.count = 0

    def put(mut self, value: Int, size: Int):
        """Append the low `size` bits of `value`."""
        for index in range(size):
            self.held = (self.held << 1) | ((value >> (size - 1 - index)) & 1)
            self.count += 1
            if self.count == 8:
                self.bytes.append(UInt8(self.held))
                if self.held == 0xFF:
                    self.bytes.append(0)
                self.held = 0
                self.count = 0

    def dc(mut self, size: Int):
        """Append the DC code for a size of zero, one, two or five."""
        var sizes: List[Int] = [0, 1, 2, 5]
        for index in range(len(sizes)):
            if sizes[index] == size:
                self.put(index, 3)

    def ac(mut self, symbol: Int):
        """Append the AC code for `symbol`, one of `AC_SYMBOLS`."""
        var symbols = ac_symbols()
        for index in range(len(symbols)):
            if symbols[index] == symbol:
                self.put(index, 4)

    def finish(self) -> List[UInt8]:
        """Return every byte, the last padded with one bits."""
        var out = self.bytes.copy()
        if self.count > 0:
            var pad = 8 - self.count
            var byte = (self.held << pad) | ((1 << pad) - 1)
            out.append(UInt8(byte))
            if byte == 0xFF:
                out.append(0)
        return out^


def ac_symbols() -> List[Int]:
    """Return the AC symbols the hand-made files code, at four-bit codes:
    end of band, a one-bit value, a run of two end-of-bands, a run of one
    and a two-bit value, sixteen zeros, a run of one and a one-bit value,
    a run of five and a one-bit value, a two-bit value, a run of three and
    a one-bit value."""
    return [0x00, 0x01, 0x10, 0x12, 0xF0, 0x11, 0x51, 0x02, 0x31]


def hand_head(
    ids: List[Int], width: Int, height: Int, marker: Int = 0xC2
) -> List[UInt8]:
    """Return a file's start up to its first scan: every quantization
    step one, every component sampled once, the DC table coding sizes
    zero, one, two and five at three bits, and the AC table coding
    `ac_symbols` at four."""
    var out = List[UInt8]()
    out.append(0xFF)
    out.append(0xD8)
    var quant = List[Int]()
    quant.append(0)
    for _ in range(BLOCK_SAMPLES):
        quant.append(1)
    push_segment(out, 0xDB, quant)
    var frame: List[Int] = [8, height >> 8, height & 0xFF, width >> 8, width]
    frame[4] = width & 0xFF
    frame.append(len(ids))
    for id in ids:
        frame.append(id)
        frame.append(0x11)
        frame.append(0)
    push_segment(out, marker, frame)
    push_segment(out, 0xC4, huffman_payload(0, [0, 0, 4], [0, 1, 2, 5]))
    push_segment(
        out,
        0xC4,
        huffman_payload(1, [0, 0, 0, len(ac_symbols())], ac_symbols()),
    )
    return out^


def add_scan(
    mut out: List[UInt8],
    ids: List[Int],
    first: Int,
    last: Int,
    high: Int,
    low: Int,
    bits: Bits,
    tables: Int = 0x00,
):
    """Append a scan header and its coded bits."""
    var header = List[Int]()
    header.append(len(ids))
    for id in ids:
        header.append(id)
        header.append(tables)
    header.append(first)
    header.append(last)
    header.append((high << 4) | low)
    push_segment(out, 0xDA, header)
    for byte in bits.finish():
        out.append(byte)


def closed(bytes: List[UInt8]) -> List[UInt8]:
    """Return `bytes` with the end marker after them."""
    var out = bytes.copy()
    out.append(0xFF)
    out.append(0xD9)
    return out^


def expect_block(
    image: DecodedImage, block_x: Int, zigzag_values: List[Int]
) raises:
    """Assert a gray block is what its coefficients, given as zigzag
    index and value pairs one after the other, transform to."""
    var order = zigzag_order()
    var coefficients = List[Float32](length=BLOCK_SAMPLES, fill=0)
    for index in range(0, len(zigzag_values), 2):
        coefficients[order[zigzag_values[index]]] = Float32(
            zigzag_values[index + 1]
        )
    var samples = inverse_dct(coefficients, cosine_table())
    for y in range(8):
        for x in range(8):
            assert_equal(
                image.get_pixel(block_x * 8 + x, y).r,
                clamp_sample(samples[y * 8 + x]),
            )


def dc_first(ids: List[Int]) -> List[UInt8]:
    """Return the start of an eight-by-eight file and one DC scan, down to
    bit one, that gives each component's block a difference of zero."""
    var out = hand_head(ids, 8, 8)
    var bits = Bits()
    for _ in range(len(ids)):
        bits.dc(0)
    add_scan(out, ids, 0, 0, 0, 1, bits)
    return out^


def test_every_kind_of_progressive_scan_builds_one_block() raises:
    var out = hand_head([1], 8, 8)
    # A DC scan down to bit one: a difference of three, so six.
    var dc = Bits()
    dc.dc(2)
    dc.put(3, 2)
    add_scan(out, [1], 0, 0, 0, 1, dc)
    # The band one to five down to bit one: one zero, then two, which is
    # four; then the end of the band.
    var low = Bits()
    low.ac(0x12)
    low.put(2, 2)
    low.ac(0x00)
    add_scan(out, [1], 1, 5, 0, 1, low)
    # The band six on down to bit one: sixteen zeros, then minus one at
    # twenty-two, which is minus two; then an end-of-band run of two
    # whose extra bit is one, so this block and two more are done.
    var high = Bits()
    high.ac(0xF0)
    high.ac(0x01)
    high.put(0, 1)
    high.ac(0x10)
    high.put(1, 1)
    add_scan(out, [1], 6, 63, 0, 1, high)
    # The DC coefficient's last bit: six becomes seven.
    var dc_bit = Bits()
    dc_bit.put(1, 1)
    add_scan(out, [1], 0, 0, 1, 0, dc_bit)
    # The first band's last bit: a new minus one at the first zero,
    # then the end of the band, which corrects four to five.
    var low_bit = Bits()
    low_bit.ac(0x01)
    low_bit.put(0, 1)
    low_bit.ac(0x00)
    low_bit.put(1, 1)
    add_scan(out, [1], 1, 5, 1, 0, low_bit)
    # The second band's last bit: sixteen zeros pass; then a run of one
    # and a new plus one, which corrects minus two to minus three on
    # the way and lands at twenty-four; then the end of the band.
    var high_bit = Bits()
    high_bit.ac(0xF0)
    high_bit.ac(0x11)
    high_bit.put(1, 1)
    high_bit.put(1, 1)
    high_bit.ac(0x00)
    add_scan(out, [1], 6, 63, 1, 0, high_bit)
    var image = decode(closed(out))
    expect_block(image, 0, [0, 7, 1, -1, 2, 5, 22, -3, 24, 1])


def test_end_of_band_runs_carry_across_blocks() raises:
    var out = hand_head([1], 16, 8)
    # Two blocks, the second predicted from the first: both two. The
    # scan names an AC table never defined, which a DC scan never reads.
    var dc = Bits()
    dc.dc(1)
    dc.put(1, 1)
    dc.dc(0)
    add_scan(out, [1], 0, 0, 0, 1, dc, tables=0x01)
    # The first block's first coefficient is two, and an end-of-band run
    # of two with an extra bit of zero closes it and the next block.
    var band = Bits()
    band.ac(0x01)
    band.put(1, 1)
    band.ac(0x10)
    band.put(0, 1)
    add_scan(out, [1], 1, 63, 0, 1, band, tables=0x10)
    # The DC bits: zero for the first, one for the second. A DC
    # refinement reads no table, so an undefined one is no matter.
    var dc_bit = Bits()
    dc_bit.put(0, 1)
    dc_bit.put(1, 1)
    add_scan(out, [1], 0, 0, 1, 0, dc_bit, tables=0x10)
    # An end-of-band run of two covers both blocks: the first's one
    # nonzero coefficient takes a correction bit of zero.
    var band_bit = Bits()
    band_bit.ac(0x10)
    band_bit.put(0, 1)
    band_bit.put(0, 1)
    add_scan(out, [1], 1, 63, 1, 0, band_bit)
    var image = decode(closed(out))
    expect_block(image, 0, [0, 2, 1, 2])
    expect_block(image, 1, [0, 3])


def test_a_band_that_fills_up_ends_its_block_without_a_code() raises:
    var out = hand_head([1], 8, 8)
    var dc = Bits()
    dc.dc(0)
    add_scan(out, [1], 0, 0, 0, 0, dc)
    # The band one to one: its one coefficient placed, two at bit one,
    # which ends the band with no end-of-band code. Its refinement is
    # sixteen zeros asked for, which passes the coefficient with a
    # correction bit of one, making three, and runs off the band.
    var first = Bits()
    first.ac(0x01)
    first.put(1, 1)
    add_scan(out, [1], 1, 1, 0, 1, first)
    var first_bit = Bits()
    first_bit.ac(0xF0)
    first_bit.put(1, 1)
    add_scan(out, [1], 1, 1, 1, 0, first_bit)
    # The band two to two, empty at first; its refinement places a new
    # minus one at the band's end.
    var second = Bits()
    second.ac(0x00)
    add_scan(out, [1], 2, 2, 0, 1, second)
    var second_bit = Bits()
    second_bit.ac(0x01)
    second_bit.put(0, 1)
    add_scan(out, [1], 2, 2, 1, 0, second_bit)
    var image = decode(closed(out))
    expect_block(image, 0, [1, 3, 2, -1])


def test_a_progressive_scan_is_refused_where_its_bits_break_the_rules() raises:
    # A value past the band in a first scan: a run of five from one.
    var past = dc_first([1])
    var run = Bits()
    run.ac(0x51)
    run.put(1, 1)
    add_scan(past, [1], 1, 5, 0, 0, run)
    refused(closed(past))
    # A refinement's new coefficient of two bits.
    var wide = dc_first([1])
    var empty = Bits()
    empty.ac(0x00)
    add_scan(wide, [1], 1, 5, 0, 1, empty)
    var two = Bits()
    two.ac(0x02)
    two.put(3, 2)
    add_scan(wide, [1], 1, 5, 1, 0, two)
    with assert_raises(contains="one bit"):
        _ = decode(closed(wide))
    # A refinement's new coefficient past the band: three zeros asked
    # for in a band of two.
    var over = dc_first([1])
    var none = Bits()
    none.ac(0x00)
    add_scan(over, [1], 1, 2, 0, 1, none)
    var three = Bits()
    three.ac(0x31)
    three.put(1, 1)
    add_scan(over, [1], 1, 2, 1, 0, three)
    refused(closed(over))


def test_a_progressive_scan_header_is_checked_field_by_field() raises:
    # An AC scan before the DC scan.
    var early = hand_head([1], 8, 8)
    var nothing = Bits()
    nothing.ac(0x00)
    add_scan(early, [1], 1, 5, 0, 0, nothing)
    with assert_raises(contains="before its component's DC"):
        _ = decode(closed(early))
    # The DC coefficient sent twice, and refined from the wrong bit.
    var twice = dc_first([1])
    var again = Bits()
    again.dc(0)
    add_scan(twice, [1], 0, 0, 0, 1, again)
    with assert_raises(contains="out of order or twice"):
        _ = decode(closed(twice))
    var skipped = dc_first([1])
    add_scan(skipped, [1], 0, 0, 2, 1, Bits())
    refused(closed(skipped))
    # A refinement of more than one bit; a stop past bit thirteen.
    var leap = dc_first([1])
    add_scan(leap, [1], 0, 0, 2, 0, Bits())
    with assert_raises(contains="one bit"):
        _ = decode(closed(leap))
    var deep = hand_head([1], 8, 8)
    add_scan(deep, [1], 0, 0, 0, 14, Bits())
    refused(closed(deep))
    # A DC scan holding AC coefficients; a band that runs backward, and
    # one past the sixty-third.
    var mixed = hand_head([1], 8, 8)
    add_scan(mixed, [1], 0, 5, 0, 0, Bits())
    refused(closed(mixed))
    var backward = dc_first([1])
    add_scan(backward, [1], 5, 4, 0, 0, Bits())
    refused(closed(backward))
    var beyond = dc_first([1])
    add_scan(beyond, [1], 1, 64, 0, 0, Bits())
    refused(closed(beyond))
    # An AC scan of three components.
    var three = dc_first([1, 2, 3])
    add_scan(three, [1, 2, 3], 1, 5, 0, 0, Bits())
    with assert_raises(contains="one component"):
        _ = decode(closed(three))
    # A table the scan needs and nobody defined: the AC table of an AC
    # scan, and the DC table of a first DC scan.
    var no_ac = dc_first([1])
    add_scan(no_ac, [1], 1, 5, 0, 0, Bits(), tables=0x01)
    refused(closed(no_ac))
    var no_dc = hand_head([1], 8, 8)
    add_scan(no_dc, [1], 0, 0, 0, 0, Bits(), tables=0x10)
    refused(closed(no_dc))


def test_every_component_must_be_in_some_scan() raises:
    # A DC scan of the luma alone, and then the end.
    var out = hand_head([1, 2, 3], 8, 8)
    var dc = Bits()
    dc.dc(0)
    add_scan(out, [1], 0, 0, 0, 0, dc)
    with assert_raises(contains="no scan"):
        _ = decode(closed(out))
    # A file with a frame and no scan at all.
    with assert_raises(contains="before its scan"):
        _ = decode(closed(hand_head([1], 8, 8)))


def test_a_sequential_file_can_hold_a_scan_per_component() raises:
    # The luma lifted by two levels, each chroma flat: gray at 130.
    var out = hand_head([1, 2, 3], 8, 8, marker=0xC0)
    var luma = Bits()
    luma.dc(5)
    luma.put(16, 5)
    luma.ac(0x00)
    add_scan(out, [1], 0, 63, 0, 0, luma)
    for id in [3, 2]:
        var chroma = Bits()
        chroma.dc(0)
        chroma.ac(0x00)
        add_scan(out, [id], 0, 63, 0, 0, chroma)
    var image = decode(closed(out))
    var seen = image.get_pixel(5, 5)
    assert_equal(seen.r, UInt8(130))
    assert_equal(seen.g, UInt8(130))
    assert_equal(seen.b, UInt8(130))
    # A component in two sequential scans is refused.
    var twice = hand_head([1], 8, 8, marker=0xC0)
    for _ in range(2):
        var block = Bits()
        block.dc(0)
        block.ac(0x00)
        add_scan(twice, [1], 0, 63, 0, 0, block)
    refused(closed(twice))


def test_a_component_keeps_the_quantization_table_of_its_first_scan() raises:
    # A DC coefficient of sixteen at a step of one is two levels. The
    # table is then redefined at a step of two, which would make four
    # levels, but the component took its table when its first scan began.
    var out = hand_head([1], 8, 8)
    var dc = Bits()
    dc.dc(5)
    dc.put(16, 5)
    add_scan(out, [1], 0, 0, 0, 0, dc)
    var doubled = List[Int]()
    doubled.append(0)
    for _ in range(BLOCK_SAMPLES):
        doubled.append(2)
    push_segment(out, 0xDB, doubled)
    var band = Bits()
    band.ac(0x00)
    add_scan(out, [1], 1, 63, 0, 0, band)
    assert_equal(decode(closed(out)).get_pixel(3, 3).r, UInt8(130))


def test_a_scan_names_one_to_all_of_the_components() raises:
    var whole = fixture("gradient444.jpg")
    refused(patched(whole, segment(whole, 0xDA) + 4, 0))
    var gray = fixture("gray.jpg")
    refused(patched(gray, segment(gray, 0xDA) + 4, 2))
    # A sequential scan's refinement bit alone is refused as well.
    refused(patched(whole, segment(whole, 0xDA) + 13, 0x10))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
