# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.tiff`: the files in `assets/tiff/`, from
`make_tiff.py`, read as three.js 0.180's `TIFFLoader` reads them with UTIF,
from `three_tiff.mjs`."""

from loaders.json import parse_json
from render.tiff import read_tiff
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
