# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A material file index keeps the first stem, in walk order."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_file_index import index_text


def _mkdir(path: String) raises:
    """Make a directory."""
    _ = run_program(["mkdir", "-p", path], 10)


def test_the_first_stem_is_kept() raises:
    var directory = mkdtemp(prefix="file index ")
    Path(directory + "/Red.mat").write_text("a")
    Path(directory + "/Green.mat").write_text("b")
    Path(directory + "/plain.txt").write_text("c")
    _mkdir(directory + "/sub/deeper")
    Path(directory + "/sub/Red.mat").write_text("d")
    Path(directory + "/sub/Note.props.txt").write_text("e")
    Path(directory + "/sub/deeper/Blue.png").write_text("f")
    var mats = index_text(directory, ".mat")
    assert_true(mats.find('"Red": "' + directory + '/Red.mat"') >= 0)
    assert_true(mats.find('"Green": "' + directory + '/Green.mat"') >= 0)
    assert_true(mats.find("sub/Red.mat") < 0)
    var props = index_text(directory, ".props.txt")
    assert_true(
        props.find('"Note": "' + directory + '/sub/Note.props.txt"') >= 0
    )
    assert_equal(index_text(directory + "/missing", ".mat"), "{}")
    _ = run_program(["rm", "-rf", directory], 10)


def test_the_command_prints_the_index() raises:
    var directory = mkdtemp(prefix="file index ")
    Path(directory + "/Red.mat").write_text("a")
    var result = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_file_index",
            directory,
            ".mat",
        ],
        30,
        merge_errors=False,
    )
    assert_equal(result.status, 0)
    assert_equal(result.output, index_text(directory, ".mat") + "\n")
    assert_true(result.errors.find("Crashpad") < 0)
    var missing = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_file_index"],
        30,
        merge_errors=False,
    )
    assert_equal(missing.status, 2)
    _ = run_program(["rm", "-rf", directory], 10)


def main() raises:
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_file_index"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
