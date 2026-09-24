# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""`exporters.exr` against three.js's `EXRExporter`.

`assets/exr_export/three.json` holds the files that three.js 0.180
writes for data textures of four sizes, float and half, with each
compression and sample type. The texels come from a xorshift generator
that is the same here and in node.
"""

from std.math import isnan
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from std.utils.numerics import inf, nan

from exporters.exr import export_exr, export_exr_half, export_exr_image
from loaders.gltf import decode_base64
from loaders.json import parse_json
from render.exr import (
    FLOAT_SAMPLES,
    HALF_SAMPLES,
    NO_COMPRESSION,
    PIZ_COMPRESSION,
    UINT_SAMPLES,
    ZIPS_COMPRESSION,
    ZIP_COMPRESSION,
    ExrCompression,
    ExrPixelType,
    decode,
)
from render.float_image import FloatImage


struct _Random(Movable):
    """The xorshift generator of the fixture's script."""

    var x: UInt32

    def __init__(out self, seed: Int):
        self.x = UInt32(seed)

    def next(mut self) -> Int:
        self.x ^= self.x << 13
        self.x ^= self.x >> 17
        self.x ^= self.x << 5
        return Int(self.x)


def _special() -> List[Float64]:
    """Return the script's special values."""
    return [
        0.0,
        -0.0,
        1.0,
        -1.0,
        0.5,
        65504.0,
        70000.0,
        -1e9,
        1e-6,
        6e-8,
        1e-10,
        nan[DType.float64](),
        inf[DType.float64](),
        -inf[DType.float64](),
        3.14159,
        0.1,
    ]


def _floats(n: Int, seed: Int) -> List[Float32]:
    """Return the script's `floats`."""
    var special = _special()
    var random = _Random(seed)
    var out = List[Float32]()
    for _ in range(n):
        var r = random.next()
        if r % 4 == 0:
            out.append(Float32(special[random.next() % len(special)]))
        else:
            out.append(
                Float32(Float64(random.next() % 200001 - 100000) / 1000.0)
            )
    return out^


def _halves(n: Int, seed: Int) -> List[UInt16]:
    """Return the script's `halves`."""
    var random = _Random(seed)
    var out = List[UInt16]()
    for _ in range(n):
        out.append(UInt16(random.next() & 0xFFFF))
    return out^


def _same_image(a: FloatImage, b: FloatImage) raises:
    """Assert that two images hold the same values, NaN for NaN."""
    assert_equal(a.width, b.width)
    assert_equal(a.height, b.height)
    for i in range(len(a.pixels)):
        if isnan(a.pixels[i]):
            assert_true(isnan(b.pixels[i]))
        else:
            assert_equal(a.pixels[i], b.pixels[i])


def test_files_match_three_js() raises:
    var text = String(
        StringSlice(
            unsafe_from_utf8=open(
                "assets/exr_export/three.json", "r"
            ).read_bytes()
        )
    )
    var doc = parse_json(text)
    var root = doc.root()
    for c in range(doc.length(root)):
        var entry = doc.at(root, c)
        var width = doc.integer(doc.get(entry, "width"))
        var height = doc.integer(doc.get(entry, "height"))
        var seed = doc.integer(doc.get(entry, "seed"))
        var code = doc.integer(doc.get(entry, "compression"))
        var name = doc.string(doc.get(entry, "type"))
        var expected = decode_base64(doc.string(doc.get(entry, "bytes")))
        var compression = ExrCompression(code)
        var type = FLOAT_SAMPLES if name == "float" else HALF_SAMPLES
        var n = width * height * 4
        var got: List[UInt8]
        var plain: List[UInt8]
        if code == -1:
            got = export_exr(width, height, _floats(n, seed))
            compression = ZIP_COMPRESSION
            plain = export_exr(width, height, _floats(n, seed), NO_COMPRESSION)
        elif doc.string(doc.get(entry, "input")) == "float":
            got = export_exr(width, height, _floats(n, seed), compression, type)
            plain = export_exr(
                width, height, _floats(n, seed), NO_COMPRESSION, type
            )
        else:
            got = export_exr_half(
                width, height, _halves(n, seed), compression, type
            )
            plain = export_exr_half(
                width, height, _halves(n, seed), NO_COMPRESSION, type
            )
        _same_blocks(got, expected, width, height, compression, type)
        # The file reads back to the values of the one with no
        # compression.
        _same_image(decode(got), decode(plain))


