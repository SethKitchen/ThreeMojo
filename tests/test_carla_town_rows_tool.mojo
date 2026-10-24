# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""One town layout, one JSON value per line.

The array is what `json.loads` returns for each line, in order, written
again by `json.dumps`.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_town_rows import rows_text


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test town rows ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    var result = run_program(["rm", "-rf", root], 10)
    if result.status != 0:
        raise Error(result.output)


def _file(root: String, name: String, var data: List[UInt8]) raises -> String:
    """Write `data` and return its path."""
    var path = root + "/" + name
    Path(path).write_bytes(Span(data))
    return path


def _ascii(text: String) -> List[UInt8]:
    """Return the bytes of an ASCII string."""
    var data = List[UInt8]()
    for byte in text.as_bytes():
        data.append(byte)
    return data^


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_rows")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_lines_stay_in_order() raises:
    var root = _dir()
    var path = _file(
        root,
        "Town.jsonl",
        _ascii('{"visible": true, "mesh": "A"}\n{"n": 1}\n'),
    )
    assert_equal(
        rows_text(path),
        '[{"visible": true, "mesh": "A"}, {"n": 1}]',
    )
    var raw = List[UInt8]()
    var head = '{"a": 1}\r\n{"b": "caf'
    for byte in head.as_bytes():
        raw.append(byte)
    raw.append(0xC3)
    raw.append(0xA9)
    raw.append(34)
    raw.append(125)
    raw.append(13)
    raw.append(10)
    var unicode = _file(root, "Uni.jsonl", raw^)
    assert_equal(
        rows_text(unicode),
        '[{"a": 1}, {"b": "caf\\u00e9"}]',
    )
    var empty = _file(root, "Empty.jsonl", List[UInt8]())
    assert_equal(rows_text(empty), "[]")
    _remove(root)


def test_a_bad_line_and_a_bad_byte_fail() raises:
    var root = _dir()
    var bad = _file(root, "Bad.jsonl", _ascii('{"a": 1}\n\n'))
    with assert_raises(contains="layout line is not JSON"):
        _ = rows_text(bad)
    var raw = List[UInt8]()
    raw.append(0xFF)
    var broken = _file(root, "Broken.jsonl", raw^)
    with assert_raises(contains="layout is not UTF-8"):
        _ = rows_text(broken)
    _remove(root)


def test_the_command_prints_the_rows_and_refuses_bad_use() raises:
    var root = _dir()
    var path = _file(root, "Town.jsonl", _ascii('{"n": 1}\n'))
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(printed.output, '[{"n": 1}]\n')
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_town_rows FILE\n")
    var failed = _cli(root + "/missing.jsonl")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_town_rows:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_rows"], 120
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
