# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A far building is one JPEG and one texture coordinate per corner."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_town_bake import bake_text


def _request(path: String) -> String:
    """Return one small building drawn from the front."""
    return (
        '{"out":"'
        + path
        + '","density":4,"most":32,"whole":{"positions":[[0,0,0],[1,0,0],[0,1,0.2]]},'
        + '"far":{"positions":[[0,0,0],[1,0,0],[0,1,0.2]],'
        + '"normals":[[0,0,1],[0,0,1],[0,0,1]]},'
        + '"parts":[{"positions":[[0,0,0],[1,0,0],[0,1,0.2]],'
        + '"normals":[[0,0,1],[0,0,1],[0,0,1]],'
        + '"uvs":[[0,0],[1,0],[0,1]],"triangles":[[0,1,2]],'
        + '"factor":[0.2,0.4,0.8,1],"cut":0.5,"masked":false}],'
        + '"views":[{"forward":[0,0,1],"right":[1,0,0],"up":[0,1,0]}]}'
    )


def test_a_small_building_writes_a_jpeg() raises:
    var root = mkdtemp(prefix="town bake ")
    var path = root + "/bake.jpg"
    var doc = bake_text(_request(path))
    assert_true(doc.startswith('{"uvs":['))
    var jpeg = Path(path).read_bytes()
    assert_true(len(jpeg) > 4)
    assert_equal(Int(jpeg[0]), 255)
    assert_equal(Int(jpeg[1]), 216)
    _ = run_program(["rm", "-rf", root], 10)


def test_views_must_be_a_list() raises:
    with assert_raises(contains="views are not a list"):
        _ = bake_text(
            '{"out":"x.jpg","density":4,"most":8,"whole":{"positions":[[0,0,0]]},'
            + '"far":{"positions":[[0,0,0]],"normals":[[0,1,0]]},'
            + '"parts":[{}],"views":{}}'
        )


def test_the_command_draws_the_building() raises:
    var root = mkdtemp(prefix="town bake cli ")
    var image = root + "/bake.jpg"
    var request = root + "/bake.json"
    Path(request).write_text(_request(image))
    var ran = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_bake", request],
        90,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)
    assert_true(ran.output.startswith('{"uvs":['))
    assert_true(Path(image).exists())
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_town_bake"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_bake FILE\n")
    with assert_raises(contains="bake request is not an object"):
        _ = bake_text("[]")
    with assert_raises(contains="density is not positive"):
        _ = bake_text(
            '{"out":"x.jpg","density":0,"most":8,"whole":{},"far":{},'
            + '"parts":[{}],"views":[{}]}'
        )
    _ = run_program(["rm", "-rf", root], 10)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_bake"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
