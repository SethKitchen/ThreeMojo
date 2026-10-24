# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A share of a tree's leaf cards.

Eight separate cards with seed 1 and keep 0.5 leave four cards. One
card is too few to thin.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_cards import cards_text


def _cards() -> String:
    """Return eight separate triangles."""
    var positions = String("[")
    var triangles = String("[")
    for index in range(8):
        if index > 0:
            positions += ","
            triangles += ","
        var base = String(index)
        var next = String(index + 1)
        positions += (
            "["
            + base
            + ".1,0.2,0.3],["
            + next
            + ".1,0.2,0.3],["
            + base
            + ".1,1.2,0.3]"
        )
        var corner = String(index * 3)
        triangles += (
            "["
            + corner
            + ","
            + String(index * 3 + 1)
            + ","
            + String(index * 3 + 2)
            + "]"
        )
    positions += "]"
    triangles += "]"
    return (
        '{"positions": '
        + positions
        + ',"normals": [[0,1,0],[0,1,0],[0,1,0],[0,1,0],[0,1,0],[0,1,0],'
        "[0,1,0],[0,1,0],[0,1,0],[0,1,0],[0,1,0],[0,1,0],[0,1,0],[0,1,0],"
        "[0,1,0],[0,1,0],[0,1,0],[0,1,0],[0,1,0],[0,1,0],[0,1,0],[0,1,0],"
        '[0,1,0],[0,1,0]],"uvs": [[0.0,1.0],[0.0,1.0],[0.0,1.0],[0.0,1.0],'
        "[0.0,1.0],[0.0,1.0],[0.0,1.0],[0.0,1.0],[0.0,1.0],[0.0,1.0],"
        "[0.0,1.0],[0.0,1.0],[0.0,1.0],[0.0,1.0],[0.0,1.0],[0.0,1.0],"
        "[0.0,1.0],[0.0,1.0],[0.0,1.0],[0.0,1.0],[0.0,1.0],[0.0,1.0],"
        '[0.0,1.0],[0.0,1.0]],"triangles": '
        + triangles
        + ',"keep": 0.5,"seed": 1}'
    )


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town cards ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_cards")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_eight_cards_keep_four() raises:
    var printed = cards_text(_cards())
    assert_true(
        printed.startswith(
            '{"positions": [[1.9619288125423018, 0.06192881254230171, 0.3],'
        )
    )
    assert_true(
        printed.endswith(
            '"triangles": [[0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11]]}'
        )
    )


def test_one_card_stays_whole() raises:
    assert_equal(
        cards_text(
            '{"positions":[[0,0,0],[1,0,0],[0,1,0]],"normals":[[0,1,0],[0,1,0],'
            '[0,1,0]],"uvs":[[0,0],[1,0],[0,1]],"triangles":[[0,1,2]],'
            '"keep":0.5,"seed":1}'
        ),
        '{"unchanged": true}',
    )
    with assert_raises():
        _ = cards_text(
            '{"positions":[[0,0,0],[1,0,0],[0,1,0]],"normals":[[0,1,0],[0,1,0],'
            '[0,1,0]],"uvs":[[0,0],[1,0],[0,1]],"triangles":[[0,1,2]],'
            '"keep":0.5,"seed":-1}'
        )


def test_the_command_line() raises:
    var root = _dir()
    var path = root + "/cards.json"
    Path(path).write_text(
        '{"positions":[[0,0,0],[1,0,0],[0,1,0]],"normals":[[0,1,0],[0,1,0],'
        '[0,1,0]],"uvs":[[0,0],[1,0],[0,1]],"triangles":[[0,1,2]],'
        '"keep":0.5,"seed":1}'
    )
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(printed.output, '{"unchanged": true}\n')
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_cards FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_cards:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_cards"], 120
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
