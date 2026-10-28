# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Area-weighted vertex normals.

The arrays are the text `json.dumps` writes for NumPy's cross products,
`add.at` sums and normalized lengths on the same points and faces.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_area_normals import normals_text


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test area normals ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    var result = run_program(["rm", "-rf", root], 10)
    if result.status != 0:
        raise Error(result.output)


def _file(root: String, text: String) raises -> String:
    """Write `text` and return its path."""
    var path = root + "/mesh.json"
    Path(path).write_text(text)
    return path


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_area_normals")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_a_right_triangle_points_up() raises:
    var root = _dir()
    var path = _file(
        root,
        '{"points": [[0, 0, 0], [1, 0, 0], [0, 1, 0]], "faces": [[0, 1, -1]]}',
    )
    assert_equal(
        normals_text(path),
        "[[0.0, 0.0, 1.0], [0.0, 0.0, 1.0], [0.0, 0.0, 1.0]]",
    )
    var spare = _file(
        root,
        '{"points": [[0, 0, 0], [1, 0, 0], [0, 1, 0], [5, 5, 5]], '
        + '"faces": [[0, 1, 2]]}',
    )
    assert_equal(
        normals_text(spare),
        "[[0.0, 0.0, 1.0], [0.0, 0.0, 1.0], [0.0, 0.0, 1.0], [0.0, 1.0, 0.0]]",
    )
    _remove(root)


def test_flat_and_cancelled_faces_point_up() raises:
    var root = _dir()
    var flat = _file(
        root,
        '{"points": [[0, 0, 0], [1, 0, 0], [2, 0, 0]], "faces": [[0, 1, 2]]}',
    )
    assert_equal(
        normals_text(flat),
        "[[0.0, 1.0, 0.0], [0.0, 1.0, 0.0], [0.0, 1.0, 0.0]]",
    )
    var cancel = _file(
        root,
        '{"points": [[0, 0, 0], [1, 0, 0], [0, 1, 0]], '
        + '"faces": [[0, 1, 2], [0, 2, 1]]}',
    )
    assert_equal(
        normals_text(cancel),
        "[[0.0, 1.0, 0.0], [0.0, 1.0, 0.0], [0.0, 1.0, 0.0]]",
    )
    _remove(root)


def test_a_skew_mesh_matches_numpy() raises:
    var root = _dir()
    var path = _file(
        root,
        '{"points": [[0, 0, 0], [2, 0, 0], [0, 3, 1], [1, 1, 2]], '
        + '"faces": [[0, 1, 2], [1, 3, 2]]}',
    )
    assert_equal(
        normals_text(path),
        "[[0.0, -0.31622776601683794, 0.9486832980505138], "
        + "[-0.5773502691896257, -0.5773502691896257, 0.5773502691896257], "
        + "[-0.5773502691896257, -0.5773502691896257, 0.5773502691896257], "
        + "[-0.8451542547285166, -0.50709255283711, -0.1690308509457033]]",
    )
    var bad = _file(root, '{"points": [[0, 0, 0]], "faces": [[0, 1, 2]]}')
    with assert_raises(contains="face index out of range"):
        _ = normals_text(bad)
    _remove(root)


def test_the_command_prints_the_normals_and_refuses_bad_use() raises:
    var root = _dir()
    var path = _file(
        root,
        '{"points": [[0, 0, 0], [1, 0, 0], [0, 1, 0]], "faces": [[0, 1, 2]]}',
    )
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(
        printed.output,
        "[[0.0, 0.0, 1.0], [0.0, 0.0, 1.0], [0.0, 0.0, 1.0]]\n",
    )
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_area_normals FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_area_normals:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_area_normals"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
