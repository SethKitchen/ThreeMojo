# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A far building's picture and its texture coordinates.

One triangle becomes a flat face. Two points size one view. The face
that points up reads the first of two pictures.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_atlas import atlas_text


def _flat() -> String:
    """Return one right triangle in the xy plane."""
    return (
        '{"mode":"flat","positions":[[0,0,0],[1,0,0],[0,1,0]],'
        '"triangles":[[0,1,2]]}'
    )


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town atlas ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_atlas")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_one_triangle_lies_flat_with_its_area_normal() raises:
    assert_equal(
        atlas_text(_flat()),
        (
            '{"positions":[[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]],'
            '"normals":[[0.0, 0.0, 1.0], [0.0, 0.0, 1.0], [0.0, 0.0, 1.0]],'
            '"triangles":[[0, 1, 2]]}'
        ),
    )
    assert_equal(
        atlas_text(
            '{"mode":"spans","positions":[[0,0,0],[1,2,3]],"density":6,'
            '"most":512,"views":[{"right":[1,0,0],"up":[0,1,0]}]}'
        ),
        (
            '[{"columns":6,"rows":12,"low_r":0.0,"high_r":1.0,"low_u":0.0,'
            '"high_u":2.0,"width":1.0,"height":2.0}]'
        ),
    )


def test_the_upward_face_reads_the_first_picture() raises:
    assert_equal(
        atlas_text(
            '{"mode":"pack","positions":[[0,0,0],[1,0,0],[0,1,0]],'
            '"normals":[[0,0,1],[0,0,1],[0,0,1]],"views":['
            '{"forward":[0,0,1],"right":[1,0,0],"up":[0,1,0],"span_r":[0,1],'
            '"span_u":[0,1],"image":[[[1,0,0]]]},'
            '{"forward":[1,0,0],"right":[0,1,0],"up":[0,0,1],"span_r":[0,1],'
            '"span_u":[0,1],"image":[[[0,1,0],[0,0,1]]]}]}'
        ),
        (
            '{"atlas":[[[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]],'
            '"uvs":[[0.0, 1.0], [0.3333333333333333, 1.0], [0.0, 0.0]]}'
        ),
    )
    with assert_raises(contains="mode is not flat, spans or pack"):
        _ = atlas_text('{"mode":"side"}')
    with assert_raises(contains="index out of range"):
        _ = atlas_text(
            '{"mode":"flat","positions":[[0,0,0],[1,0,0],[0,1,0]],'
            '"triangles":[[0,1,9]]}'
        )


def test_the_command_prints_the_face_and_refuses_bad_use() raises:
    var root = _dir()
    var path = root + "/atlas.json"
    Path(path).write_text(_flat())
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(
        printed.output,
        (
            '{"positions":[[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]],'
            '"normals":[[0.0, 0.0, 1.0], [0.0, 0.0, 1.0], [0.0, 0.0, 1.0]],'
            '"triangles":[[0, 1, 2]]}\n'
        ),
    )
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_atlas FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_atlas:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_atlas"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
