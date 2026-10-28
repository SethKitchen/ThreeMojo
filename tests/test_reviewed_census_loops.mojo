# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A reviewed proof with a census holds only while its listed files name it."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_false, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools._python_json import PyJson

comptime OPENDRIVE = "extensions/carla/opendrive.mojo"
"""The module whose border reader keeps a census of its record helper."""
comptime ACTIVE = "_" + "active"
"""The census name, built so that this file does not name it."""


def _lines(root: String) raises -> List[String]:
    """Return the reviewed OpenDRIVE proof lines that hold under `root`."""
    var ran = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "coverage_loop_seal",
            "reviews",
            root,
            "extensions/carla/opendrive",
        ],
        30.0,
        merge_errors=False,
    )
    if ran.status != 0:
        raise Error(ran.errors + ran.output)
    var doc = PyJson.parse(ran.output)
    var lines = List[String]()
    for index in range(doc.length(doc.root)):
        lines.append(doc.text(doc.at(doc.item(doc.root, index), "line")))
    return lines^


def _has(lines: List[String], line: String) -> Bool:
    """Return whether `lines` holds `line`."""
    for item in lines:
        if item == line:
            return True
    return False


def _root() raises -> String:
    """Return a new root that holds only the OpenDRIVE module."""
    var root = mkdtemp(prefix="reviewed-census-")
    var made = run_program(
        ["mkdir", "-p", root + "/extensions/carla", root + "/tests"], 10.0
    )
    if made.status != 0:
        raise Error(made.output)
    Path(root + "/" + OPENDRIVE).write_bytes(Path(OPENDRIVE).read_bytes())
    return root


def _remove(root: String) raises:
    """Remove a test root."""
    _ = run_program(["rm", "-rf", root], 10.0)


def test_the_census_row_holds_with_only_its_listed_file() raises:
    """With only the module present, every OpenDRIVE row holds."""
    var root = _root()
    try:
        var lines = _lines(root)
        assert_true(_has(lines, "450"))
        assert_true(_has(lines, "593"))
    finally:
        _remove(root)


def test_a_new_file_that_names_the_helper_withdraws_only_its_row() raises:
    """A file outside the census that names the helper withdraws row 450."""
    var root = _root()
    try:
        Path(root + "/tests/caller.mojo").write_text(
            "def main():\n    var " + ACTIVE + " = 1\n"
        )
        var lines = _lines(root)
        assert_false(_has(lines, "450"))
        assert_true(_has(lines, "593"))
    finally:
        _remove(root)


def test_a_longer_identifier_is_not_the_helper() raises:
    """A name that only contains the helper's name keeps row 450."""
    var root = _root()
    try:
        Path(root + "/tests/caller.mojo").write_text(
            "def main():\n    var my" + ACTIVE + "_count = 1\n"
        )
        assert_true(_has(_lines(root), "450"))
    finally:
        _remove(root)


def main() raises:
    """Run the census tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
