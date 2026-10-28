# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Quadric collapses match fast-simplification.

`border` false matches version 0.1.11. `border` true keeps every open
edge, as version 0.2.0 does with `preserve_border`. Replay matches
`replay_simplification` from version 0.1.11.

The x86-64 wheels round each product, as this port does, so there a
simplified mesh is the same bit for bit. The arm64 wheels fuse
multiply-adds, so a collapsed vertex can differ in its last digits. Its
triangles and collapses are still the same.
"""

from std.sys import CompilationTarget
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools._python_float import parse_float
from tools._python_json import PY_FLOAT, PY_INT, PyJson
from tools.carla_simplify import simplify_text

# How far a coordinate may differ from the installed simplifier's, relative
# to its size and at least 1: the arm64 wheels differ by about 1e-14.
comptime POINT_TOLERANCE = 1.0e-12


def _assert_same_indices(
    got: PyJson, have: Int, want: PyJson, wanted: Int, name: String
) raises:
    """Assert that two lists of index pairs or triples are the same."""
    assert_equal(got.length(have), want.length(wanted), name)
    for row in range(want.length(wanted)):
        var a = got.item(have, row)
        var b = want.item(wanted, row)
        assert_equal(got.length(a), want.length(b), name)
        for column in range(want.length(b)):
            var x = got.item(a, column)
            var y = want.item(b, column)
            assert_true(got.kind(x) == PY_INT, name)
            assert_true(want.kind(y) == PY_INT, name)
            assert_equal(got.text(x), want.text(y), name)


def _coordinate(doc: PyJson, node: Int) raises -> Float64:
    """Return a coordinate, written as a float or an integer."""
    if doc.kind(node) == PY_FLOAT:
        return doc.number(node)
    assert_true(doc.kind(node) == PY_INT, "a coordinate is a number")
    return parse_float(doc.text(node))


def _assert_same_mesh(actual: String, expected: String) raises:
    """Assert that a simplified mesh is the installed simplifier's: the
    same triangles and collapses, and points within `POINT_TOLERANCE`, and
    on x86-64 the same text."""
    var got = PyJson.parse(actual)
    var want = PyJson.parse(expected)
    _assert_same_indices(
        got,
        got.at(got.root, "triangles"),
        want,
        want.at(want.root, "triangles"),
        "triangles",
    )
    _assert_same_indices(
        got,
        got.at(got.root, "collapses"),
        want,
        want.at(want.root, "collapses"),
        "collapses",
    )
    var have = got.at(got.root, "points")
    var wanted = want.at(want.root, "points")
    assert_equal(got.length(have), want.length(wanted), "points")
    for row in range(want.length(wanted)):
        var a = got.item(have, row)
        var b = want.item(wanted, row)
        assert_equal(got.length(a), want.length(b), "points")
        for column in range(want.length(b)):
            var x = _coordinate(got, got.item(a, column))
            var y = _coordinate(want, want.item(b, column))
            assert_true(
                abs(x - y) <= POINT_TOLERANCE * max(1.0, abs(y)),
                "point " + String(row) + ": " + String(x) + " " + String(y),
            )
    comptime if CompilationTarget.is_x86():
        assert_equal(actual, expected)


def _python(script: String) raises -> String:
    """Return the standard output of a Python script."""
    var result = run_program(["python3", "-c", script], 30, merge_errors=False)
    if result.status != 0:
        raise Error(result.errors)
    return result.output


def test_collapses_match_the_installed_simplifier() raises:
    var lines = _python(
        "import json, numpy\n"
        + "import fast_simplification\n"
        + "rng = numpy.random.default_rng(761)\n"
        + "def grid(n, lift):\n"
        + "    pts = [[float(x), float(y), float(lift)*x*y] for y in range(n)"
        " for x in range(n)]\n"
        + "    faces = []\n"
        + "    for y in range(n-1):\n"
        + "        for x in range(n-1):\n"
        + "            i = y*n+x\n"
        + "            faces.append([i, i+1, i+n])\n"
        + "            faces.append([i+1, i+n+1, i+n])\n"
        + "    return numpy.array(pts), numpy.array(faces, numpy.int32)\n"
        + "cases = []\n"
        + "for n, lift, target in ((3, 0.0, 2), (4, 0.15, 4), (5, -0.05, 6)):\n"
        + "    pts, faces = grid(n, lift)\n"
        + "    out, tri, collapses = fast_simplification.simplify(pts, faces,"
        " target_count=target, return_collapses=True)\n"
        + "    cases.append((pts, faces, target, False, out, tri, collapses))\n"
        + "pts = rng.normal(size=(12, 3))\n"
        + "faces ="
        " numpy.array([[0,1,2],[0,2,3],[0,3,4],[0,4,1],[5,6,7],[5,7,8],[5,8,6]],"
        " numpy.int32)\n"
        + "out, tri, collapses = fast_simplification.simplify(pts[:9], faces,"
        " target_count=3, return_collapses=True)\n"
        + "cases.append((pts[:9], faces, 3, False, out, tri, collapses))\n"
        + "for pts, faces, target, border, out, tri, collapses in cases:\n"
        + "    req = {'points': pts.tolist(), 'triangles': faces.tolist(),"
        " 'target': int(target), 'border': border}\n"
        + "    got = {'points': out.tolist(), 'triangles': tri.tolist(),"
        " 'collapses': collapses.tolist()}\n"
        + "    print(json.dumps(req, separators=(',', ':')))\n"
        + "    print(json.dumps(got, separators=(',', ':')))\n"
    )
    var pending = String("")
    var count = 0
    for line in lines.splitlines():
        var text = String(line)
        if text.byte_length() == 0:
            continue
        if pending.byte_length() == 0:
            pending = text
            continue
        _assert_same_mesh(simplify_text(pending), text)
        pending = ""
        count += 1
    assert_equal(count, 4)
    assert_equal(
        simplify_text(
            '{"points":[[0.0,0.0,0.0],[1.0,0.0,0.0],[2.0,0.0,0.0],[0.0,1.0,0.0],'
            + "[1.0,1.0,0.0],[2.0,1.0,0.0],[0.0,2.0,0.0],[1.0,2.0,0.0],[2.0,2.0,0.0]],"
            + '"triangles":[[0,1,3],[1,4,3],[1,2,4],[2,5,4],[3,4,6],[4,7,6],[4,5,7],[5,8,7]],'
            + '"target":2,"border":true}'
        ),
        '{"points":[[0.0,0.0,0.0],[1.0,0.0,0.0],[2.0,0.0,0.0],[0.0,1.0,0.0],'
        + "[1.0,1.0,0.0],[2.0,1.0,0.0],[0.0,2.0,0.0],[1.0,2.0,0.0],[2.0,2.0,0.0]],"
        + '"triangles":[[0,1,3],[1,4,3],[1,2,4],[2,5,4],[3,4,6],[4,7,6],[4,5,7],[5,8,7]],'
        + '"collapses":[]}',
    )
    with assert_raises(contains="target is larger than the mesh"):
        _ = simplify_text(
            '{"points":[[0,0,0],[1,0,0],[0,1,0]],"triangles":[[0,1,2]],"target":2,"border":false}'
        )
    with assert_raises(contains="simplify request is not an object"):
        _ = simplify_text("[]")


def test_replay_matches_the_installed_package() raises:
    var lines = _python(
        "import json, numpy\n"
        + "import fast_simplification\n"
        + "def emit(pts, faces, collapses):\n"
        + "    pts = numpy.asarray(pts, float).reshape(-1, 3)\n"
        + "    faces = numpy.asarray(faces, numpy.int32).reshape(-1, 3)\n"
        + "    collapses = numpy.asarray(collapses, numpy.int32).reshape(-1,"
        " 2)\n"
        + "    req = {'mode': 'replay', 'points': pts.tolist(), 'triangles':"
        " faces.tolist(), 'collapses': collapses.tolist()}\n"
        + "    out, tri, mapping = fast_simplification.replay_simplification(\n"
        + "        numpy.ascontiguousarray(pts, numpy.float32),\n"
        + "        numpy.ascontiguousarray(faces),\n"
        + "        numpy.ascontiguousarray(collapses))\n"
        + "    got = {'points': numpy.asarray(out, float).tolist(),"
        " 'triangles':\n"
        + "        numpy.asarray(tri, numpy.int64).tolist(), 'mapping':\n"
        + "        numpy.asarray(mapping, numpy.int64).tolist()}\n"
        + "    print(json.dumps(req, separators=(',', ':')))\n"
        + "    print(json.dumps(got, separators=(',', ':')))\n"
        + "emit([], numpy.zeros((0, 3), numpy.int32), numpy.zeros((0, 2),"
        " numpy.int32))\n"
        + "emit([[0, 0, 0], [1, 0, 0], [0, 1, 0]], [[0, 1, 2]], [])\n"
        + "emit([[0, 0, 0], [1, 0, 0], [0, 1, 0], [2, 2, 2]], [[0, 1, 2]],"
        " [[0, 3]])\n"
        + "emit([[0, 0, 0], [1, 0, 0], [0, 1, 0]], [[0, 1, 2]], [[0, 1]])\n"
        + "emit([[0.0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0.4]], [[0, 1, 2],"
        " [1, 3, 2]], [[1, 3]])\n"
        + "emit([[0.0, 0, 0], [1, 0, 0], [0.2, 1, 0.3], [1, 1, 0.4]], [[0,"
        " 1, 2],"
        " [1, 3, 2]], [[0, 1], [2, 0]])\n"
        + "emit([(0, 0, 0), (0, 1, 0), (1, 0.2, 0), (1.3, 0.2, 0), (0.2, -0.4,"
        " 0), (0.2, -0.8, 0), (1.6, 0.5, 0), (2, 2, 0), (2.2, 2, 0), (1.8,"
        " 0.7, 0)], [[0, 1, 2], [0, 2, 4], [2, 3, 3], [4, 5, 5], [2, 6, 6],"
        " [2, 9, 9], [7, 8, 8]], numpy.zeros((0, 2), numpy.int32))\n"
        + "def grid(n, lift):\n"
        + "    pts = [[float(x), float(y), float(lift)*x*y] for y in range(n)"
        " for x in range(n)]\n"
        + "    faces = []\n"
        + "    for y in range(n-1):\n"
        + "        for x in range(n-1):\n"
        + "            i = y*n+x\n"
        + "            faces.append([i, i+1, i+n])\n"
        + "            faces.append([i+1, i+n+1, i+n])\n"
        + "    return numpy.array(pts), numpy.array(faces, numpy.int32)\n"
        + "for n, lift, target in ((3, 0.0, 1), (4, 0.15, 4)):\n"
        + "    pts, faces = grid(n, lift)\n"
        + "    _, _, collapses = fast_simplification.simplify(pts, faces,"
        " target_count=target, return_collapses=True)\n"
        + "    emit(pts, faces, collapses)\n"
        + "rng = numpy.random.default_rng(761)\n"
        + "pts = rng.normal(size=(9, 3))\n"
        + "faces = numpy.array([[0, 1, 2], [0, 2, 3], [0, 3, 4], [0, 4, 1],"
        " [5, 6, 7], [5, 7, 8], [5, 8, 6]], numpy.int32)\n"
        + "_, _, collapses = fast_simplification.simplify(pts, faces,"
        " target_count=3, return_collapses=True)\n"
        + "emit(pts, faces, collapses)\n"
        + "pts = rng.normal(size=(6, 3))\n"
        + "faces = numpy.array([[0, 1, 2], [1, 3, 2], [2, 3, 4], [3, 5, 4]],"
        " numpy.int32)\n"
        + "_, _, collapses = fast_simplification.simplify(pts, faces,"
        " target_count=2, return_collapses=True)\n"
        + "emit(pts, faces, collapses)\n"
    )
    var pending = String("")
    var count = 0
    for line in lines.splitlines():
        var text = String(line)
        if text.byte_length() == 0:
            continue
        if pending.byte_length() == 0:
            pending = text
            continue
        assert_equal(simplify_text(pending), text)
        pending = ""
        count += 1
    assert_equal(count, 11)
    with assert_raises(contains="mode is not replay"):
        _ = simplify_text('{"mode":"nope"}')
    with assert_raises(contains="collapse index is out of range"):
        _ = simplify_text(
            '{"mode":"replay","points":[[0,0,0],[1,0,0],[0,1,0]],'
            + '"triangles":[[0,1,2]],"collapses":[[0,3]]}'
        )
    with assert_raises(contains="replay index is out of range"):
        _ = simplify_text(
            '{"mode":"replay","points":[[0,0,0],[1,0,0],[0,1,0],[2,2,2]],'
            + '"triangles":[[0,1,2]],"collapses":[]}'
        )
    with assert_raises(contains="collapse is not 2 indices"):
        _ = simplify_text(
            '{"mode":"replay","points":[[0,0,0],[1,0,0],[0,1,0]],'
            + '"triangles":[[0,1,2]],"collapses":[[0]]}'
        )


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_simplify"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
