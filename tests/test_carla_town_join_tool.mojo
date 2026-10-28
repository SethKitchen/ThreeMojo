# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A building's primitives joined into one mesh.

The second part's triangle starts after the first part's vertices.
An index past that part is refused.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_join import join_text


def _parts() -> String:
    """Return two primitives."""
    return (
        '{"parts":[{"positions":[[0,0,0],[1,0,0]],"normals":[[0,1,0],[0,1,0]],'
        '"uvs":[[0,0],[1,0]],"triangles":[[0,1,0]]},'
        '{"positions":[[2,3,4]],"normals":[[0,0,1]],"uvs":[[0.5,0.5]],'
        '"triangles":[[0,0,0]]}]}'
    )


def _joined() -> String:
    """Return the joined mesh for `_parts`."""
    return (
        '{"positions":[[0.0,0.0,0.0],[1.0,0.0,0.0],[2.0,3.0,4.0]],'
        '"normals":[[0.0,1.0,0.0],[0.0,1.0,0.0],[0.0,0.0,1.0]],'
        '"uvs":[[0.0,0.0],[1.0,0.0],[0.5,0.5]],'
        '"triangles":[[0,1,0],[2,2,2]]}'
    )


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town join ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_join")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_the_second_part_starts_after_the_first() raises:
    assert_equal(join_text(_parts()), _joined())
    with assert_raises(contains="index out of range"):
        _ = join_text(
            '{"parts":[{"positions":[[0,0,0]],"normals":[[0,1,0]],'
            '"uvs":[[0,0]],"triangles":[[0,1,0]]}]}'
        )


def test_the_command_prints_the_mesh_and_refuses_bad_use() raises:
    var root = _dir()
    var path = root + "/join.json"
    Path(path).write_text(_parts())
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(printed.output, _joined() + "\n")
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_join FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_join:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_join"], 120
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
