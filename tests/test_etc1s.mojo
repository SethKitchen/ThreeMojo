# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.etc1s`: BasisLZ global data and slices written bit by
bit, and every malformed one the decoder refuses.

`tests/test_ktx2.mojo` checks whole files that the Basis Universal
encoder wrote against three.js's transcoder. These tests build the data
by hand, so each prediction, selector and refusal has a case of its own.
The Huffman tables here use one code length per table, or the code-length
code `Writer.table` writes, so a test can say which symbol each code is.
"""

from render.etc1s import Etc1sGlobal, etc1s_image, etc1s_intensities
from std.testing import TestSuite, assert_equal, assert_raises


def order() -> List[Int]:
    """Return the order the code-length code sizes are stored in."""
    return [
        17, 18, 19, 20, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
        16,
    ]  # fmt: skip


struct Writer(Movable):
    """Bits written low bit first, as the decoder reads them."""

    var bits: List[Int]

    def __init__(out self):
        self.bits = List[Int]()

    def put(mut self, value: Int, count: Int):
        """Write `count` bits of `value`, low bit first."""
        for bit in range(count):
            self.bits.append((value >> bit) & 1)

    def code(mut self, value: Int, count: Int):
        """Write a Huffman code of `count` bits, high bit first."""
        for bit in range(count - 1, -1, -1):
            self.bits.append((value >> bit) & 1)

    def length_symbol(mut self, symbol: Int):
        """Write a symbol of the code-length code `table` uses: symbols 0
        to 10 in four bits, 11 to 20 in five."""
        if symbol < 11:
            self.code(symbol, 4)
        else:
            self.code(22 + symbol - 11, 5)

    def lengths_header(mut self, total: Int):
        """Write a table's symbol count and the code-length code."""
        self.put(total, 14)
        self.put(21, 5)
        for code in order():
            self.put(4 if code < 11 else 5, 3)

    def table(mut self, sizes: List[Int]):
        """Write a Huffman table of the given code lengths."""
        self.lengths_header(len(sizes))
        for size in sizes:
            self.length_symbol(size)

    def flat(mut self, bits: Int):
        """Write a table of `2 ** bits` symbols, each `bits` long, so that
        symbol `s` has the code `s`."""
        self.table(List[Int](length=1 << bits, fill=bits))

    def vlc(mut self, value: Int, chunk: Int):
        """Write a number in chunks of `chunk` bits."""
        var rest = value
        while True:
            self.put(rest & ((1 << chunk) - 1), chunk)
            rest >>= chunk
            self.put(1 if rest > 0 else 0, 1)
            if rest == 0:
                return

    def bytes(self) -> List[UInt8]:
        """Return the bits as bytes, the last one padded with zeros."""
        var out = List[UInt8](length=(len(self.bits) + 7) // 8, fill=0)
        for index in range(len(self.bits)):
            out[index >> 3] |= UInt8(self.bits[index] << (index & 7))
        return out^


def le(value: Int, count: Int) -> List[UInt8]:
    """Return `value` as `count` little-endian bytes."""
    var out = List[UInt8]()
    for index in range(count):
        out.append(UInt8((value >> (index * 8)) & 0xFF))
    return out^


struct Global(Movable):
    """BasisLZ global data under construction.

    The endpoint and selector codebooks, flat Huffman tables for a slice,
    and one image descriptor per image.
    """

    var endpoints: List[Int]
    var selectors: List[Int]
    var history: Int
    var images: List[Int]
    var delta_bits: Int
    var selector_bits: Int
    var raw_selectors: Bool
    var selector_flags: Int
    var empty_intensity_table: Bool
    var empty_selector_table: Bool
    var empty_run_table: Bool
    var tables: List[UInt8]
    """The slice tables section, or empty for flat tables."""

    def __init__(out self):
        # Two endpoints: 5-bit red 31 with the smallest table, and gray 16
        # with the largest.
        self.endpoints = [31, 0, 0, 0, 16, 16, 16, 7]
        # Selector 0 is all zeros; selector 1 is all threes.
        self.selectors = [0, 0, 0, 0, 255, 255, 255, 255]
        self.history = 4
        self.images = List[Int]()
        self.delta_bits = 1
        self.selector_bits = 3
        self.raw_selectors = True
        self.selector_flags = 0
        self.empty_intensity_table = False
        self.empty_selector_table = False
        self.empty_run_table = False
        self.tables = List[UInt8]()

    def image(mut self, rgb_offset: Int, rgb_length: Int, alpha: Int = 0):
        """Add an image descriptor; an alpha slice follows the color."""
        self.images.extend([0, rgb_offset, rgb_length, rgb_length, alpha])

    def endpoint_data(self) -> List[UInt8]:
        """Return the endpoint codebook: flat tables and deltas."""
        var w = Writer()
        for _ in range(3):
            w.flat(5)
        if self.empty_intensity_table:
            w.put(0, 14)
        else:
            w.flat(3)
        w.put(0, 1)
        var previous: List[Int] = [16, 16, 16]
        var intensity = 0
        for index in range(len(self.endpoints) // 4):
            var at = index * 4
            w.code((self.endpoints[at + 3] - intensity) & 7, 3)
            intensity = self.endpoints[at + 3]
            for channel in range(3):
                w.code(
                    (self.endpoints[at + channel] - previous[channel]) & 31, 5
                )
                previous[channel] = self.endpoints[at + channel]
        return w.bytes()

    def selector_data(self) -> List[UInt8]:
        """Return the selector codebook, raw or delta coded."""
        var w = Writer()
        w.put(self.selector_flags, 2)
        if self.raw_selectors:
            w.put(1, 1)
            for byte in self.selectors:
                w.put(byte, 8)
            return w.bytes()
        w.put(0, 1)
        if self.empty_selector_table:
            w.put(0, 14)
        else:
            w.flat(8)
        for index in range(len(self.selectors)):
            if index < 4:
                w.put(self.selectors[index], 8)
            else:
                w.code(self.selectors[index] ^ self.selectors[index - 4], 8)
        return w.bytes()

    def table_data(self) -> List[UInt8]:
        """Return the slice tables: flat codes and the history size."""
        if len(self.tables) > 0:
            return self.tables.copy()
        var w = Writer()
        w.flat(9)
        w.flat(self.delta_bits)
        w.flat(self.selector_bits)
        if self.empty_run_table:
            w.put(0, 14)
        else:
            w.flat(6)
        w.put(self.history, 13)
        return w.bytes()

    def bytes(self, slice_length: Int = -1) -> List[UInt8]:
        """Return the global data: with one image whose color slice is
        `slice_length` bytes at the start of its level, or with the images
        added."""
        var images = self.images.copy()
        if slice_length >= 0:
            images = [0, 0, slice_length, 0, 0]
        var endpoints = self.endpoint_data()
        var selectors = self.selector_data()
        var tables = self.table_data()
        var out = le(len(self.endpoints) // 4, 2)
        out.extend(le(len(self.selectors) // 4, 2))
        out.extend(le(len(endpoints), 4))
        out.extend(le(len(selectors), 4))
        out.extend(le(len(tables), 4))
        out.extend(le(0, 4))
        for value in images:
            out.extend(le(value, 4))
        out.extend(endpoints^)
        out.extend(selectors^)
        out.extend(tables^)
        return out^


def decode(
    global_data: Global, slice: Writer, width: Int = 8, height: Int = 8
) raises -> List[UInt8]:
    """Decode one image whose color slice is `slice`."""
    var bytes = slice.bytes()
    var decoded = Etc1sGlobal(global_data.bytes(len(bytes)), 1, False)
    return etc1s_image(decoded, 0, bytes, width, height, False)


def color(r5: Int, table: Int, step: Int) -> Int:
    """Return an 8-bit channel of a 5-bit value moved by an intensity."""
    var value = (r5 << 3) | (r5 >> 2)
    return max(0, min(255, value + etc1s_intensities()[table * 4 + step]))


def test_each_prediction_and_selector_source() raises:
    # One 2x2 group: a delta, then left, above and above left.
    var g = Global()
    var s = Writer()
    s.code(3 | (0 << 2) | (1 << 4) | (2 << 6), 9)
    # Block (0, 0): endpoint 0 + 1, and selector 1, which enters the
    # history.
    s.code(1, 1)
    s.code(1, 3)
    # Block (1, 0): selector 0.
    s.code(0, 3)
    # Block (0, 1): history entry 2, which holds selector 1.
    s.code(2 + 2, 3)
    # Block (1, 1): a run of three of the most recent history entry, 0.
    s.code(6, 3)
    s.code(0, 6)
    var image = decode(g, s)
    var bright = color(16, 7, 3)
    var dark = color(16, 7, 0)
    assert_equal(Int(image[0]), bright)
    assert_equal(Int(image[(0 * 8 + 4) * 4]), dark)
    assert_equal(Int(image[(4 * 8 + 0) * 4 + 1]), bright)
    assert_equal(Int(image[(4 * 8 + 4) * 4 + 2]), dark)
    assert_equal(Int(image[3]), 255)


def test_a_prediction_repeats_and_a_long_run_counts() raises:
    # Three groups across; the second repeats the first's symbol for two
    # more groups, and every block takes a delta of zero.
    var g = Global()
    var s = Writer()
    s.code(255, 9)
    s.code(0, 1)
    # A long run of selector 0 covers all twelve blocks.
    s.code(6, 3)
    s.code(63, 6)
    s.vlc(9, 7)
    s.code(0, 1)
    s.code(256, 9)
    s.vlc(0, 4)
    # The other ten blocks' deltas.
    for _ in range(10):
        s.code(0, 1)
    var image = decode(g, s, 24, 8)
    assert_equal(len(image), 24 * 8 * 4)
    assert_equal(Int(image[0]), color(31, 0, 0))


def test_an_endpoint_delta_wraps_around_the_codebook() raises:
    var g = Global()
    g.delta_bits = 2
    var s = Writer()
    s.code(3, 9)
    # 0 + 3 wraps to 1.
    s.code(3, 2)
    s.code(1, 3)
    var image = decode(g, s, 4, 4)
    assert_equal(Int(image[0]), color(16, 7, 3))


def test_malformed_slices_are_refused() raises:
    var cases: List[Int] = [0, 1, 2]
    var messages: List[String] = ["left edge", "top edge", "above left"]
    for index in range(3):
        var s = Writer()
        s.code(cases[index], 9)
        with assert_raises(contains=messages[index]):
            _ = decode(Global(), s)
    var wide = Global()
    wide.delta_bits = 3
    var far = Writer()
    far.code(3, 9)
    far.code(5, 3)
    with assert_raises(contains="delta is out of range"):
        _ = decode(wide, far)
    var run = Writer()
    run.code(3, 9)
    run.code(0, 1)
    run.code(6, 3)
    run.code(63, 6)
    run.vlc(100, 7)
    with assert_raises(contains="longer than the image"):
        _ = decode(Global(), run)
    var missing = Writer()
    missing.code(3, 9)
    missing.code(0, 1)
    missing.code(7, 3)
    with assert_raises(contains="not in the history"):
        _ = decode(Global(), missing)
    # A slice past the end of its level.
    var g = Global()
    g.image(100, 4)
    var decoded = Etc1sGlobal(g.bytes(), 1, False)
    with assert_raises(contains="outside its level"):
        _ = etc1s_image(decoded, 0, List[UInt8](length=4, fill=0), 4, 4, False)


def test_an_alpha_slice_writes_alpha() raises:
    var g = Global()
    var s = Writer()
    s.code(3, 9)
    s.code(0, 1)
    s.code(1, 3)
    var bytes = s.bytes()
    var level = bytes.copy()
    level.extend(bytes.copy())
    g.image(0, len(bytes), len(bytes))
    var decoded = Etc1sGlobal(g.bytes(), 1, True)
    var image = etc1s_image(decoded, 0, level, 4, 4, True)
    # The color is red 31 at step 3; alpha is its green, 0 at step 3.
    assert_equal(Int(image[0]), color(31, 0, 3))
    assert_equal(Int(image[3]), color(0, 0, 3))


def test_delta_coded_selectors() raises:
    var g = Global()
    g.raw_selectors = False
    var s = Writer()
    s.code(3, 9)
    s.code(0, 1)
    s.code(1, 3)
    assert_equal(Int(decode(g, s, 4, 4)[0]), color(31, 0, 3))
    # One selector needs no table.
    var one = Global()
    one.raw_selectors = False
    one.selectors = [255, 255, 255, 255]
    one.empty_selector_table = True
    var t = Writer()
    t.code(3, 9)
    t.code(0, 1)
    t.code(0, 3)
    assert_equal(Int(decode(one, t, 4, 4)[0]), color(31, 0, 3))


def test_malformed_global_data_is_refused() raises:
    with assert_raises(contains="shorter than its header"):
        _ = Etc1sGlobal(List[UInt8](length=19, fill=0), 1, False)
    var empty = Global()
    empty.endpoints = List[Int]()
    empty.image(0, 1)
    with assert_raises(contains="empty codebook"):
        _ = Etc1sGlobal(empty.bytes(), 1, False)
    var g = Global()
    g.image(0, 1)
    var bytes = g.bytes()
    _ = bytes.pop()
    with assert_raises(contains="shorter than it says"):
        _ = Etc1sGlobal(bytes, 1, False)
    var video = Global()
    video.images = [2, 0, 1, 0, 0]
    with assert_raises(contains="P-frames"):
        _ = Etc1sGlobal(video.bytes(), 1, False)
    var colorless = Global()
    colorless.image(0, 0)
    with assert_raises(contains="no color slice"):
        _ = Etc1sGlobal(colorless.bytes(), 1, False)
    var opaque = Global()
    opaque.image(0, 1)
    with assert_raises(contains="no alpha slice"):
        _ = Etc1sGlobal(opaque.bytes(), 1, True)
    var runless = Global()
    runless.image(0, 1)
    runless.empty_run_table = True
    with assert_raises(contains="slice table is empty"):
        _ = Etc1sGlobal(runless.bytes(), 1, False)
    var forgetful = Global()
    forgetful.image(0, 1)
    forgetful.history = 0
    with assert_raises(contains="history is empty"):
        _ = Etc1sGlobal(forgetful.bytes(), 1, False)
    var dull = Global()
    dull.image(0, 1)
    dull.empty_intensity_table = True
    with assert_raises(contains="endpoint codebook table is empty"):
        _ = Etc1sGlobal(dull.bytes(), 1, False)
    for flags in [1, 2]:
        var shared = Global()
        shared.image(0, 1)
        shared.selector_flags = flags
        with assert_raises(contains="selector codebooks are not supported"):
            _ = Etc1sGlobal(shared.bytes(), 1, False)
    var tableless = Global()
    tableless.image(0, 1)
    tableless.raw_selectors = False
    tableless.empty_selector_table = True
    with assert_raises(contains="selector codebook table is empty"):
        _ = Etc1sGlobal(tableless.bytes(), 1, False)


def tables_with(var first: Writer) -> List[UInt8]:
    """Return a slice tables section whose first table is already in
    `first`, and flat tables after it."""
    first.flat(1)
    first.flat(3)
    first.flat(6)
    first.put(4, 13)
    return first.bytes()


def test_malformed_huffman_tables_are_refused() raises:
    var cases = List[List[UInt8]]()
    var messages = List[String]()
    # Three codes of one bit are more than a code holds.
    var over = Writer()
    over.table([1, 1, 1])
    cases.append(tables_with(over^))
    messages.append("not a complete code")
    # No code-length codes.
    var none = Writer()
    none.put(4, 14)
    none.put(0, 5)
    cases.append(tables_with(none^))
    messages.append("code-length count")
    # A repeat before any length, a repeat of a zero length, a repeat
    # past the last symbol, and a zero run past it.
    var early = Writer()
    early.lengths_header(4)
    early.length_symbol(19)
    early.put(0, 2)
    cases.append(tables_with(early^))
    messages.append("repeats before a length")
    var zero = Writer()
    zero.lengths_header(4)
    zero.length_symbol(0)
    zero.length_symbol(19)
    zero.put(0, 2)
    cases.append(tables_with(zero^))
    messages.append("repeats a zero length")
    var past = Writer()
    past.lengths_header(3)
    past.length_symbol(2)
    past.length_symbol(19)
    past.put(0, 2)
    cases.append(tables_with(past^))
    messages.append("runs past its symbols")
    var run = Writer()
    run.lengths_header(2)
    run.length_symbol(17)
    run.put(0, 3)
    cases.append(tables_with(run^))
    messages.append("runs past its symbols")
    for index in range(len(cases)):
        var g = Global()
        g.image(0, 1)
        g.tables = cases[index].copy()
        with assert_raises(contains=messages[index]):
            _ = Etc1sGlobal(g.bytes(), 1, False)


def test_a_code_of_one_symbol_matches_only_its_bit() raises:
    # The prediction code has one symbol, whose code is a zero bit.
    var w = Writer()
    w.table([1])
    var g = Global()
    g.tables = tables_with(w^)
    var s = Writer()
    s.put(1, 1)
    with assert_raises(contains="no Huffman code matches"):
        _ = decode(g, s)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
