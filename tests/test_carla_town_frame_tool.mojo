# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""An Unreal matrix in the renderer's frame.

`linear` and `move` are the text `json.dumps` writes for NumPy's
`SWAP @ M.T @ SWAP` and `SWAP @ t / 100`.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_frame import frame_text


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town frame ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    var result = run_program(["rm", "-rf", root], 10)
    if result.status != 0:
        raise Error(result.output)


def _file(root: String, text: String) raises -> String:
    """Write `text` and return its path."""
    var path = root + "/matrix.json"
    Path(path).write_text(text)
    return path


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_frame")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_a_shift_becomes_meters_on_x() raises:
    var root = _dir()
    var path = _file(
        root, "[[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [3200, 0, 0, 1]]"
    )
    assert_equal(
        frame_text(path),
        '{"linear": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]], '
        + '"move": [32.0, 0.0, 0.0]}',
    )
    _remove(root)


def test_axes_swap_and_a_flat_matrix_match() raises:
    var root = _dir()
    var nested = _file(
        root,
        "[[1, 2, 3, 0], [5, 6, 7, 0], [9, 10, 11, 0], [13, 14, 15, 1]]",
    )
    var expected = (
        '{"linear": [[1.0, 9.0, 5.0], [3.0, 11.0, 7.0], [2.0, 10.0, 6.0]], '
        + '"move": [0.13, 0.15, 0.14]}'
    )
    assert_equal(frame_text(nested), expected)
    var flat = _file(
        root, "[1, 2, 3, 0, 5, 6, 7, 0, 9, 10, 11, 0, 13, 14, 15, 1]"
    )
    assert_equal(frame_text(flat), expected)
    var yaw = _file(
        root,
        "[[6.123233995736766e-17, 1, 0, 0], [-1, 6.123233995736766e-17, 0, 0], "
        + "[0, 0, 1, 0], [100, 200, 300, 1]]",
    )
    assert_equal(
        frame_text(yaw),
        '{"linear": [[6.123233995736766e-17, 0.0, -1.0], [0.0, 1.0, 0.0], '
        + '[1.0, 0.0, 6.123233995736766e-17]], "move": [1.0, 3.0, 2.0]}',
    )
    _remove(root)


def test_a_bad_matrix_is_refused() raises:
    var root = _dir()
    var path = _file(root, "[1, 2, 3]")
    with assert_raises(contains="matrix is not 16 numbers"):
        _ = frame_text(path)
    _remove(root)


def test_the_command_prints_the_frame_and_refuses_bad_use() raises:
    var root = _dir()
    var path = _file(
        root, "[[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]"
    )
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(
        printed.output,
        '{"linear": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]], '
        + '"move": [0.0, 0.0, 0.0]}\n',
    )
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_frame FILE | serve\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_frame:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_frame"], 120
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
