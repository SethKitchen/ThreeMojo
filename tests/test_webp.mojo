# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.webp`, `render.webp_lossless` and
`render.webp_lossy`.

`assets/webp/` holds WebP files that libwebp 1.6.0's `cwebp` wrote with
one set of options each, and some damaged on purpose. Each `name.png`
holds the pixels that libwebp's `dwebp` decodes from `name.webp`, and
`webp.json` says which files libwebp refuses. `make_webp.py` wrote them.

Streams and containers that no encoder writes are built here, bit by bit,
for the errors that libwebp checks.
"""

from loaders.json import parse_json
from render.png import decode as decode_png
from render.webp import decode, decode_alpha, is_webp
from render.webp_lossless import (
    SUBTRACT_GREEN_TRANSFORM,
    WebpTransform,
    apply_inverse,
    decode_lossless,
)
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _file(name: String) raises -> List[UInt8]:
    return Path("assets/webp/" + name).read_bytes()


def test_every_file_decodes_as_libwebp_decodes_it() raises:
    var doc = parse_json(Path("assets/webp/webp.json").read_text())
    var cases = doc.get(doc.root(), "cases")
    for k in range(doc.length(cases)):
        var entry = doc.at(cases, k)
        var name = doc.string(doc.get(entry, "name"))
        var bytes = _file(name + ".webp")
        if doc.boolean(doc.get(entry, "error")):
            with assert_raises():
                _ = decode(bytes)
            continue
        var got = decode(bytes)
        var want = decode_png(_file(name + ".png"))
        assert_equal(got.width, want.width, name)
        assert_equal(got.height, want.height, name)
        for i in range(len(want.pixels)):
            if got.pixels[i] != want.pixels[i]:
                var pixel = i // 4
                assert_equal(
                    got.pixels[i],
                    want.pixels[i],
                    name
                    + " at x "
                    + String(pixel % want.width)
                    + ", y "
                    + String(pixel // want.width)
                    + ", channel "
                    + String(i % 4),
                )


def test_a_webp_file_is_told_by_its_header() raises:
    assert_true(is_webp(_file("lossy_q75.webp")))
    assert_false(is_webp(_file("lossy_q75.png")))
    var short: List[UInt8] = [0x52, 0x49, 0x46, 0x46]
    assert_false(is_webp(short))
    with assert_raises(contains="not a RIFF WEBP file"):
        _ = decode(short)


struct _Writer(Movable):
    """Write bits from each byte's low end first, as VP8L reads them."""

    var bytes: List[UInt8]
    var count: Int

    def __init__(out self):
        self.bytes = List[UInt8]()
        self.count = 0

    def put(mut self, value: Int, bits: Int):
        for i in range(bits):
            if self.count % 8 == 0:
                self.bytes.append(0)
            if (value >> i) & 1 == 1:
                self.bytes[len(self.bytes) - 1] |= UInt8(1 << (self.count % 8))
            self.count += 1


def _header(width: Int, height: Int) -> _Writer:
    """A VP8L header, then no transform, no cache and one group."""
    var w = _Writer()
    w.put(0x2F, 8)
    w.put(width - 1, 14)
    w.put(height - 1, 14)
    w.put(0, 1)
    w.put(0, 3)
    return w^


def _single(mut w: _Writer, symbol: Int):
    """A simple code of one eight-bit symbol, which takes no bits."""
    w.put(1, 1)
    w.put(0, 1)
    w.put(1, 1)
    w.put(symbol, 8)


def _plain(mut w: _Writer):
    """No transform, no color cache and no group image."""
    w.put(0, 1)
    w.put(0, 1)
    w.put(0, 1)


def _lengths_code(mut w: _Writer, lengths: List[Int]):
    """A code whose lengths a code-length code of four lengths stores:
    for 17, 18, 0 and 1, in the format's order."""
    w.put(0, 1)
    w.put(0, 4)
    for length in lengths:
        w.put(length, 3)


