# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A far tree is two crossing quads and one PNG."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_town_tree import tree_text


def test_a_small_tree_writes_a_png_and_two_quads() raises:
    var root = mkdtemp(prefix="town tree ")
    var path = root + "/tree.png"
    var doc = tree_text(
        '{"size":4,"samples":1,"out":"'
        + path
        + '","parts":[{"positions":[[0,0,0],[1,0,0],[0.2,2,0.3]],'
        + '"normals":[[0,1,0],[0,1,0],[0,1,0]],'
        + '"uvs":[[0,0],[1,0],[0,1]],"triangles":[[0,1,2]],'
        + '"factor":[1,0,0,1],"cut":0.5,"masked":false}]}'
    )
    assert_true(doc.find('"triangles":[[0,1,2],[0,2,3],[4,5,6],[4,6,7]]') >= 0)
    assert_true(doc.find('"normals":') >= 0)
    var png = Path(path).read_bytes()
    assert_true(len(png) > 8)
    assert_equal(Int(png[0]), 137)
    assert_equal(Int(png[1]), 80)
    assert_equal(Int(png[2]), 78)
    assert_equal(Int(png[3]), 71)
    _ = run_program(["rm", "-rf", root], 10)


def test_a_non_positive_size_is_refused() raises:
    with assert_raises(contains="samples is not positive"):
        _ = tree_text('{"size":4,"samples":0,"out":"x.png","parts":[{}]}')


def test_the_command_draws_the_tree() raises:
    var root = mkdtemp(prefix="town tree cli ")
    var image = root + "/tree.png"
    var request = root + "/tree.json"
    Path(request).write_text(
        '{"size":4,"samples":1,"out":"'
        + image
        + '","parts":[{"positions":[[0,0,0],[1,0,0],[0.2,2,0.3]],'
        + '"normals":[[0,1,0],[0,1,0],[0,1,0]],"uvs":[[0,0],[1,0],[0,1]],'
        + '"triangles":[[0,1,2]],"factor":[0,1,0,1],"cut":0.5,"masked":false}]}'
    )
    var ran = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_tree", request],
        60,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)
    assert_true(
        ran.output.find('"triangles":[[0,1,2],[0,2,3],[4,5,6],[4,6,7]]') >= 0
    )
    assert_true(Path(image).exists())
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_tree"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_tree FILE\n")
    with assert_raises(contains="tree request is not an object"):
        _ = tree_text("[]")
    with assert_raises(contains="parts are not a list"):
        _ = tree_text('{"size":4,"samples":1,"out":"x.png","parts":[]}')
    with assert_raises(contains="size is not positive"):
        _ = tree_text('{"size":0,"samples":1,"out":"x.png","parts":[{}]}')
    _ = run_program(["rm", "-rf", root], 10)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_tree"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
