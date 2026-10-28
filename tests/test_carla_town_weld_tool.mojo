# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Corners gathered into cells.

Two corners at the origin become one. A repeated triangle is kept once.
A mesh that fits in one cell has no triangle left.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_weld import weld_text


def _mesh() -> String:
    """Return five corners and four triangles."""
    return (
        '{"positions":[[0,0,0],[0,0,0],[1,0,0],[0,1,0],[1,1,0]],'
        '"triangles":[[0,2,3],[1,2,3],[2,3,4],[0,1,2]],'
        '"divisions":200,"minimum":0.25}'
    )


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town weld ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_weld")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_shared_cells_keep_one_mean_and_one_copy() raises:
    assert_equal(
        weld_text(_mesh()),
        (
            '{"points":[[0.0,0.0,0.0],[0.0,1.0,0.0],[1.0,0.0,0.0],'
            '[1.0,1.0,0.0]],"triangles":[[0,2,1],[2,1,3]]}'
        ),
    )
    assert_equal(
        weld_text(
            '{"positions":[[0,0,0],[0.01,0,0],[0.02,0.01,0]],'
            '"triangles":[[0,1,2]],"divisions":200,"minimum":1}'
        ),
        '{"empty": true}',
    )
    with assert_raises(contains="index out of range"):
        _ = weld_text(
            '{"positions":[[0,0,0],[1,0,0],[0,1,0]],"triangles":[[0,1,9]],'
            '"divisions":200,"minimum":0.25}'
        )


def test_the_command_prints_the_cells_and_refuses_bad_use() raises:
    var root = _dir()
    var path = root + "/weld.json"
    Path(path).write_text(_mesh())
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(
        printed.output,
        (
            '{"points":[[0.0,0.0,0.0],[0.0,1.0,0.0],[1.0,0.0,0.0],'
            '[1.0,1.0,0.0]],"triangles":[[0,2,1],[2,1,3]]}\n'
        ),
    )
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_weld FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_weld:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_weld"], 120
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
