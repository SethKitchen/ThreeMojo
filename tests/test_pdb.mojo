# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.pdb`: `assets/pdb/fixture.pdb` read as three.js
0.180's `PDBLoader` reads it, from `assets/pdb/three_pdb.mjs`."""

from core.buffer_geometry import COLOR, POSITION
from loaders.json import JsonDocument, parse_json
from loaders.pdb import cpk_color, parse_pdb, read_pdb
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def _reference() raises -> JsonDocument:
    """Return what three.js made of the fixture."""
    return parse_json(Path("assets/pdb/pdb.json").read_text())


def _same(
    got: List[Float32], doc: JsonDocument, key: String, atol: Float64
) raises:
    """Assert a flat array is three.js's."""
    var want = doc.get(doc.root(), key)
    assert_equal(len(got), doc.length(want), key)
    for at in range(len(got)):
        assert_almost_equal(
            Float64(got[at]), doc.number(doc.at(want, at)), atol=atol, msg=key
        )


def test_a_pdb_file_is_read_as_three_js_reads_it() raises:
    var model = read_pdb("assets/pdb/fixture.pdb")
    var doc = _reference()
    _same(
        model.atoms_geometry.attribute_view(String(POSITION)).packed(),
        doc,
        "atoms",
        1e-6,
    )
    # three.js decodes sRGB with its own constants; this port with the
    # curve's definition. They agree to a few parts in a million.
    _same(
        model.atoms_geometry.attribute_view(String(COLOR)).packed(),
        doc,
        "colors",
        1e-5,
    )
    _same(
        model.bonds_geometry.attribute_view(String(POSITION)).packed(),
        doc,
        "bonds",
        1e-6,
    )
    var json = doc.get(doc.root(), "json")
    assert_equal(len(model.atoms), doc.length(json))
    for at in range(len(model.atoms)):
        var entry = doc.at(json, at)
        ref atom = model.atoms[at]
        assert_almost_equal(atom.x, doc.number(doc.at(entry, 0)), atol=1e-9)
        assert_equal(atom.element, doc.string(doc.at(entry, 4)))
        var rgb = doc.at(entry, 3)
        assert_equal(atom.red, doc.integer(doc.at(rgb, 0)))
        assert_equal(atom.blue, doc.integer(doc.at(rgb, 2)))


def test_what_three_js_would_throw_on_is_refused() raises:
    with assert_raises(contains="no color"):
        _ = parse_pdb(
            "ATOM      1  XX  LIG A   1       0.000   0.000   0.000"
            + "  1.00  0.00          Qq\n"
        )
    with assert_raises(contains="no line gives"):
        _ = parse_pdb("CONECT    1    2\n")
    with assert_raises(contains="from no atom"):
        _ = parse_pdb("CONECT         2\n")
    # A line of another kind and a bond to atom zero are stepped over.
    var empty = parse_pdb("REMARK\nCONECT    1    0\n")
    assert_equal(len(empty.atoms), 0)
    var unknown = cpk_color("zz")
    assert_equal(unknown[0], -1)
    assert_true(cpk_color("fe")[0] == 224)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
