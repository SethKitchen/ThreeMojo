# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""`loaders.hdr_cube` against three.js's `HDRCubeTextureLoader`.

`assets/hdr_cube/three.json` holds the floats of the six faces in
`assets/hdr_cube/`, as three.js 0.180's `HDRLoader` reads them with
`FloatType`, in the loader's order.
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from loaders.hdr_cube import hdr_cube_texture_from, read_hdr_cube_texture
from loaders.json import parse_json
from render.cube_texture import CubeLayout, SEEN_FROM_OUTSIDE
from render.float_image import FloatImage
from render.srgb import LINEAR
from render.texture import BILINEAR, CLAMP, FLOAT_TYPE


def _paths() -> List[String]:
    """Return the six files, in three.js's order."""
    var out = List[String]()
    for name in ["px", "nx", "py", "ny", "pz", "nz"]:
        out.append("assets/hdr_cube/" + name + ".hdr")
    return out^


def test_faces_match_three_js() raises:
    var text = String(
        unsafe_from_utf8=open("assets/hdr_cube/three.json", "r").read_bytes()
    )
    var doc = parse_json(text)
    var cube = read_hdr_cube_texture(_paths())
    assert_equal(cube.size, 2)
    for face in range(6):
        var entry = doc.at(doc.root(), face)
        ref texture = cube.faces[face]
        assert_equal(texture.width, doc.integer(doc.get(entry, "width")))
        assert_equal(texture.texel_type, FLOAT_TYPE)
        assert_equal(texture.wrap_s, CLAMP)
        assert_equal(texture.wrap_t, CLAMP)
        assert_equal(texture.mag_filter, BILINEAR)
        assert_equal(texture.color_space, LINEAR)
        assert_equal(texture.levels, 1)
        var data = doc.get(entry, "data")
        assert_equal(len(texture.data), doc.length(data))
        for i in range(len(texture.data)):
            assert_equal(Float64(texture.data[i]), doc.number(doc.at(data, i)))


def test_layout_and_chain() raises:
    var inside = read_hdr_cube_texture(_paths())
    var outside = read_hdr_cube_texture(_paths(), SEEN_FROM_OUTSIDE, True)
    # The first two faces trade places, and the rest stay. With a chain,
    # the first 16 floats are the full size.
    for i in range(16):
        assert_equal(outside.faces[0].data[i], inside.faces[1].data[i])
        assert_equal(outside.faces[1].data[i], inside.faces[0].data[i])
        assert_equal(outside.faces[2].data[i], inside.faces[2].data[i])
    assert_true(outside.faces[0].levels > 1)


def test_refusals() raises:
    var five = _paths()
    _ = five.pop()
    with assert_raises(contains="six files"):
        _ = read_hdr_cube_texture(five)
    with assert_raises(contains="six images"):
        _ = hdr_cube_texture_from(List[FloatImage]())
    var images = List[FloatImage]()
    for _ in range(6):
        images.append(FloatImage(1, 1, [Float32(1), 1, 1, 1]))
    with assert_raises(contains="SEEN_FROM_INSIDE or SEEN_FROM_OUTSIDE"):
        _ = hdr_cube_texture_from(images, CubeLayout(7))
    images[3] = FloatImage(2, 1, [Float32(1), 1, 1, 1, 1, 1, 1, 1])
    with assert_raises():
        _ = hdr_cube_texture_from(images)
    var missing = _paths()
    missing[2] = "assets/hdr_cube/missing.hdr"
    with assert_raises():
        _ = read_hdr_cube_texture(missing)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
