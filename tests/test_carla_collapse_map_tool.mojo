# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The first corner that collapsed into each new corner.

When two old corners land on one new corner, the smaller old index
stays. A new corner that nobody reached stays 0.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_collapse_map import collapse_text


def _shared() -> String:
    """Return three old corners, two of which land on corner 2."""
    return '{"mapping":[2,0,2],"count":3}'


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test collapse map ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_collapse_map")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def _refuse(text: String, message: String) raises:
    """Require `text` to fail with `message`."""
    with assert_raises(contains=message):
        _ = collapse_text(text)


def test_the_first_old_corner_stays() raises:
    assert_equal(collapse_text(_shared()), '{"source":[1,0,0]}')
    assert_equal(
        collapse_text('{"mapping":[1,0,1,0],"count":2}'),
        '{"source":[1,0]}',
    )
    assert_equal(
        collapse_text('{"mapping":[2,2,1,0,1],"count":3}'),
        '{"source":[3,2,0]}',
    )
    assert_equal(collapse_text('{"mapping":[],"count":2}'), '{"source":[0,0]}')
    assert_equal(collapse_text('{"mapping":[],"count":0}'), '{"source":[]}')
    _refuse("[]", "collapse map is not an object")
    _refuse('{"mapping":1,"count":0}', "mapping is not a list")
    _refuse('{"mapping":[],"count":-1}', "count is negative")
    _refuse('{"mapping":[],"count":1.5}', "count is not an integer")
    _refuse('{"mapping":[0],"count":0}', "index out of range")
    _refuse('{"mapping":[-1],"count":1}', "index out of range")
    _refuse('{"mapping":[1],"count":1}', "index out of range")
    _refuse('{"mapping":[0.5],"count":1}', "index is not an integer")


def test_the_command_prints_the_map_and_refuses_bad_use() raises:
    var root = _dir()
    var path = root + "/map.json"
    Path(path).write_text(_shared())
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(printed.output, '{"source":[1,0,0]}\n')
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_collapse_map FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_collapse_map:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_collapse_map"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
