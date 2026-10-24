# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Static package names in a vehicle blueprint.

The arrays are the text `json.dumps` writes for the paths
`re.findall` keeps from the same bytes, sorted once each.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_vehicle_refs import reference_text


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test vehicle refs ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    var result = run_program(["rm", "-rf", root], 10)
    if result.status != 0:
        raise Error(result.output)


def _file(root: String, data: List[UInt8]) raises -> String:
    """Write `data` and return its path."""
    var path = root + "/BP.uasset"
    Path(path).write_bytes(Span(data))
    return path


def _bytes(text: String) -> List[UInt8]:
    """Return the bytes of an ASCII string."""
    var data = List[UInt8]()
    for byte in text.as_bytes():
        data.append(byte)
    return data^


def _cli(path: String) raises -> ProcessResult:
    """Run the built program on `path`. An empty path omits the argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_vehicle_refs")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def test_paths_are_unique_and_sorted() raises:
    var root = _dir()
    var path = _file(
        root,
        _bytes(
            "zz/Game/Carla/Static/zeta\x00/Game/Carla/Static/alpha"
            + "\x00/Game/Carla/Static/alpha"
        ),
    )
    assert_equal(
        reference_text(path),
        '["/Game/Carla/Static/alpha", "/Game/Carla/Static/zeta"]',
    )
    _remove(root)


def test_a_path_stops_at_a_dot_and_keeps_a_hyphen() raises:
    var root = _dir()
    var path = _file(
        root,
        _bytes(
            "/Game/carla/Static/no/Game/Carla/StaticX/no"
            + "/Game/Carla/Static/B-C_d.uasset"
            + "/Game/Carla/Static/Car/A"
        ),
    )
    assert_equal(
        reference_text(path),
        '["/Game/Carla/Static/B-C_d", "/Game/Carla/Static/Car/A"]',
    )
    _remove(root)


def test_joined_paths_stay_one_match() raises:
    var root = _dir()
    var path = _file(root, _bytes("/Game/Carla/Static/Game/Carla/Static/Inner"))
    assert_equal(
        reference_text(path), '["/Game/Carla/Static/Game/Carla/Static/Inner"]'
    )
    var empty = _file(root, List[UInt8]())
    assert_equal(reference_text(empty), "[]")
    _remove(root)


def test_the_command_prints_the_paths_and_refuses_bad_use() raises:
    var root = _dir()
    var path = _file(root, _bytes("/Game/Carla/Static/Car/A"))
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(printed.output, '["/Game/Carla/Static/Car/A"]\n')
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_vehicle_refs FILE\n")
    var failed = _cli(root + "/missing.uasset")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_vehicle_refs:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_vehicle_refs"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
