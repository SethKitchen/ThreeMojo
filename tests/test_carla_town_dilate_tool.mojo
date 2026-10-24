# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Colors spread from covered texels into empty ones.

The images are the text `json.dumps` writes for NumPy's wrapped neighbor
average and the mean of the texels that stay covered.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_dilate import dilate_text


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town dilate ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    var result = run_program(["rm", "-rf", root], 10)
    if result.status != 0:
        raise Error(result.output)


def _file(root: String, text: String) raises -> String:
    """Write `text` and return its path."""
    var path = root + "/view.json"
    Path(path).write_text(text)
    return path


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_dilate")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_one_red_texel_fills_a_small_view() raises:
    var root = _dir()
    var path = _file(
        root,
        '{"image": [[[1, 0, 0], [0, 0, 0]], [[0, 0, 0], [0, 0, 0]]], '
        + '"covered": [[true, false], [false, false]], "passes": 1}',
    )
    assert_equal(
        dilate_text(path),
        (
            "[[[1.0, 0.0, 0.0], [1.0, 0.0, 0.0]], [[1.0, 0.0, 0.0], [1.0, 0.0,"
            " 0.0]]]"
        ),
    )
    _remove(root)


def test_two_colors_average_and_zero_passes_use_the_mean() raises:
    var root = _dir()
    var averaged = _file(
        root,
        '{"image": [[[1, 0, 0]], [[0, 0, 0]], [[0, 0, 1]]], '
        + '"covered": [[true], [false], [true]], "passes": 1}',
    )
    assert_equal(
        dilate_text(averaged),
        "[[[1.0, 0.0, 0.0]], [[0.5, 0.0, 0.5]], [[0.0, 0.0, 1.0]]]",
    )
    var mean = _file(
        root,
        '{"image": [[[0, 0, 0], [0, 0, 0], [0, 0, 0]], [[0, 0, 0], '
        + "[0.2, 0.4, 0.6], [0, 0, 0]], [[0, 0, 0], [0, 0, 0], [0, 0, 0]]], "
        + '"covered": [[false, false, false], [false, true, false], '
        + '[false, false, false]], "passes": 0}',
    )
    assert_equal(
        dilate_text(mean),
        "[[[0.2, 0.4, 0.6], [0.2, 0.4, 0.6], [0.2, 0.4, 0.6]], "
        + "[[0.2, 0.4, 0.6], [0.2, 0.4, 0.6], [0.2, 0.4, 0.6]], "
        + "[[0.2, 0.4, 0.6], [0.2, 0.4, 0.6], [0.2, 0.4, 0.6]]]",
    )
    var bad = _file(
        root, '{"image": [[[1, 0, 0]]], "covered": [[true], [false]]}'
    )
    with assert_raises(contains="covered does not match"):
        _ = dilate_text(bad)
    _remove(root)


def test_the_command_prints_the_image_and_refuses_bad_use() raises:
    var root = _dir()
    var path = _file(
        root,
        '{"image": [[[1, 0, 0]]], "covered": [[true]], "passes": 1}',
    )
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(printed.output, "[[[1.0, 0.0, 0.0]]]\n")
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_dilate FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_dilate:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_dilate"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
