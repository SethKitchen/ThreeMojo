# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Quadric collapses match fast-simplification.

`border` false matches version 0.1.11. `border` true keeps every open
edge, as version 0.2.0 does with `preserve_border`.
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_simplify import simplify_text


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
        assert_equal(simplify_text(pending), text)
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


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_simplify"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
