# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A simplified far mesh, clipped and turned to face its original.

A point outside the box is pulled back in. A face that points the other
way is turned back. A mesh with no triangles is empty.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_finish import finish_text


def _clipped() -> String:
    """Return one triangle and a box that cuts its first corner."""
    return (
        '{"mode":"prepare","points":[[5,-3,0],[0,0,0],[0,1,0]],'
        '"triangles":[[0,1,2]],"box":[[0,0,0],[1,1,0]]}'
    )


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town finish ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_finish")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_a_point_stays_in_the_box_and_a_face_turns_back() raises:
    assert_equal(
        finish_text(_clipped()),
        (
            '{"corners":[[[1.0,0.0,0.0],[0.0,0.0,0.0],[0.0,1.0,0.0]]],'
            '"normals":[[0.0,0.0,-1.0]]}'
        ),
    )
    assert_equal(
        finish_text(
            '{"mode":"wind","corners":[[[0,0,0],[1,0,0],[0,1,0]]],'
            '"normals":[[0,0,1]],"uvs":[[[0,0],[1,0],[0,1]]],'
            '"facing":[[0,0,-1]]}'
        ),
        (
            '{"positions":[[0.0,1.0,0.0],[1.0,0.0,0.0],[0.0,0.0,0.0]],'
            '"normals":[[-0.0,-0.0,-1.0],[-0.0,-0.0,-1.0],[-0.0,-0.0,-1.0]],'
            '"uvs":[[0.0,1.0],[1.0,0.0],[0.0,0.0]],"triangles":[[0,1,2]]}'
        ),
    )
    assert_equal(
        finish_text('{"mode":"prepare","points":[[0,0,0]],"triangles":[]}'),
        '{"empty": true}',
    )
    with assert_raises(contains="mode is not prepare or wind"):
        _ = finish_text('{"mode":"side"}')


def test_the_command_prints_the_clipped_face_and_refuses_bad_use() raises:
    var root = _dir()
    var path = root + "/finish.json"
    Path(path).write_text(_clipped())
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(
        printed.output,
        (
            '{"corners":[[[1.0,0.0,0.0],[0.0,0.0,0.0],[0.0,1.0,0.0]]],'
            '"normals":[[0.0,0.0,-1.0]]}\n'
        ),
    )
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_finish FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_finish:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_finish"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