def _offset(bytes: List[UInt8], at: Int, count: Int) -> Int:
    """Return a little-endian number."""
    var value = 0
    for k in range(count):
        value |= Int(bytes[at + k]) << (8 * k)
    return value


def _same_blocks(
    got: List[UInt8],
    expected: List[UInt8],
    width: Int,
    height: Int,
    compression: ExrCompression,
    type: ExrPixelType,
) raises:
    """Assert that a file is three.js's, but for the blocks that three.js
    writes wrong: a block not smaller than its lines, and the short last
    block of a ZIP file."""
    var table = _header_length(expected)
    assert_equal(_header_length(got), table)
    for i in range(table):
        assert_equal(got[i], expected[i])
    var lines = 16 if compression == ZIP_COMPRESSION else 1
    var blocks = (height + lines - 1) // lines
    for b in range(blocks):
        var mine = _offset(got, table + 8 * b, 8)
        var theirs = _offset(expected, table + 8 * b, 8)
        assert_equal(_offset(got, mine, 4), b * lines)
        assert_equal(_offset(expected, theirs, 4), b * lines)
        var size = _offset(expected, theirs + 4, 4)
        var real = min(lines, height - b * lines) * width * 4 * 2 * type.value
        var mine_size = _offset(got, mine + 4, 4)
        if compression == NO_COMPRESSION or (
            size < real and real == lines * width * 4 * 2 * type.value
        ):
            assert_equal(mine_size, size)
            for i in range(size):
                assert_equal(got[mine + 8 + i], expected[theirs + 8 + i])
        else:
            assert_true(mine_size <= real)
    var last = _offset(got, table + 8 * (blocks - 1), 8)
    assert_equal(len(got), last + 8 + _offset(got, last + 4, 4))


def _header_length(bytes: List[UInt8]) -> Int:
    """Return where the offset table of a file starts: after the header's
    two zero bytes that end the channel list and the header."""
    # Past the magic number and the version, then each attribute.
    var at = 8
    while bytes[at] != 0:
        while bytes[at] != 0:
            at += 1
        at += 1
        while bytes[at] != 0:
            at += 1
        at += 1
        var size = (
            Int(bytes[at])
            | (Int(bytes[at + 1]) << 8)
            | (Int(bytes[at + 2]) << 16)
            | (Int(bytes[at + 3]) << 24)
        )
        at += 4 + size
    return at + 1


def test_images_read_back() raises:
    var pixels = List[Float32]()
    for i in range(5 * 21 * 4):
        pixels.append(Float32(i % 41) / 4)
    var image = FloatImage(5, 21, pixels.copy())
    for compression in [NO_COMPRESSION, ZIPS_COMPRESSION, ZIP_COMPRESSION]:
        _same_image(
            decode(export_exr_image(image, compression, FLOAT_SAMPLES)), image
        )
    # Halves hold these values too.
    _same_image(decode(export_exr_image(image)), image)


def test_refusals() raises:
    var four: List[Float32] = [1, 2, 3, 4]
    with assert_raises(contains="a width and a height"):
        _ = export_exr(0, 1, List[Float32]())
    with assert_raises(contains="a width and a height"):
        _ = export_exr(1, 0, List[Float32]())
    with assert_raises(contains="not 4 values"):
        _ = export_exr(2, 1, four)
    with assert_raises(contains="none, ZIPS or ZIP"):
        _ = export_exr(1, 1, four, PIZ_COMPRESSION)
    with assert_raises(contains="HALF or FLOAT"):
        _ = export_exr(1, 1, four, ZIP_COMPRESSION, UINT_SAMPLES)
    with assert_raises(contains="HALF or FLOAT"):
        _ = export_exr_half(
            1,
            1,
            List[UInt16](length=4, fill=0),
            ZIP_COMPRESSION,
            ExrPixelType(7),
        )
    with assert_raises(contains="four values"):
        _ = export_exr_image(FloatImage(2, 2, four.copy()))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