def test_a_hand_made_stream_of_one_color_decodes() raises:
    var w = _header(3, 2)
    _plain(w)
    for symbol in [0x40, 0x10, 0x20, 0x80, 0]:
        _single(w, symbol)
    var image = decode_lossless(w.bytes.copy())
    assert_equal(image.width, 3)
    assert_equal(image.height, 2)
    for pixel in image.pixels:
        assert_equal(pixel, 0x80104020)


def _refused(var w: _Writer, message: String) raises:
    with assert_raises(contains=message):
        _ = decode_lossless(w.bytes.copy())


def test_a_malformed_lossless_stream_is_refused() raises:
    var short: List[UInt8] = [0x2F]
    with assert_raises(contains="not a VP8L stream"):
        _ = decode_lossless(short^)
    var wrong: List[UInt8] = [0x2E, 0, 0, 0, 0]
    with assert_raises(contains="not a VP8L stream"):
        _ = decode_lossless(wrong^)
    var version: List[UInt8] = [0x2F, 0, 0, 0, 0x20]
    with assert_raises(contains="not a VP8L stream"):
        _ = decode_lossless(version^)
    # The same transform twice.
    var twice = _header(2, 2)
    for _ in range(2):
        twice.put(1, 1)
        twice.put(2, 2)
    _refused(twice^, "named twice")
    # A color cache of no bits, and of twelve.
    for bits in [0, 12]:
        var cache = _header(2, 2)
        cache.put(0, 1)
        cache.put(1, 1)
        cache.put(bits, 4)
        _refused(cache^, "color cache of that size")
    # A simple code whose one symbol is past the alphabet has none.
    var none = _header(2, 2)
    _plain(none)
    for _ in range(4):
        _single(none, 0)
    _single(none, 200)
    _refused(none^, "has no symbols")
    # More lengths than the green alphabet has symbols.
    var more = _header(2, 2)
    _plain(more)
    _lengths_code(more, [0, 0, 1, 1])
    more.put(1, 1)
    more.put(4, 3)
    more.put(1023, 10)
    _refused(more^, "more lengths than symbols")
    # Runs of zeros past the alphabet: 18 is code 1, and each run is 138.
    var runs = _header(2, 2)
    _plain(runs)
    _lengths_code(runs, [0, 1, 0, 1])
    runs.put(0, 1)
    for _ in range(3):
        runs.put(1, 1)
        runs.put(127, 7)
    _refused(runs^, "run past its symbols")
    # A code-length code of three one-bit codes, and of two two-bit ones.
    var over = _header(2, 2)
    _plain(over)
    _lengths_code(over, [1, 1, 1, 0])
    _refused(over^, "over-subscribed")
    var short_code = _header(2, 2)
    _plain(short_code)
    _lengths_code(short_code, [2, 2, 0, 0])
    _refused(short_code^, "not complete")
    # A copy from before the first pixel: green's symbols are 0, code 0,
    # and a copy of length one, code 1.
    var copy = _header(2, 2)
    _plain(copy)
    _lengths_code(copy, [0, 0, 1, 1])
    copy.put(0, 1)
    for symbol in range(280):
        copy.put(1 if symbol == 0 or symbol == 256 else 0, 1)
    for _ in range(4):
        _single(copy, 0)
    copy.put(1, 1)
    _refused(copy^, "copy reaches outside")
    # Two green symbols, one bit a pixel, and too few bits.
    var cut = _header(8, 8)
    _plain(cut)
    cut.put(1, 1)
    cut.put(1, 1)
    cut.put(1, 1)
    cut.put(0, 8)
    cut.put(1, 8)
    for _ in range(4):
        _single(cut, 0)
    _refused(cut^, "ends too soon")
    with assert_raises(contains="transform that is not known"):
        _ = apply_inverse(
            WebpTransform(9), 0, 1, List[UInt32](), List[UInt32](), 1
        )
    var green: List[UInt32] = [0x00102030]
    var added = apply_inverse(
        SUBTRACT_GREEN_TRANSFORM, 0, 1, List[UInt32](), green^, 1
    )
    assert_equal(added[0], 0x00302050)


