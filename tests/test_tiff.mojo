# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.tiff`: the files in `assets/tiff/`, from
`make_tiff.py`, read as three.js 0.180's `TIFFLoader` reads them with UTIF,
from `three_tiff.mjs`."""

from loaders.json import parse_json
from render.tiff import read_tiff
from std.math import inf, nan
from std.memory import bitcast
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def test_each_file_is_read_as_three_js_reads_it() raises:
    var doc = parse_json(Path("assets/tiff/tiff.json").read_text())
    var root = doc.root()
    # Files three.js reads that the decoder refuses on purpose; see the
    # module docstring.
    var refused: List[String] = [
        "no_width.tif",
        "no_height.tif",
        "not_tiff.tif",
        "tile_missing.tif",
        "lzw_bad_after_clear.tif",
        "short_strips.tif",
        "tile_counts.tif",
    ]
    for k in range(doc.length(root)):
        var name = doc.key(root, k)
        var want = doc.get(root, name)
        var bytes = Path("assets/tiff/" + name).read_bytes()
        if doc.has(want, "error") or name in refused:
            with assert_raises():
                _ = read_tiff(bytes)
            continue
        var texture = read_tiff(bytes)
        assert_equal(texture.width, doc.integer(doc.get(want, "width")), name)
        assert_equal(texture.height, doc.integer(doc.get(want, "height")), name)
        assert_true(texture.flip_y)
        var data = doc.get(want, "data")
        # The texture holds its chain of levels after the first.
        assert_true(len(texture.pixels) >= doc.length(data), name)
        for at in range(doc.length(data)):
            assert_equal(
                Int(texture.pixels[at]),
                doc.integer(doc.at(data, at)),
                name + " byte " + String(at),
            )


def _push16(mut bytes: List[UInt8], value: Int):
    bytes.append(UInt8(value & 255))
    bytes.append(UInt8((value >> 8) & 255))


def _push32(mut bytes: List[UInt8], value: Int):
    bytes.append(UInt8(value & 255))
    bytes.append(UInt8((value >> 8) & 255))
    bytes.append(UInt8((value >> 16) & 255))
    bytes.append(UInt8((value >> 24) & 255))


def _long(mut bytes: List[UInt8], tag: Int, value: Int):
    _push16(bytes, tag)
    _push16(bytes, 4)
    _push32(bytes, 1)
    _push32(bytes, value)


def _tiff(
    width: Int,
    height: Int,
    tags: List[Int],
    chunk: List[UInt8],
    tiles: Bool,
) -> List[UInt8]:
    var bytes = List[UInt8]()
    bytes.append(73)
    bytes.append(73)
    _push16(bytes, 42)
    _push32(bytes, 0)
    var chunk_at = len(bytes)
    for byte in chunk:
        bytes.append(byte)
    var ifd_at = len(bytes)
    bytes[4] = UInt8(ifd_at & 255)
    bytes[5] = UInt8((ifd_at >> 8) & 255)
    bytes[6] = UInt8((ifd_at >> 16) & 255)
    bytes[7] = UInt8((ifd_at >> 24) & 255)
    var count = 2 + len(tags) // 2
    if len(chunk) > 0:
        count += 2
    _push16(bytes, count)
    _long(bytes, 256, width)
    _long(bytes, 257, height)
    var index = 0
    while index < len(tags):
        _long(bytes, tags[index], tags[index + 1])
        index += 2
    if len(chunk) > 0:
        _long(bytes, 324 if tiles else 273, chunk_at)
        _long(bytes, 325 if tiles else 279, len(chunk))
    _push32(bytes, 0)
    return bytes^


def test_a_wrapped_size_is_refused() raises:
    # 4294967295 * 2147483649 wraps in a signed integer and is past the
    # pixel limit. The check divides before it multiplies.
    var huge = _tiff(4294967295, 2147483649, List[Int](), List[UInt8](), False)
    with assert_raises(contains="larger than this port decodes"):
        _ = read_tiff(huge)
    # Bits and samples whose product does not fit, on a one-pixel image.
    var wide = _tiff(
        1, 1, [258, 4294967295, 277, 4294967295], List[UInt8](), False
    )
    with assert_raises(contains="larger than this port decodes"):
        _ = read_tiff(wide)
    # A product that fits, and a buffer past the byte limit.
    var deep = _tiff(1, 1, [258, 64, 277, 1 << 28], List[UInt8](), False)
    with assert_raises(contains="larger than this port decodes"):
        _ = read_tiff(deep)
    # A zero factor still reaches the strip check. It is not an overflow.
    var zero = _tiff(1, 1, [258, 0], List[UInt8](), False)
    with assert_raises(contains="no strips or tiles"):
        _ = read_tiff(zero)


def test_a_tile_needs_a_positive_size() raises:
    var flat = _tiff(
        1, 1, [322, 0, 323, 1, 324, 0, 325, 0], List[UInt8](), False
    )
    with assert_raises(contains="no size"):
        _ = read_tiff(flat)
    var thin = _tiff(
        1, 1, [322, 1, 323, 0, 324, 0, 325, 0], List[UInt8](), False
    )
    with assert_raises(contains="no size"):
        _ = read_tiff(thin)


def _f32(mut bytes: List[UInt8], value: Float32):
    """Append a little-endian float."""
    _push32(bytes, Int(bitcast[DType.uint32](value)))


def test_a_float_gray_sample_past_2_63_is_byte_zero() raises:
    """A sample of 1e20 is a multiple of 2048, so its byte is zero."""
    var chunk = List[UInt8]()
    _f32(chunk, 1)
    _f32(chunk, Float32(1e20))
    _f32(chunk, inf[DType.float32]())
    _f32(chunk, nan[DType.float32]())
    _f32(chunk, -1)
    var file = _tiff(5, 1, [258, 32, 262, 1, 339, 3], chunk, False)
    var texture = read_tiff(file)
    assert_equal(texture.width, 5)
    assert_equal(texture.height, 1)
    var want = [255, 0, 0, 0, 2]
    for pixel in range(5):
        var at = pixel * 4
        assert_equal(Int(texture.pixels[at]), want[pixel])
        assert_equal(Int(texture.pixels[at + 1]), want[pixel])
        assert_equal(Int(texture.pixels[at + 2]), want[pixel])
        assert_equal(Int(texture.pixels[at + 3]), 255)


def test_a_deflate_strip_that_is_not_deflate_is_refused() raises:
    # Header and checksum are skipped. The byte between them is a reserved
    # DEFLATE block, so the failure is the stream, not its size.
    var chunk: List[UInt8] = [0, 0, 7, 0, 0, 0, 0, 0]
    var file = _tiff(1, 1, [258, 8, 259, 8, 262, 1], chunk, False)
    with assert_raises(contains="Reserved DEFLATE block type"):
        _ = read_tiff(file)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
