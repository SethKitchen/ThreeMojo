# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A bent spline mesh placed in the renderer frame.

The component matrix moves the bent points. Y and Z are swapped, and
centimeters become meters. A mirrored matrix reverses the triangles.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_spline import spline_text


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town spline ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _file(root: String, name: String, text: String) raises -> String:
    """Write `text` and return its path."""
    var path = root + "/" + name
    Path(path).write_text(text)
    return path


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_spline")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_an_identity_matrix_swaps_axes_and_uses_meters() raises:
    var text = (
        '{"matrix":[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]],'
        '"positions":[[100,200,300]],"normals":[[0,3,4]],'
        '"triangles":[[0,1,2]]}'
    )
    assert_equal(
        spline_text(text),
        (
            '{"points": [[1.0, 3.0, 2.0]], "normals": [[0.0, 0.8, 0.6]], '
            '"triangles": [[0, 1, 2]]}'
        ),
    )


def test_a_mirrored_matrix_reverses_triangles() raises:
    var text = (
        '{"matrix":[[1,0,0,0],[0,1,0,0],[0,0,-1,0],[0,0,0,1]],'
        '"positions":[[100,0,0]],"normals":[[0,0,1]],'
        '"triangles":[[0,1,2]]}'
    )
    assert_equal(
        spline_text(text),
        (
            '{"points": [[1.0, 0.0, 0.0]], "normals": [[0.0, -1.0, 0.0]], '
            '"triangles": [[2, 1, 0]]}'
        ),
    )
    with assert_raises():
        _ = spline_text(
            '{"matrix":[[0,0,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,1]],'
            '"positions":[[0,0,0]],"normals":[[0,1,0]],"triangles":[[0,0,0]]}'
        )


def test_the_command_line() raises:
    var root = _dir()
    var path = _file(
        root,
        "spline.json",
        (
            '{"matrix":[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]],'
            '"positions":[[100,200,300]],"normals":[[0,3,4]],'
            '"triangles":[[0,1,2]]}'
        ),
    )
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(
        printed.output,
        (
            '{"points": [[1.0, 3.0, 2.0]], "normals": [[0.0, 0.8, 0.6]], '
            '"triangles": [[0, 1, 2]]}\n'
        ),
    )
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_spline FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_spline:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_spline"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
