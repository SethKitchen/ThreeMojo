# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Texture coordinates of a simplified triangle.

A corner halfway along both edges of a right triangle reads the
matching texture coordinate. A short triangle is refused.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_uv import uv_text


def _triangle() -> String:
    """Return one right triangle and a point inside it."""
    return (
        '{"source":[[[0,0,0],[1,0,0],[0,1,0]]],'
        '"uvs":[[[0,0],[1,0],[0,1]]],'
        '"corners":[[[0.25,0.25,0],[1,0,0],[0,1,0]]]}'
    )


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town uv ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_uv")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_a_midpoint_reads_the_matching_coordinate() raises:
    assert_equal(
        uv_text(_triangle()),
        '{"uvs":[[0.25,0.25],[1.0,0.0],[0.0,1.0]]}',
    )
    with assert_raises(contains="triangles differ in length"):
        _ = uv_text(
            '{"source":[[[0,0,0],[1,0,0],[0,1,0]],[[0,0,0],[1,0,0],[0,1,0]]],'
            '"uvs":[[[0,0],[1,0],[0,1]]],'
            '"corners":[[[0,0,0],[1,0,0],[0,1,0]],[[0,0,0],[1,0,0],[0,1,0]]]}'
        )


def test_the_command_prints_the_coordinates_and_refuses_bad_use() raises:
    var root = _dir()
    var path = root + "/uv.json"
    Path(path).write_text(_triangle())
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(printed.output, '{"uvs":[[0.25,0.25],[1.0,0.0],[0.0,1.0]]}\n')
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_uv FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_uv:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_uv"], 120
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
