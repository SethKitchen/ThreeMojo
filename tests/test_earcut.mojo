# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `geometries.earcut`.

`assets/vrml/earcut.json` holds the triangles three.js 0.180's earcut
gives for made polygons: small ones, flat and repeated ones, crossing
ones that need each of earcut's passes, and ones of more than 80 points
that earcut searches by z-order. It also holds what
`ShapeUtils.triangulateShape` gives for four outlines.

`assets/earcut/holes.json` holds the same for polygons with holes: one,
two, two whose leftmost points share an x, a hole of one point, a hole
that touches the outline, a large polygon of three holes, and outlines
and holes closed by a repeat of their first point.
"""

from geometries.earcut import earcut, triangulate_shape
from loaders.json import JsonDocument, parse_json
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises


def numbers(doc: JsonDocument, node: Int) raises -> List[Float64]:
    """Read a list of numbers."""
    var out = List[Float64]()
    for i in range(doc.length(node)):
        out.append(doc.number(doc.at(node, i)))
    return out^


def check(doc: JsonDocument, item: Int, got: List[Int]) raises:
    """Compare triangles with three.js."""
    var want = doc.get(item, "triangles")
    assert_equal(len(got), doc.length(want))
    for i in range(len(got)):
        assert_equal(got[i], doc.integer(doc.at(want, i)))


def test_earcut_matches_three_js() raises:
    var doc = parse_json(Path("assets/vrml/earcut.json").read_text())
    var cases = doc.get(doc.root(), "cases")
    for c in range(doc.length(cases)):
        var item = doc.at(cases, c)
        var data = numbers(doc, doc.get(item, "data"))
        check(doc, item, earcut(data))


def test_triangulate_shape_matches_three_js() raises:
    var doc = parse_json(Path("assets/vrml/earcut.json").read_text())
    var shapes = doc.get(doc.root(), "shapes")
    for c in range(doc.length(shapes)):
        var item = doc.at(shapes, c)
        var data = numbers(doc, doc.get(item, "data"))
        check(doc, item, triangulate_shape(data))


def _holes() raises -> JsonDocument:
    """Return the hole cases three.js cut."""
    return parse_json(Path("assets/earcut/holes.json").read_text())


def test_earcut_with_holes_matches_three_js() raises:
    var doc = _holes()
    var cases = doc.get(doc.root(), "cases")
    for c in range(doc.length(cases)):
        var item = doc.at(cases, c)
        var data = numbers(doc, doc.get(item, "data"))
        var starts = doc.get(item, "holeIndices")
        var holes = List[Int]()
        for at in range(doc.length(starts)):
            holes.append(doc.integer(doc.at(starts, at)))
        check(doc, item, earcut(data, holes))


def test_triangulate_shape_with_holes_matches_three_js() raises:
    var doc = _holes()
    var shapes = doc.get(doc.root(), "shapes")
    for c in range(doc.length(shapes)):
        var item = doc.at(shapes, c)
        var contour = numbers(doc, doc.get(item, "contour"))
        var list = doc.get(item, "holes")
        var holes = List[List[Float64]]()
        for at in range(doc.length(list)):
            holes.append(numbers(doc, doc.at(list, at)))
        check(doc, item, triangulate_shape(contour, holes))


def test_a_hole_must_start_inside_and_in_order() raises:
    var square: List[Float64] = [0, 0, 10, 0, 10, 10, 0, 10, 3, 3, 5, 5, 3, 5]
    with assert_raises(contains="a hole must start"):
        _ = earcut(square, [0])
    with assert_raises(contains="a hole must start"):
        _ = earcut(square, [7])
    with assert_raises(contains="a hole must start"):
        _ = earcut(square, [4, 4])
    with assert_raises(contains="odd length"):
        _ = triangulate_shape([0, 0, 1, 0, 0, 1], [[Float64(1)]])


def test_odd_lists_are_refused() raises:
    with assert_raises(contains="odd length"):
        _ = earcut([0, 1, 2])
    with assert_raises(contains="odd length"):
        _ = triangulate_shape([0])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