def _le32(value: Int) -> List[UInt8]:
    var out = List[UInt8]()
    for i in range(4):
        out.append(UInt8((value >> (8 * i)) & 0xFF))
    return out^


def _chunk(tag: String, data: List[UInt8], size: Int = -1) -> List[UInt8]:
    """A chunk, padded to an even length; `size` overrides its size."""
    var out = List[UInt8]()
    for b in tag.as_bytes():
        out.append(b)
    out += _le32(len(data) if size < 0 else size)
    out += data.copy()
    if len(data) % 2 == 1:
        out.append(0)
    return out^


def _riff(body: List[UInt8], riff: Int = -1) -> List[UInt8]:
    """A RIFF WEBP file around chunks; `riff` overrides its size."""
    var out: List[UInt8] = [0x52, 0x49, 0x46, 0x46]
    out += _le32(4 + len(body) if riff < 0 else riff)
    out += [0x57, 0x45, 0x42, 0x50]
    out += body.copy()
    return out^


def _vp8x(width: Int, height: Int) -> List[UInt8]:
    var data: List[UInt8] = [0x10, 0, 0, 0]
    for value in [width - 1, height - 1]:
        for i in range(3):
            data.append(UInt8((value >> (8 * i)) & 0xFF))
    return _chunk("VP8X", data)


def _payload(name: String) raises -> List[UInt8]:
    """The image chunk's payload of a file here."""
    var bytes = _file(name)
    var size = Int(bytes[16]) | (Int(bytes[17]) << 8) | (Int(bytes[18]) << 16)
    var out = List[UInt8]()
    for i in range(20, 20 + size):
        out.append(bytes[i])
    return out^


def _container_refused(bytes: List[UInt8], message: String) raises:
    with assert_raises(contains=message):
        _ = decode(bytes)


def test_a_malformed_container_is_refused() raises:
    var lossless = _payload("lossless_z5.webp")
    var lossy = _payload("lossy_q75.webp")
    var riff: List[UInt8] = [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0]
    assert_false(is_webp(riff))
    riff += [0x57, 0x45, 0x42, 0x51]
    assert_false(is_webp(riff))
    var ten: List[UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0]
    _container_refused(
        _riff(_chunk("VP8X", ten)), "VP8X chunk that is not ten bytes"
    )
    var head: List[UInt8] = [0x56, 0x50, 0x38, 0x58, 10, 0, 0, 0, 0, 0]
    _container_refused(_riff(head), "VP8X chunk runs past the file")
    _container_refused(_riff(_vp8x(67, 45)), "no image chunk")
    var extra = _vp8x(67, 45) + _chunk("XTRA", List[UInt8](), 100)
    _container_refused(_riff(extra), "runs past the RIFF size")
    _container_refused(
        _riff(_chunk("XTRA", List[UInt8]()) + _chunk("VP8L", lossless)),
        "image chunk is not VP8 or VP8L",
    )
    _container_refused(
        _riff(_chunk("VP8L", lossless, 500000)), "image chunk runs past"
    )
    # Alpha that is empty, and raw alpha that is short.
    var empty = (
        _vp8x(67, 45) + _chunk("ALPH", List[UInt8]()) + _chunk("VP8 ", lossy)
    )
    _container_refused(_riff(empty), "alpha chunk is empty")
    var raw: List[UInt8] = [0, 1, 2, 3]
    var short = _vp8x(67, 45) + _chunk("ALPH", raw) + _chunk("VP8 ", lossy)
    _container_refused(_riff(short), "raw alpha is too short")
    # The last alpha chunk counts: raw alpha of all 7s, after one that
    # is empty.
    var sevens: List[UInt8] = [0]
    for _ in range(67 * 45):
        sevens.append(7)
    var last = (
        _vp8x(67, 45)
        + _chunk("ALPH", raw)
        + _chunk("ALPH", sevens)
        + _chunk("VP8 ", lossy)
    )
    var image = decode(_riff(last))
    assert_equal(image.pixels[3], 7)
    assert_equal(len(decode_alpha(sevens, 67, 45)), 67 * 45)


