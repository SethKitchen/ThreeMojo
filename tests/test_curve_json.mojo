# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.curve_json`: curves, paths and shapes read from
three.js 0.180's `toJSON` and written back as three.js writes them.

`assets/curve_json/three_curves.mjs` makes the reference. Each curve is
read, sampled and compared with three.js's `getPoints`, then written and
compared with three.js's JSON, number for number.
"""

from exporters.json_writer import JsonWriter
from loaders.curve_json import (
    curve3_from_json,
    curve3_to_json,
    curve_from_json,
    curve_to_json,
    read_curve,
    read_curve3,
    read_curve_path3,
    read_path,
    read_shape,
    shape_from_json,
    shape_to_json,
    write_curve_path3,
    write_path,
)
from loaders.json import (
    ARRAY,
    BOOLEAN,
    JsonDocument,
    NUMBER,
    OBJECT,
    STRING,
    parse_json,
)
from math.path import Path, Shape
from math.vector2 import Vector2
from std.pathlib import Path as FilePath
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def _reference() raises -> JsonDocument:
    """Return what three.js wrote."""
    return parse_json(FilePath("assets/curve_json/curves.json").read_text())


def _same(
    one: JsonDocument, a: Int, two: JsonDocument, b: Int, label: String
) raises:
    """Assert two JSON values are the same: the same keys, the same
    strings and flags, and numbers to a millionth."""
    var kind = one.kind(a)
    assert_true(kind == two.kind(b), label + ": a different kind")
    if kind == OBJECT:
        assert_equal(one.length(a), two.length(b), label + ": keys")
        for at in range(one.length(a)):
            var key = one.key(a, at)
            assert_true(two.has(b, key), label + " lacks " + key)
            _same(one, one.get(a, key), two, two.get(b, key), label + "." + key)
    elif kind == ARRAY:
        assert_equal(one.length(a), two.length(b), label + ": length")
        for at in range(one.length(a)):
            _same(one, one.at(a, at), two, two.at(b, at), label)
    elif kind == NUMBER:
        assert_almost_equal(one.number(a), two.number(b), atol=1e-6, msg=label)
    elif kind == STRING:
        assert_equal(one.string(a), two.string(b), label)
    elif kind == BOOLEAN:
        assert_equal(one.boolean(a), two.boolean(b), label)


def _points(doc: JsonDocument, list: Int, size: Int) raises -> List[Float64]:
    """Return a flat list of numbers."""
    var out = List[Float64]()
    for at in range(doc.length(list)):
        out.append(doc.number(doc.at(list, at)))
    assert_equal(len(out) % size, 0)
    return out^


def _entry_json(doc: JsonDocument, entry: Int) raises -> String:
    """Return an entry's `json` as text, to read as a document of its own."""
    return _text(doc, doc.get(entry, "json"))


def _text(doc: JsonDocument, node: Int) raises -> String:
    """Write a node back out as JSON text."""
    var writer = JsonWriter()
    _copy(doc, node, writer)
    return writer.finish()


def _copy(doc: JsonDocument, node: Int, mut writer: JsonWriter) raises:
    """Write one node into a writer."""
    var kind = doc.kind(node)
    if kind == OBJECT:
        writer.begin_object()
        for at in range(doc.length(node)):
            var key = doc.key(node, at)
            writer.key(key)
            _copy(doc, doc.get(node, key), writer)
        writer.end_object()
    elif kind == ARRAY:
        writer.begin_array()
        for at in range(doc.length(node)):
            _copy(doc, doc.at(node, at), writer)
        writer.end_array()
    elif kind == NUMBER:
        writer.raw(String(doc.number(node)))
    elif kind == STRING:
        writer.string(doc.string(node))
    elif kind == BOOLEAN:
        writer.boolean(doc.boolean(node))
    else:
        writer.null()


def test_plane_curves_read_and_write_as_three_js_does() raises:
    var doc = _reference()
    var plane = doc.get(doc.root(), "plane")
    for c in range(doc.length(plane)):
        var entry = doc.at(plane, c)
        var curve = curve_from_json(_entry_json(doc, entry))
        var want = _points(doc, doc.get(entry, "points"), 2)
        var got = curve.sample(8)
        assert_equal(len(got) * 2, len(want))
        for at in range(len(got)):
            assert_almost_equal(Float64(got[at].x), want[at * 2], atol=1e-5)
            assert_almost_equal(Float64(got[at].y), want[at * 2 + 1], atol=1e-5)
        var written = parse_json(curve_to_json(curve))
        var theirs = doc.get(entry, "json")
        # An `ArcCurve` is written as the `EllipseCurve` it is.
        if doc.string(doc.get(theirs, "type")) == "ArcCurve":
            assert_equal(
                written.string(written.get(written.root(), "type")),
                "EllipseCurve",
            )
            continue
        _same(written, written.root(), doc, theirs, "plane " + String(c))


def test_curves_in_space_read_and_write_as_three_js_does() raises:
    var doc = _reference()
    var space = doc.get(doc.root(), "space")
    for c in range(doc.length(space)):
        var entry = doc.at(space, c)
        var curve = curve3_from_json(_entry_json(doc, entry))
        var want = _points(doc, doc.get(entry, "points"), 3)
        var got = curve.sample(8)
        assert_equal(len(got) * 3, len(want))
        for at in range(len(got)):
            assert_almost_equal(Float64(got[at].x), want[at * 3], atol=1e-5)
            assert_almost_equal(Float64(got[at].y), want[at * 3 + 1], atol=1e-5)
            assert_almost_equal(Float64(got[at].z), want[at * 3 + 2], atol=1e-5)
        var written = parse_json(curve3_to_json(curve))
        _same(
            written,
            written.root(),
            doc,
            doc.get(entry, "json"),
            "space " + String(c),
        )


