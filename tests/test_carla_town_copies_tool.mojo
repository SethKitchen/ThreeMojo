# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""World matrices for town mesh copies.

The arrays are the text `json.dumps` writes for the NumPy matrices
`placements` built from the same scale, rotation, location and instances.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_copies import copies_text


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town copies ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    var result = run_program(["rm", "-rf", root], 10)
    if result.status != 0:
        raise Error(result.output)


def _file(root: String, text: String) raises -> String:
    """Write `text` and return its path."""
    var path = root + "/row.json"
    Path(path).write_text(text)
    return path


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_copies")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_a_shift_is_the_component_matrix() raises:
    var root = _dir()
    var path = _file(
        root,
        '{"scale": [1, 1, 1], "rotation": [0, 0, 0], "location": [3200, 0, 0]}',
    )
    assert_equal(
        copies_text(path),
        "[[[1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0], "
        + "[3200.0, 0.0, 0.0, 1.0]]]",
    )
    _remove(root)


def test_yaw_scale_and_instances_match_numpy() raises:
    var root = _dir()
    var yaw = _file(
        root,
        '{"scale": [1, 1, 1], "rotation": [0, 90, 0], "location": [0, 0, 0]}',
    )
    assert_equal(
        copies_text(yaw),
        "[[[6.123233995736766e-17, 1.0, 0.0, 0.0], [-1.0,"
        " 6.123233995736766e-17, "
        + "0.0, 0.0], [0.0, 0.0, 1.0, 0.0], [0.0, 0.0, 0.0, 1.0]]]",
    )
    var scaled = _file(
        root,
        '{"scale": [2, 3, 4], "rotation": [0, 0, 0], "location": [1, 2, 3], '
        + '"instances": [[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 10, 20, 30, 1], '
        + "[[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]]}",
    )
    assert_equal(
        copies_text(scaled),
        "[[[2.0, 0.0, 0.0, 0.0], [0.0, 3.0, 0.0, 0.0], [0.0, 0.0, 4.0, 0.0], "
        + "[21.0, 62.0, 123.0, 1.0]], [[2.0, 0.0, 0.0, 0.0], [0.0, 3.0, 0.0, "
        + "0.0], [0.0, 0.0, 4.0, 0.0], [1.0, 2.0, 3.0, 1.0]]]",
    )
    var negative = _file(
        root,
        '{"scale": [-1, 1, 1], "rotation": [0, 0, 0], "location": [1, 2, 3]}',
    )
    assert_equal(
        copies_text(negative),
        "[[[-1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0], "
        + "[1.0, 2.0, 3.0, 1.0]]]",
    )
    _remove(root)


def test_empty_instances_and_a_bad_row_fail_cleanly() raises:
    var root = _dir()
    var empty = _file(
        root,
        '{"scale": [1, 1, 1], "rotation": [0, 0, 0], "location": [0, 0, 0], '
        + '"instances": []}',
    )
    assert_equal(copies_text(empty), "[]")
    var bad = _file(root, '{"rotation": [0, 0, 0], "location": [0, 0, 0]}')
    with assert_raises(contains="KeyError"):
        _ = copies_text(bad)
    var short = _file(
        root,
        '{"scale": [1, 1, 1], "rotation": [0, 0, 0], "location": [0, 0, 0], '
        + '"instances": [[1, 0, 0]]}',
    )
    with assert_raises(contains="instance is not 16 numbers"):
        _ = copies_text(short)
    _remove(root)


def test_the_command_prints_the_matrix_and_refuses_bad_use() raises:
    var root = _dir()
    var path = _file(
        root,
        '{"scale": [1, 1, 1], "rotation": [0, 0, 0], "location": [0, 0, 0]}',
    )
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(
        printed.output,
        "[[[1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0], "
        + "[0.0, 0.0, 0.0, 1.0]]]\n",
    )
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_copies FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_copies:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_copies"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
