# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The original triangle a simplified face reads.

A right triangle reports its center and its upward normal. Of two
neighbors, the one nearer the new plane wins. An equal score keeps the
earlier neighbor.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_choose import choose_text


def _source() -> String:
    """Return one right triangle and one flat edge."""
    return (
        '{"mode":"source","positions":[[0,0,0],[1,0,0],[0,1,0],'
        "[0.5,0,0],[1.5,0,0],[2.5,0,0]],"
        '"triangles":[[0,1,2],[3,4,5]]}'
    )


def _choice() -> String:
    """Return two faces. The second neighbor wins only the first face."""
    return (
        '{"mode":"choose",'
        '"centers":[[0,0,0],[10,0,5]],'
        '"normals":[[0,0,1],[0,0,1]],'
        '"queries":[[10,0,5],[0,0,0]],'
        '"faces":[[0,0,1],[0,0,-1]],'
        '"near":[[0,1],[0,1]]}'
    )


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town choose ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_choose")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def _refuse(text: String, message: String) raises:
    """Require `text` to fail with `message`."""
    with assert_raises(contains=message):
        _ = choose_text(text)


def test_a_triangle_reports_its_center_and_a_nearer_plane_wins() raises:
    assert_equal(
        choose_text(_source()),
        (
            '{"centers":[[0.3333333333333333,0.3333333333333333,0.0],'
            "[1.5,0.0,0.0]],"
            '"normals":[[0.0,0.0,1.0],[0.0,0.0,0.0]]}'
        ),
    )
    assert_equal(
        choose_text(_choice()),
        '{"best":[1,0]}',
    )
    assert_equal(
        choose_text('{"mode":"source","positions":[],"triangles":[]}'),
        '{"centers":[],"normals":[]}',
    )
    assert_equal(
        choose_text(
            '{"mode":"choose","centers":[],"normals":[],'
            '"queries":[],"faces":[],"near":[]}'
        ),
        '{"best":[]}',
    )
    assert_equal(
        choose_text(
            '{"mode":"choose","centers":[[0,0,0]],"normals":[[0,0,1]],'
            '"queries":[[0,0,1]],"faces":[[0,0,1]],"near":[[0]]}'
        ),
        '{"best":[0]}',
    )
    _refuse("[]", "choose request is not an object")
    _refuse('{"mode":"side"}', "mode is not source or choose")
    _refuse(
        (
            '{"mode":"choose","centers":[[0,0,0]],"normals":[],'
            '"queries":[[0,0,0]],"faces":[[0,0,1]],"near":[[0]]}'
        ),
        "choose arrays differ in length",
    )
    _refuse(
        (
            '{"mode":"choose","centers":[[0,0,0]],"normals":[[0,0,1]],'
            '"queries":[[0,0,0]],"faces":[],"near":[]}'
        ),
        "choose arrays differ in length",
    )
    _refuse(
        (
            '{"mode":"choose","centers":[[0,0,0]],"normals":[[0,0,1]],'
            '"queries":[[0,0,0]],"faces":[[0,0,1]],"near":1}'
        ),
        "near does not match the faces",
    )
    _refuse(
        (
            '{"mode":"choose","centers":[[0,0,0]],"normals":[[0,0,1]],'
            '"queries":[[0,0,0]],"faces":[[0,0,1]],"near":[]}'
        ),
        "near does not match the faces",
    )
    _refuse(
        (
            '{"mode":"choose","centers":[[0,0,0]],"normals":[[0,0,1]],'
            '"queries":[[0,0,0]],"faces":[[0,0,1]],"near":[1]}'
        ),
        "near row is empty",
    )
    _refuse(
        (
            '{"mode":"choose","centers":[[0,0,0]],"normals":[[0,0,1]],'
            '"queries":[[0,0,0]],"faces":[[0,0,1]],"near":[[]]}'
        ),
        "near row is empty",
    )
    _refuse(
        (
            '{"mode":"choose","centers":[[0,0,0]],"normals":[[0,0,1]],'
            '"queries":[[0,0,0]],"faces":[[0,0,1]],"near":[[-1]]}'
        ),
        "index out of range",
    )
    _refuse(
        (
            '{"mode":"choose","centers":[[0,0,0]],"normals":[[0,0,1]],'
            '"queries":[[0,0,0]],"faces":[[0,0,1]],"near":[[1]]}'
        ),
        "index out of range",
    )
    _refuse(
        (
            '{"mode":"choose","centers":[[0,0,0]],"normals":[[0,0,1]],'
            '"queries":[[0,0,0]],"faces":[[0,0,1]],"near":[[0.5]]}'
        ),
        "index is not an integer",
    )
    _refuse(
        '{"mode":"source","positions":1,"triangles":[]}',
        "vectors are not a list",
    )
    _refuse(
        '{"mode":"source","positions":[1],"triangles":[]}',
        "vector is not 3 numbers",
    )
    _refuse(
        '{"mode":"source","positions":[[0,0]],"triangles":[]}',
        "vector is not 3 numbers",
    )
    _refuse(
        '{"mode":"source","positions":[["no",0,0]],"triangles":[]}',
        "coordinate is not a number",
    )
    _refuse(
        '{"mode":"source","positions":[[0,0,0]],"triangles":1}',
        "triangles are not a list",
    )
    _refuse(
        (
            '{"mode":"source","positions":[[0,0,0],[1,0,0],[0,1,0]],'
            '"triangles":[1]}'
        ),
        "triangle is not three indices",
    )
    _refuse(
        (
            '{"mode":"source","positions":[[0,0,0],[1,0,0],[0,1,0]],'
            '"triangles":[[0,1]]}'
        ),
        "triangle is not three indices",
    )
    _refuse(
        (
            '{"mode":"source","positions":[[0,0,0],[1,0,0],[0,1,0]],'
            '"triangles":[[-1,0,1]]}'
        ),
        "index out of range",
    )
    _refuse(
        (
            '{"mode":"source","positions":[[0,0,0],[1,0,0],[0,1,0]],'
            '"triangles":[[0,1,3]]}'
        ),
        "index out of range",
    )


def test_the_command_prints_the_choice_and_refuses_bad_use() raises:
    var root = _dir()
    var path = root + "/choose.json"
    Path(path).write_text(_choice())
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(printed.output, '{"best":[1,0]}\n')
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_choose FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_choose:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_choose"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
