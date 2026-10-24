# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The original triangles nearest a simplified face.

Seventeen centers split the tree. A repeated coordinate slides the
split. Equal distances come out in the tree's heap order.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_near import near_text


def _split() -> String:
    """Return seventeen centers, enough to split a leaf of sixteen."""
    return (
        '{"centers":[[0,0,0],[1,3,5],[2,6,10],[3,2,4],[4,5,9],[5,1,3],'
        "[6,4,8],[7,0,2],[8,3,7],[9,6,1],[10,2,6],[11,5,0],[12,1,5],"
        "[13,4,10],[14,0,4],[15,3,9],[16,6,3]],"
        '"queries":[[1.2,0.4,0.5],[10,10,10]],"count":3}'
    )


def _slide() -> String:
    """Return a cloud whose median coordinate is shared."""
    return (
        '{"centers":[[0,0,0],[0,0.01,0],[0,0.02,0],[0,0.03,0],'
        "[0,0.04,0],[0,0.05,0],[0,0.06,0],[0,0.07,0],[0,0.08,0],"
        "[0,0.09,0],[0,0.1,0],[0,0.11,0],[0,0.12,0],[0,0.13,0],"
        "[0,0.14,0],[0,0.15,0],[0,0.16,0],[0,0.17,0],[5,0,0],"
        '[5,0.1,0],[5,0.2,0]],"queries":[[0.2,0.05,0]],"count":2}'
    )


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town near ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_near")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def _refuse(text: String, message: String) raises:
    """Require `text` to fail with `message`."""
    with assert_raises(contains=message):
        _ = near_text(text)


def test_the_nearest_centers_match_the_tree() raises:
    assert_equal(near_text(_split()), '{"near":[[0,3,5],[13,6,4]]}')
    assert_equal(near_text(_slide()), '{"near":[[5,6]]}')
    assert_equal(
        near_text(
            '{"centers":[[1,2,3],[1,2,3],[1,2,3],[1,2,3],[1,2,3],'
            "[1,2,3],[1,2,3],[1,2,3],[1,2,3],[1,2,3],[1,2,3],"
            "[1,2,3],[1,2,3],[1,2,3],[1,2,3],[1,2,3],[1,2,3]],"
            '"queries":[[0,0,0]],"count":2}'
        ),
        '{"near":[[1,0]]}',
    )
    assert_equal(
        near_text('{"centers":[[0,0,0]],"queries":[],"count":1}'),
        '{"near":[]}',
    )
    _refuse("[]", "near request is not an object")
    _refuse(
        '{"centers":[[0,0,0]],"queries":[[0,0,0]],"count":0}',
        "count is not positive",
    )
    _refuse(
        '{"centers":[[0,0,0]],"queries":[[0,0,0]],"count":2}',
        "count is past the centers",
    )
    _refuse(
        '{"centers":[[0,0,0]],"queries":[[0,0,0]],"count":1.5}',
        "count is not an integer",
    )
    _refuse(
        '{"centers":1,"queries":[],"count":1}',
        "vectors are not a list",
    )
    _refuse(
        '{"centers":[[0,0]],"queries":[],"count":1}',
        "vector is not 3 numbers",
    )
    _refuse(
        '{"centers":[["no",0,0]],"queries":[],"count":1}',
        "coordinate is not a number",
    )


def test_the_command_prints_the_neighbors_and_refuses_bad_use() raises:
    var root = _dir()
    var path = root + "/near.json"
    Path(path).write_text(_split())
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(printed.output, '{"near":[[0,3,5],[13,6,4]]}\n')
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_near FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_near:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_near"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