def test_a_path_in_space_reads_and_writes_as_three_js_does() raises:
    var doc = _reference()
    var entry = doc.get(doc.root(), "path3")
    var path = read_curve_path3(doc, doc.get(entry, "json"))
    assert_equal(len(path.curves), 2)
    var writer = JsonWriter()
    write_curve_path3(writer, path)
    var written = parse_json(writer.finish())
    _same(written, written.root(), doc, doc.get(entry, "json"), "path3")


def test_a_shape_reads_and_writes_as_three_js_does() raises:
    var doc = _reference()
    var entry = doc.get(doc.root(), "shape")
    var shape = shape_from_json(_entry_json(doc, entry))
    assert_equal(shape.hole_count(), 1)
    # The outline is closed, and the hole ends a Float32 rounding from
    # where it began, which is where it began.
    var want = _points(doc, doc.get(entry, "outline"), 2)
    var got = shape.outline_points(6)
    assert_equal(len(got) * 2, len(want))
    for at in range(len(got)):
        assert_almost_equal(Float64(got[at].x), want[at * 2], atol=1e-5)
        assert_almost_equal(Float64(got[at].y), want[at * 2 + 1], atol=1e-5)
    var holes = doc.get(entry, "holes")
    var hole = _points(doc, doc.at(holes, 0), 2)
    var drawn = shape.hole_points(0, 6)
    assert_equal(len(drawn) * 2, len(hole))
    for at in range(len(drawn)):
        assert_almost_equal(Float64(drawn[at].x), hole[at * 2], atol=1e-5)
        assert_almost_equal(Float64(drawn[at].y), hole[at * 2 + 1], atol=1e-5)
    var written = parse_json(shape_to_json(shape))
    _same(written, written.root(), doc, doc.get(entry, "json"), "shape")


def test_an_open_path_is_closed_when_it_becomes_a_shape() raises:
    var doc = parse_json(
        '{"curves":[{"type":"LineCurve","v1":[0,0],"v2":[1,0]},'
        + '{"type":"LineCurve","v1":[1,0],"v2":[0,1]}],'
        + '"currentPoint":[0,1],"holes":[]}'
    )
    var open = read_path(doc, doc.root())
    assert_true(not open.is_closed())
    var shape = read_shape(doc, doc.root())
    assert_true(shape.outline.is_closed())
    assert_equal(len(shape.outline.curves), 3)
    assert_equal(shape.uuid, "")
    # A path with no curves starts and ends at its pen.
    var empty = parse_json('{"curves":[],"currentPoint":[2,3]}')
    var pen = read_path(empty, empty.root())
    assert_equal(pen.first.x, 2)
    var writer = JsonWriter()
    write_path(writer, pen)
    var back = parse_json(writer.finish())
    assert_equal(back.string(back.get(back.root(), "type")), "Path")


def test_what_is_not_a_curve_is_refused() raises:
    with assert_raises(contains="not read"):
        _ = curve_from_json('{"type":"LineCurve3"}')
    with assert_raises(contains="not read"):
        _ = curve3_from_json('{"type":"LineCurve"}')
    with assert_raises(contains="must be an object"):
        _ = curve_from_json("[]")
    with assert_raises(contains="has no v2"):
        _ = curve_from_json('{"type":"LineCurve","v1":[0,0]}')
    with assert_raises(contains="2 numbers"):
        _ = curve_from_json('{"type":"LineCurve","v1":[0,0,0],"v2":[1,0]}')
    with assert_raises(contains="2 numbers"):
        _ = curve_from_json('{"type":"LineCurve","v1":5,"v2":[1,0]}')
    with assert_raises(contains="[x, y]"):
        _ = curve_from_json('{"type":"SplineCurve","points":[5,[1,1]]}')
    with assert_raises(contains="[x, y, z]"):
        _ = curve3_from_json('{"type":"CatmullRomCurve3","points":[5,[1,1,1]]}')
    with assert_raises(contains="must be an array"):
        _ = curve_from_json('{"type":"SplineCurve","points":{}}')
    with assert_raises(contains="[x, y]"):
        _ = curve_from_json('{"type":"SplineCurve","points":[[0,0],[1]]}')
    with assert_raises(contains="[x, y, z]"):
        _ = curve3_from_json(
            '{"type":"CatmullRomCurve3","points":[[0,0,0],[1,1]]}'
        )
    with assert_raises(contains="curveType"):
        _ = curve3_from_json(
            '{"type":"CatmullRomCurve3","points":[[0,0,0],[1,1,1]],'
            + '"closed":false,"curveType":"loose","tension":0.5}'
        )
    with assert_raises(contains="empty path"):
        _ = shape_from_json('{"curves":[],"currentPoint":[0,0],"holes":[]}')
    var bare = parse_json('{"type":"LineCurve","v1":[0,0],"v2":[1,0]}')
    var line = read_curve(bare, bare.root())
    var outline = Path(Vector2(0, 0))
    outline.line_to(Vector2(1, 0))
    outline.line_to(Vector2(0, 1))
    outline.close_path()
    var shape = Shape(outline^)
    with assert_raises(contains="needs a uuid"):
        _ = shape_to_json(shape)
    assert_equal(line.points[1].x, 1)
    var space = parse_json('{"type":"LineCurve3","v1":[0,0,0],"v2":[0,0,1]}')
    assert_equal(read_curve3(space, space.root()).points[1].z, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
