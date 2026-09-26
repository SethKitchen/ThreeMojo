# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.pvr`: the PVR files in `assets/pvrtc/` read as three.js
0.180's `PVRLoader` reads them, from `assets/pvrtc/three_pvr.mjs`, and their
levels decoded as `PVRTDecompress.cpp` decodes them."""

from loaders.json import parse_json
from render.compressed_texture import (
    RGB_PVRTC_2BPPV1_FORMAT,
    RGB_PVRTC_4BPPV1_FORMAT,
    RGBA_PVRTC_2BPPV1_FORMAT,
    RGBA_PVRTC_4BPPV1_FORMAT,
    CompressedFormat,
    decode_compressed,
)
from render.pvr import read
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def test_each_file_is_read_as_three_js_reads_it() raises:
    var doc = parse_json(Path("assets/pvrtc/pvr.json").read_text())
    # three.js's format numbers, from 35840, and this port's formats.
    var formats: List[CompressedFormat] = [
        RGB_PVRTC_4BPPV1_FORMAT,
        RGB_PVRTC_2BPPV1_FORMAT,
        RGBA_PVRTC_4BPPV1_FORMAT,
        RGBA_PVRTC_2BPPV1_FORMAT,
    ]
    for name in ["mips.pvr", "cube.pvr", "v2.pvr"]:
        var image = read(Path("assets/pvrtc/" + name).read_bytes())
        var want = doc.get(doc.root(), name)
        assert_true(
            image.format
            == formats[doc.integer(doc.get(want, "format")) - 35840]
        )
        assert_equal(image.width, doc.integer(doc.get(want, "width")))
        assert_equal(image.levels, doc.integer(doc.get(want, "mipmapCount")))
        assert_equal(image.faces == 6, doc.boolean(doc.get(want, "isCubemap")))
        var mipmaps = doc.get(want, "mipmaps")
        assert_equal(len(image.mipmaps), doc.length(mipmaps))
        for k in range(len(image.mipmaps)):
            var data = doc.get(doc.at(mipmaps, k), "data")
            assert_equal(len(image.mipmaps[k]), doc.length(data))
            for at in range(len(image.mipmaps[k])):
                assert_equal(
                    Int(image.mipmaps[k][at]), doc.integer(doc.at(data, at))
                )


def test_a_level_decodes_as_the_reference_decodes_it() raises:
    var doc = parse_json(Path("assets/pvrtc/reference.json").read_text())
    var mips = read(Path("assets/pvrtc/mips.pvr").read_bytes())
    var texture = mips.texture(level=1)
    var want = doc.get(doc.root(), "4bpp_4x4")
    for at in range(len(texture.pixels)):
        assert_equal(Int(texture.pixels[at]), doc.integer(doc.at(want, at)))
    # The RGB forms are opaque.
    var cube = read(Path("assets/pvrtc/cube.pvr").read_bytes())
    var opaque = decode_compressed(8, 8, cube.mipmaps[5], cube.format)
    for at in range(3, len(opaque.pixels), 4):
        assert_equal(Int(opaque.pixels[at]), 255)


def _header(words: List[Int]) -> List[UInt8]:
    """Return thirteen little-endian words.

    Args:
        words: The words, the rest zero.

    Returns:
        The bytes.
    """
    var out = List[UInt8](length=52, fill=0)
    for k in range(len(words)):
        for byte in range(4):
            out[k * 4 + byte] = UInt8((words[k] >> (8 * byte)) & 0xFF)
    return out^


def test_what_three_js_cannot_read_is_refused() raises:
    with assert_raises(contains="shorter than its header"):
        _ = read(List[UInt8](length=20, fill=0))
    with assert_raises(contains="neither version"):
        _ = read(_header([]))
    with assert_raises(contains="pixel format 7 is not PVRTC"):
        _ = read(_header([0x03525650, 0, 7]))
    var v2: List[Int] = [52, 8, 8, 0, 13, 0, 0, 0, 0, 0, 0, 0x21525650, 1]
    with assert_raises(contains="format 13 is not PVRTC"):
        _ = read(_header(v2))
    # Four bits without alpha is RGB.
    v2[4] = 25
    var rgb = _header(v2)
    rgb.extend(List[UInt8](length=32, fill=0))
    assert_true(read(rgb).format == RGB_PVRTC_4BPPV1_FORMAT)
    v2[4] = 24
    var two = _header(v2)
    two.extend(List[UInt8](length=32, fill=0))
    assert_true(read(two).format == RGB_PVRTC_2BPPV1_FORMAT)
    var v3: List[Int] = [0x03525650, 0, 3, 0, 0, 0, 8, 0, 1, 1, 1, 1, 0]
    with assert_raises(contains="must be positive"):
        _ = read(_header(v3))
    v3[6] = 0
    v3[7] = 8
    with assert_raises(contains="must be positive"):
        _ = read(_header(v3))
    v3[6] = 8
    v3[10] = 0
    with assert_raises(contains="must be positive"):
        _ = read(_header(v3))
    v3[10] = 1
    v3[7] = 12
    with assert_raises(contains="powers of two"):
        _ = read(_header(v3))
    v3[6] = 12
    v3[7] = 8
    with assert_raises(contains="powers of two"):
        _ = read(_header(v3))
    v3[6] = 8
    v3[11] = 5
    with assert_raises(contains="more levels"):
        _ = read(_header(v3))
    v3[11] = 0
    with assert_raises(contains="more levels"):
        _ = read(_header(v3))
    v3[11] = 1
    with assert_raises(contains="ends before its last level"):
        _ = read(_header(v3))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
