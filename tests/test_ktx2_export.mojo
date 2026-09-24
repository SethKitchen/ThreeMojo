# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""`exporters.ktx2` against three.js's `KTX2Exporter`.

`assets/ktx2_export/three.json` holds the files that three.js 0.180
writes for 2D and 3D data textures of bytes, floats and halves, with
four, two and one channels. Texel `t`, channel `c` holds
`(t * 37 + c * 71 + 5) % 256` as a byte, or
`((t * 37 + c * 71) % 200 - 100) / 8` as a float.
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from exporters.ktx2 import export_ktx2, export_ktx2_volume
from loaders.gltf import decode_base64
from loaders.json import parse_json
from render.ktx2 import read
from render.srgb import LINEAR, SRGB
from render.texture import (
    BILINEAR,
    CLAMP,
    TexelType,
    Texture,
    float_texture,
)
from render.volume_texture import Data3DTexture, VolumeImage

comptime WRITER = "three.js 180"


def _bytes(texels: Int, channels: Int) -> List[UInt8]:
    """Return RGBA bytes, the first `channels` of each from the formula
    and the rest zero."""
    var out = List[UInt8](length=texels * 4, fill=0)
    for t in range(texels):
        for c in range(channels):
            out[t * 4 + c] = UInt8((t * 37 + c * 71 + 5) % 256)
    return out^


def _floats(texels: Int, channels: Int) -> List[Float32]:
    """Return RGBA floats, the first `channels` of each from the formula
    and the rest zero."""
    var out = List[Float32](length=texels * 4, fill=0)
    for t in range(texels):
        for c in range(channels):
            out[t * 4 + c] = Float32((t * 37 + c * 71) % 200 - 100) / 8
    return out^


def test_files_match_three_js() raises:
    var text = String(
        unsafe_from_utf8=open("assets/ktx2_export/three.json", "r").read_bytes()
    )
    var doc = parse_json(text)
    var root = doc.root()
    for i in range(doc.length(root)):
        var entry = doc.at(root, i)
        var width = doc.integer(doc.get(entry, "width"))
        var height = doc.integer(doc.get(entry, "height"))
        var depth = doc.integer(doc.get(entry, "depth"))
        var type = doc.string(doc.get(entry, "type"))
        var channels = doc.integer(doc.get(entry, "channels"))
        var space = (
            SRGB if doc.string(doc.get(entry, "space")) == "srgb" else LINEAR
        )
        var expected = decode_base64(doc.string(doc.get(entry, "bytes")))
        var texels = width * height * max(depth, 1)
        var half = type == "half"
        var got: List[UInt8]
        if depth > 0:
            var image = VolumeImage.of_bytes(
                width, height, depth, _bytes(texels, channels)
            ) if type == "byte" else VolumeImage.of_floats(
                width, height, depth, _floats(texels, channels)
            )
            var volume = Data3DTexture(image^, color_space=space)
            got = export_ktx2_volume(volume, channels, half, WRITER)
        elif type == "byte":
            var texture = Texture(
                width,
                height,
                _bytes(texels, channels),
                CLAMP,
                BILINEAR,
                space,
                False,
            )
            got = export_ktx2(texture, channels, half, WRITER)
        else:
            var texture = float_texture(
                width, height, _floats(texels, channels)
            )
            got = export_ktx2(texture, channels, half, WRITER)
        assert_equal(len(got), len(expected))
        for k in range(len(got)):
            assert_equal(got[k], expected[k])


def test_files_read_back() raises:
    # A byte texture with a chain: the full size is written, and read
    # back to the same texels.
    var texture = Texture(3, 2, _bytes(6, 4), CLAMP, BILINEAR, SRGB, True)
    var back = read(export_ktx2(texture)).texture()
    assert_equal(back.color_space, SRGB)
    for k in range(24):
        assert_equal(back.pixels[k], texture.pixels[k])
    var floats = float_texture(3, 2, _floats(6, 4))
    var again = read(export_ktx2(floats, 2)).texture()
    for t in range(6):
        assert_equal(again.data[t * 4], floats.data[t * 4])
        assert_equal(again.data[t * 4 + 1], floats.data[t * 4 + 1])
        assert_equal(again.data[t * 4 + 3], 1)


def test_refusals() raises:
    var texture = Texture(3, 2, _bytes(6, 4), CLAMP, BILINEAR, SRGB, False)
    with assert_raises(contains="1, 2 or 4 channels"):
        _ = export_ktx2(texture, 3)
    with assert_raises(contains="only a float texture"):
        _ = export_ktx2(texture, 4, True)
    with assert_raises(contains="blank texture"):
        _ = export_ktx2(Texture())
    var floats = float_texture(3, 2, _floats(6, 4))
    floats.color_space = SRGB
    with assert_raises(contains="must be LINEAR"):
        _ = export_ktx2(floats)
    var odd = Texture(3, 2, _bytes(6, 4), CLAMP, BILINEAR, SRGB, False)
    odd.texel_type = TexelType(9)
    with assert_raises(contains="bytes or floats"):
        _ = export_ktx2(odd)
    var unknown = Texture(3, 2, _bytes(6, 4), CLAMP, BILINEAR, SRGB, False)
    unknown.color_space.value = 9
    with assert_raises(contains="SRGB or LINEAR"):
        _ = export_ktx2(unknown)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
