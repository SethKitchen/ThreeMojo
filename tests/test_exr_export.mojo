# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""`exporters.exr` against three.js's `EXRExporter`.

`assets/exr_export/three.json` holds the files that three.js r187
writes for data textures, with each of its five compressions and both
sample types. `assets/exr_export/three_exr_export.mjs` writes it. The
texels come from a xorshift generator and from smooth images that are
the same here and in node. A large file is held by its size and
SHA-256.
"""

from std.math import floor, isnan
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from std.utils.numerics import inf, nan

from exporters.exr import export_exr, export_exr_half, export_exr_image
from loaders.bytes import decode_base64
from loaders.json import parse_json
from render.exr import (
    FLOAT_SAMPLES,
    HALF_SAMPLES,
    NO_COMPRESSION,
    PIZ_COMPRESSION,
    PXR24_COMPRESSION,
    RLE_COMPRESSION,
    UINT_SAMPLES,
    ZIPS_COMPRESSION,
    ZIP_COMPRESSION,
    ExrCompression,
    ExrPixelType,
    decode,
)
from render.float_image import FloatImage
from tools._sha256 import sha256_hex


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


def _smooth(width: Int, height: Int, seed: Int) -> List[Float32]:
    """Return the script's `smooth`."""
    var out = List[Float32]()
    for y in range(height):
        for x in range(width):
            var run = x < (seed % 7) + 3
            var wave = abs(Float64((y + seed) % 6) / 3 - 1)
            var ramp = (
                floor(64 * (Float64(x) / Float64(width) + 0.5 * wave) + 0.5)
                / 64
            )
            var rise = floor(Float64(256 * y) / Float64(height) + 0.5) / 64
            out.append(Float32(0.25 if run else ramp))
            out.append(Float32(0.25 if run else rise))
            out.append(Float32(Float64((x + y + seed) % 9) / 8))
            out.append(1)
    return out^


def _fine(width: Int, height: Int, seed: Int) -> List[Float32]:
    """Return the script's `fine`."""
    var out = List[Float32]()
    for y in range(height):
        for x in range(width):
            var h0 = Float64((x * 7919 + y * 104729 + seed) % 65521)
            var h1 = Float64((x * 104729 + y * 7919 + seed) % 65521)
            var h2 = Float64((x * 31337 + y * 271 + seed) % 65521)
            var fx = Float64(x)
            var fy = Float64(y)
            out.append(Float32(fx * 0.0123 + fy * 0.0071 + h0 * 1e-8))
            out.append(
                Float32(
                    (fx - 192) * (fx - 192) * 0.0001 - fy * 0.02 + h1 * 1e-8
                )
            )
            out.append(Float32(fx * fy * 0.0002 + 0.5 + h2 * 1e-8))
            out.append(1)
    return out^


def _texels(input: String, width: Int, height: Int, seed: Int) -> List[Float32]:
    """Return the float texels of one of the script's inputs."""
    if input == "zero":
        return List[Float32](length=width * height * 4, fill=0)
    if input == "smooth":
        return _smooth(width, height, seed)
    if input == "fine":
        return _fine(width, height, seed)
    return _floats(width * height * 4, seed)


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
        var input = doc.string(doc.get(entry, "input"))
        var name = doc.string(doc.get(entry, "type"))
        var compression = ExrCompression(code)
        var type = FLOAT_SAMPLES if name == "float" else HALF_SAMPLES
        var n = width * height * 4
        var got: List[UInt8]
        var plain: List[UInt8]
        if code == -1:
            # three.js's defaults: ZIP and halves.
            got = export_exr(width, height, _texels(input, width, height, seed))
            plain = export_exr(
                width,
                height,
                _texels(input, width, height, seed),
                NO_COMPRESSION,
            )
        elif input == "half":
            got = export_exr_half(
                width, height, _halves(n, seed), compression, type
            )
            plain = export_exr_half(
                width, height, _halves(n, seed), NO_COMPRESSION, type
            )
        else:
            var texels = _texels(input, width, height, seed)
            got = export_exr(width, height, texels, compression, type)
            plain = export_exr(width, height, texels, NO_COMPRESSION, type)
        if doc.has(entry, "bytes"):
            var expected = decode_base64(doc.string(doc.get(entry, "bytes")))
            assert_equal(len(got), len(expected))
            for i in range(len(expected)):
                assert_equal(got[i], expected[i])
        else:
            assert_equal(len(got), doc.integer(doc.get(entry, "size")))
            assert_equal(
                sha256_hex(Span(got)), doc.string(doc.get(entry, "sha256"))
            )
        # The file reads back to the values of the one with no
        # compression.
        _same_image(decode(got), decode(plain))


def test_images_read_back() raises:
    var pixels = List[Float32]()
    for i in range(5 * 21 * 4):
        pixels.append(Float32(i % 41) / 4)
    var image = FloatImage(5, 21, pixels.copy())
    for compression in [
        NO_COMPRESSION,
        RLE_COMPRESSION,
        ZIPS_COMPRESSION,
        ZIP_COMPRESSION,
        PIZ_COMPRESSION,
    ]:
        _same_image(
            decode(export_exr_image(image, compression, FLOAT_SAMPLES)), image
        )
    # Halves hold these values too.
    _same_image(decode(export_exr_image(image)), image)


def test_refusals() raises:
    var four: List[Float32] = [1, 2, 3, 4]
    with assert_raises(contains="a width and a height"):
        _ = export_exr(0, 1, List[Float32]())
    with assert_raises(contains="larger than this port"):
        _ = export_exr(1 << 31, 1 << 31, List[Float32]())
    with assert_raises(contains="a width and a height"):
        _ = export_exr(1, 0, List[Float32]())
    with assert_raises(contains="not 4 values"):
        _ = export_exr(2, 1, four)
    with assert_raises(contains="none, RLE, ZIPS, ZIP or PIZ"):
        _ = export_exr(1, 1, four, PXR24_COMPRESSION)
    with assert_raises(contains="none, RLE, ZIPS, ZIP or PIZ"):
        _ = export_exr(1, 1, four, ExrCompression(-1))
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