def _frame(var payload: List[UInt8]) -> List[UInt8]:
    return _riff(_chunk("VP8 ", payload))


def _with_partition(payload: List[UInt8], length: Int) -> List[UInt8]:
    """The frame with its first partition's length changed."""
    var out = payload.copy()
    var tag = Int(out[0]) | (Int(out[1]) << 8) | (Int(out[2]) << 16)
    tag = (tag & 0x1F) | (length << 5)
    out[0] = UInt8(tag & 0xFF)
    out[1] = UInt8((tag >> 8) & 0xFF)
    out[2] = UInt8((tag >> 16) & 0xFF)
    return out^


def test_a_malformed_lossy_frame_is_refused() raises:
    var lossy = _payload("lossy_q75.webp")
    var size = len(lossy)
    var cut = List[UInt8]()
    for i in range(9):
        cut.append(lossy[i])
    _container_refused(_frame(cut^), "frame header is too short")
    var start = lossy.copy()
    start[3] = 0
    _container_refused(_frame(start^), "start code is wrong")
    var inter = lossy.copy()
    inter[0] |= 1
    _container_refused(_frame(inter^), "not a key frame")
    var profile = lossy.copy()
    profile[0] |= 0x08
    _container_refused(_frame(profile^), "profile that is not known")
    var hidden = lossy.copy()
    hidden[0] &= ~UInt8(0x10)
    _container_refused(_frame(hidden^), "not shown")
    _container_refused(
        _frame(_with_partition(lossy, size)), "first partition runs past"
    )
    _container_refused(
        _frame(_with_partition(lossy, size - 5)), "first partition runs past"
    )
    var empty = lossy.copy()
    empty[6] = 0
    empty[7] = 0
    _container_refused(_frame(empty^), "frame with no size")
    # Cut right after the first partition: the token partition is empty.
    var tag = Int(lossy[0]) | (Int(lossy[1]) << 8) | (Int(lossy[2]) << 16)
    var first = tag >> 5
    var headless = List[UInt8]()
    for i in range(10 + first):
        headless.append(lossy[i])
    _container_refused(_frame(headless^), "last partition is empty")
    # Four partitions, cut before their sizes.
    var four = _payload("lossy_four_partitions.webp")
    var four_first = (
        Int(four[0]) | (Int(four[1]) << 8) | (Int(four[2]) << 16)
    ) >> 5
    var sizes = List[UInt8]()
    for i in range(10 + four_first + 2):
        sizes.append(four[i])
    _container_refused(_frame(sizes^), "partition sizes run past")
    # A first partition too short for its headers, then for its modes.
    var seen = String()
    for length in range(0, first):
        try:
            _ = decode(_frame(_with_partition(lossy, length)))
        except error:
            seen += String(error) + "\n"
    assert_true("segment header" in seen)
    assert_true("filter header" in seen)
    assert_true("first partition ends too soon" in seen)
    # The token partition cut in half.
    var half = List[UInt8]()
    for i in range(10 + first + (size - 10 - first) // 2):
        half.append(lossy[i])
    _container_refused(_frame(half^), "token partition ends too soon")


def test_a_code_of_fifteen_bits_is_read() raises:
    # A code-length code of sixteen four-bit codes, one for each length,
    # then green's lengths 1 to 14, 15 and 15: a complete code whose last
    # two symbols take fifteen bits.
    var w = _header(1, 1)
    _plain(w)
    w.put(0, 1)
    w.put(15, 4)
    var order: List[Int] = [
        17,
        18,
        0,
        1,
        2,
        3,
        4,
        5,
        16,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
    ]
    for symbol in order:
        w.put(4 if symbol <= 15 else 0, 3)
    w.put(0, 1)
    for symbol in range(280):
        var length = 0
        if symbol < 14:
            length = symbol + 1
        elif symbol < 16:
            length = 15
        for b in range(3, -1, -1):
            w.put((length >> b) & 1, 1)
    for _ in range(4):
        _single(w, 0)
    for _ in range(15):
        w.put(1, 1)
    var image = decode_lossless(w.bytes.copy())
    assert_equal(image.pixels[0], 15 << 8)


def _predicted(width: Int, height: Int) raises -> List[UInt32]:
    """An image of zeros under a predictor transform whose every tile is
    mode 14, which libwebp pads with black."""
    var w = _header(width, height)
    w.put(1, 1)
    w.put(0, 2)
    w.put(0, 3)
    w.put(0, 1)
    _single(w, 14)
    for _ in range(4):
        _single(w, 0)
    w.put(0, 1)
    w.put(0, 1)
    w.put(0, 1)
    for _ in range(5):
        _single(w, 0)
    return decode_lossless(w.bytes.copy()).pixels.copy()


def test_the_padded_predictor_modes_predict_black() raises:
    for size in [(2, 2), (1, 2), (2, 1)]:
        var pixels = _predicted(size[0], size[1])
        assert_equal(len(pixels), size[0] * size[1])
        for pixel in pixels:
            assert_equal(pixel, 0xFF000000)


def test_a_palette_of_three_colors_packs_four_indices() raises:
    var w = _header(5, 1)
    w.put(1, 1)
    w.put(3, 2)
    w.put(2, 8)
    # The palette: each color the one before plus 0x44221133.
    w.put(0, 1)
    for symbol in [0x11, 0x22, 0x33, 0x44, 0]:
        _single(w, symbol)
    w.put(0, 1)
    w.put(0, 1)
    w.put(0, 1)
    for _ in range(5):
        _single(w, 0)
    var image = decode_lossless(w.bytes.copy())
    assert_equal(len(image.pixels), 5)
    for pixel in image.pixels:
        assert_equal(pixel, 0x44221133)


def test_a_second_simple_symbol_past_the_alphabet_is_dropped() raises:
    var w = _header(2, 1)
    _plain(w)
    for _ in range(4):
        _single(w, 7)
    # Distance: two symbols, 0 and 200, and 200 is past 40.
    w.put(1, 1)
    w.put(1, 1)
    w.put(0, 1)
    w.put(0, 1)
    w.put(200, 8)
    var image = decode_lossless(w.bytes.copy())
    assert_equal(image.pixels[1], 0x07070707)


def test_a_copy_past_the_last_pixel_is_refused() raises:
    # Green's codes are 0 for a literal and 1 for a copy of five pixels,
    # from a distance of one: past the end of a two-pixel image.
    var w = _header(2, 1)
    _plain(w)
    _lengths_code(w, [0, 0, 1, 1])
    w.put(0, 1)
    for symbol in range(280):
        w.put(1 if symbol == 0 or symbol == 260 else 0, 1)
    for _ in range(3):
        _single(w, 0)
    _single(w, 13)
    w.put(0, 1)
    w.put(1, 1)
    w.put(0, 1)
    w.put(24, 5)
    _refused(w^, "copy reaches outside")


def test_a_vp8x_file_can_hold_a_lossless_image() raises:
    var lossless = _payload("lossless_z5.webp")
    var plain = decode(_file("lossless_z5.webp"))
    var extra: List[UInt8] = [1, 2, 3]
    var wrapped = decode(
        _riff(_vp8x(67, 45) + _chunk("XTRA", extra) + _chunk("VP8L", lossless))
    )
    assert_equal(len(wrapped.pixels), len(plain.pixels))
    for i in range(len(plain.pixels)):
        assert_equal(wrapped.pixels[i], plain.pixels[i])


def test_each_byte_of_the_start_code_is_checked() raises:
    var lossy = _payload("lossy_q75.webp")
    for at in [4, 5]:
        var wrong = lossy.copy()
        wrong[at] = 0
        _container_refused(_frame(wrong^), "start code is wrong")
    var flat = lossy.copy()
    flat[8] = 0
    flat[9] = 0
    _container_refused(_frame(flat^), "frame with no size")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
