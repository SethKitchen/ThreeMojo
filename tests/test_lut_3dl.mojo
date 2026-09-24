# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.lut_3dl` and `loaders.lut_image`.

`assets/lut/fixture.json` is the texture data three.js 0.180's
`LUT3dlLoader` gives for `assets/lut/table.3dl` and `assets/lut/small.3dl`
in node, as bytes and as floats. `small.3dl` has a grid of three values,
which three.js reads as an entry too, and one entry past its size, which
wraps. `row.png` and `column.png` hold one table of size three as a row
and as a column of squares.
"""

from loaders.json import JsonDocument, parse_json
from loaders.lut_3dl import lut_3dl_byte, parse_lut_3dl, read_lut_3dl
from loaders.lut_image import lut_image_from, parse_lut_image, read_lut_image
from render.png import DecodedImage
from render.srgb import SRGB
from render.texture import FLOAT_TYPE, UNSIGNED_BYTE_TYPE, TexelType
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def near(got: Float64, want: Float64) raises:
    """Assert two numbers agree to a `Float32`."""
    var scale = max(Float64(1), abs(want))
    if not (abs(got - want) <= 1e-6 * scale):
        raise Error("got " + String(got) + ", want " + String(want))


def check(file: String) raises:
    """Compare one table with three.js."""
    var doc = parse_json(Path("assets/lut/fixture.json").read_text())
    var want = doc.get(doc.root(), file)
    var bytes = read_lut_3dl("assets/lut/" + file)
    var wb = doc.get(want, "byte")
    assert_equal(bytes.size, doc.integer(doc.get(wb, "size")))
    var data = doc.get(wb, "data")
    ref pixels = bytes.texture.image.pixels
    assert_equal(len(pixels), doc.length(data))
    for i in range(len(pixels)):
        assert_equal(Int(pixels[i]), doc.integer(doc.at(data, i)))
    var floats = read_lut_3dl("assets/lut/" + file, FLOAT_TYPE)
    var wf = doc.get(doc.get(want, "float"), "data")
    ref values = floats.texture.image.data
    assert_equal(len(values), doc.length(wf))
    for i in range(len(values)):
        near(Float64(values[i]), doc.number(doc.at(wf, i)))


def test_the_tables_match_three_js() raises:
    check("table.3dl")
    check("small.3dl")


def test_3dl_edges_and_refusals() raises:
    # A grid of spaces is one entry of zero; the largest value, a half,
    # scales up to one.
    var single = parse_lut_3dl("   \n0.5 0.25 0\n")
    assert_equal(single.size, 1)
    assert_equal(single.max_bit_value, 0.5)
    assert_equal(Int(single.texture.image.pixels[0]), 255)
    assert_equal(lut_3dl_byte(-1.5), 255)
    assert_equal(lut_3dl_byte(256.7), 0)
    with assert_raises(contains="not valid"):
        _ = parse_lut_3dl("0 1\n", TexelType(5))
    with assert_raises(contains="missing grid"):
        _ = parse_lut_3dl("# none\n1.5 2 3\n")
    with assert_raises(contains="inconsistent grid"):
        _ = parse_lut_3dl("0 1 3\n")
    with assert_raises(contains="is not a number"):
        _ = parse_lut_3dl("0 1\n1e 2 3\n")
    with assert_raises(contains="is not a number"):
        _ = parse_lut_3dl("0 1\n1e999 2 3\n")
    with assert_raises(contains="is not a number"):
        _ = parse_lut_3dl("99999999999999999999999 1\n")
    with assert_raises(contains="not above zero"):
        _ = parse_lut_3dl("0 1\n0 0 0\n")
    with assert_raises():
        _ = read_lut_3dl("assets/lut/missing.3dl")


def test_images() raises:
    var row = read_lut_image("assets/lut/row.png")
    var column = read_lut_image("assets/lut/column.png")
    assert_equal(row.size, 3)
    assert_equal(column.size, 3)
    assert_equal(row.texture.image.pixels, column.texture.image.pixels)
    # Blue two, green one, red two: the texel at (2, 1, 2).
    var at = ((2 * 3 + 1) * 3 + 2) * 4
    assert_equal(Int(column.texture.image.pixels[at]), 200)
    assert_equal(Int(column.texture.image.pixels[at + 1]), 100)
    assert_equal(Int(column.texture.image.pixels[at + 2]), 200)
    with assert_raises(contains="size below one"):
        _ = parse_lut_image([], 0)
    with assert_raises(contains="needs 8 texels"):
        _ = parse_lut_image([0, 0, 0, 0], 2)
    var tall = DecodedImage(2, 3, List[UInt8](length=24, fill=0), SRGB)
    with assert_raises(contains="column"):
        _ = lut_image_from(tall)
    var wide = DecodedImage(3, 2, List[UInt8](length=24, fill=0), SRGB)
    with assert_raises(contains="row"):
        _ = lut_image_from(wide)
    with assert_raises(contains="size below one"):
        _ = lut_image_from(DecodedImage(0, 0, List[UInt8](), SRGB))
    with assert_raises():
        _ = read_lut_image("assets/lut/missing.png")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
