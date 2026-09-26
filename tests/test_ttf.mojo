# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.ttf`: the fonts in `assets/ttf/`, from
`make_fonts.py` and three.js's own `kenpixel.ttf`, read as three.js 0.180's
`TTFLoader` reads them with opentype.js, from `three_ttf.mjs`."""

from loaders.json import JsonDocument, NULL, NUMBER, OBJECT, STRING, parse_json
from loaders.ttf import read_ttf, ttf_json
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def _same(
    got: JsonDocument, a: Int, want: JsonDocument, b: Int, path: String
) raises:
    """Assert two JSON values are equal, objects in any order.

    Args:
        got: The port's document.
        a: Its value.
        want: three.js's document.
        b: Its value.
        path: The path, for a failure.
    """
    var kind = want.kind(b)
    assert_true(got.kind(a) == kind, path)
    if kind == OBJECT:
        assert_equal(got.length(a), want.length(b), path)
        for k in range(want.length(b)):
            var key = want.key(b, k)
            assert_true(got.has(a, key), path + "." + key)
            _same(
                got, got.get(a, key), want, want.get(b, key), path + "." + key
            )
    elif kind == NUMBER:
        assert_equal(got.number(a), want.number(b), path)
    elif kind == STRING:
        assert_equal(got.string(a), want.string(b), path)


def test_each_font_is_read_as_three_js_reads_it() raises:
    var doc = parse_json(Path("assets/ttf/ttf.json").read_text())
    for name in [
        "curves.ttf",
        "astral.ttf",
        "kenpixel.ttf",
        "edges.ttf",
        "bare.ttf",
        "zero.ttf",
    ]:
        var bytes = Path("assets/ttf/" + name).read_bytes()
        for reversed in [False, True]:
            var key = name + (" reversed" if reversed else "")
            var got = parse_json(ttf_json(bytes, reversed))
            _same(got, got.root(), doc, doc.get(doc.root(), key), key)


def test_apple_s_signature_is_true_type() raises:
    var edges = Path("assets/ttf/edges.ttf").read_bytes()
    var apple = Path("assets/ttf/true.ttf").read_bytes()
    assert_equal(ttf_json(apple, False), ttf_json(edges, False))


def test_a_font_reads_into_a_font() raises:
    var font = read_ttf("assets/ttf/curves.ttf")
    assert_equal(font.family_name, "Curves Regular")


def test_a_font_three_js_cannot_read_is_refused() raises:
    var cases: List[String] = [
        "far_component.ttf",
        "names glyph",
        "loop.ttf",
        "nest too deep",
        "flags.ttf",
        "Bad flags",
        "matched.ttf",
        "Matched points out of range",
        "few_glyphs.ttf",
        "names no glyph",
        "otto.ttf",
        "only TrueType outlines",
        "short.ttf",
        "runs past the end",
        "no_post.ttf",
        "has no post table",
        "no_glyf.ttf",
        "TrueType or CFF outlines",
        "mac_cmap.ttf",
        "No valid cmap",
        "format_6.ttf",
        "Only format 4 and 12",
        "surrogate.ttf",
        "is a surrogate",
        "no_loca.ttf",
        "TrueType or CFF outlines",
        "matched_second.ttf",
        "Matched points out of range",
    ]
    for at in range(0, len(cases), 2):
        var bytes = Path("assets/ttf/broken/" + cases[at]).read_bytes()
        with assert_raises(contains=cases[at + 1]):
            _ = ttf_json(bytes, False)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
