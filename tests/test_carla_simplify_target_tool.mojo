# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""How many triangles a simplified mesh keeps.

A zero budget keeps nothing. A masked mesh keeps leaf cards. A far mesh
below eight triangles stays whole. Free vehicle parts share one ratio.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_simplify_target import target_text


def _vehicle() -> String:
    """Return one kept primitive and one free primitive."""
    return (
        '{"mode":"vehicle","counts":[100,1000],"fixed":[true,false],'
        '"budget":400,"keep":400}'
    )


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test simplify target ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_simplify_target")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def _refuse(text: String, message: String) raises:
    """Require `text` to fail with `message`."""
    with assert_raises(contains=message):
        _ = target_text(text)


def test_the_share_matches_the_exporter() raises:
    assert_equal(
        target_text(
            '{"mode":"share","budget":0,"factor":1,"triangles":10,'
            '"total":10,"masked":false,"keep":400}'
        ),
        '{"action":"none","target":0,"keep":0.0,"small":false}',
    )
    assert_equal(
        target_text(
            '{"mode":"share","budget":100,"factor":1,"triangles":1000,'
            '"total":10000,"masked":true,"keep":400}'
        ),
        '{"action":"cards","target":0,"keep":0.0115,"small":false}',
    )
    assert_equal(
        target_text(
            '{"mode":"share","budget":10000,"factor":1,"triangles":1000,'
            '"total":1000,"masked":true,"keep":400}'
        ),
        '{"action":"whole","target":0,"keep":1.0,"small":false}',
    )
    assert_equal(
        target_text(
            '{"mode":"share","budget":200,"factor":1,"triangles":1000,'
            '"total":1000,"masked":false,"keep":400}'
        ),
        '{"action":"simplify","target":200,"keep":0.0,"small":false}',
    )
    assert_equal(
        target_text(
            '{"mode":"collapse","triangles":300,"target":10,'
            '"small":false,"keep":400}'
        ),
        '{"whole":true,"count":0}',
    )
    assert_equal(
        target_text(
            '{"mode":"collapse","triangles":10,"target":10,'
            '"small":true,"keep":400}'
        ),
        '{"whole":true,"count":0}',
    )
    assert_equal(
        target_text(
            '{"mode":"collapse","triangles":1000,"target":500,'
            '"small":true,"keep":400}'
        ),
        '{"whole":false,"count":500}',
    )
    assert_equal(
        target_text(
            '{"mode":"collapse","triangles":1000,"target":500,'
            '"small":false,"keep":400}'
        ),
        '{"whole":false,"count":500}',
    )
    assert_equal(
        target_text('{"mode":"weld","triangles":9,"target":3}'),
        '{"whole":false,"count":8}',
    )
    assert_equal(target_text(_vehicle()), '{"skip":false,"targets":[0,300]}')
    assert_equal(
        target_text(
            '{"mode":"vehicle","counts":[10],"fixed":[false],'
            '"budget":100,"keep":400}'
        ),
        '{"skip":true,"targets":[0]}',
    )
    _refuse("[]", "target request is not an object")
    _refuse('{"mode":"side"}', "mode is not share, collapse, weld, or vehicle")
    _refuse(
        '{"mode":"weld","triangles":-1,"target":1}',
        "count is negative",
    )
    _refuse(
        '{"mode":"vehicle","counts":[1],"fixed":[],"budget":1,"keep":1}',
        "vehicle arrays differ in length",
    )
    _refuse(
        '{"mode":"vehicle","counts":1,"fixed":[false],"budget":1,"keep":1}',
        "vehicle arrays are not lists",
    )
    _refuse(
        '{"mode":"vehicle","counts":[1],"fixed":false,"budget":1,"keep":1}',
        "vehicle arrays are not lists",
    )
    _refuse(
        '{"mode":"collapse","triangles":1,"target":1,"small":1,"keep":1}',
        "flag is not a bool",
    )
    _refuse(
        (
            '{"mode":"share","budget":1,"factor":"no","triangles":1,'
            '"total":1,"masked":false,"keep":1}'
        ),
        "factor is not a number",
    )


def test_the_command_prints_the_target_and_refuses_bad_use() raises:
    var root = _dir()
    var path = root + "/target.json"
    Path(path).write_text(_vehicle())
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(printed.output, '{"skip":false,"targets":[0,300]}\n')
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_simplify_target FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_simplify_target:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "--build",
            "carla_simplify_target",
        ],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
