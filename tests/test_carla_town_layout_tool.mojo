# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A town layout dump installs the mod and stops the server on time."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="layout-dump-")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    var result = run_program(["rm", "-rf", root], 10)
    if result.status != 0:
        raise Error(result.output)


def _cli(var arguments: List[String]) raises -> ProcessResult:
    """Run the built program."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_town_layout")
    command.extend(arguments^)
    return run_program(command, 30, merge_errors=False)


def _exe(path: String, body: String) raises:
    """Write an executable script."""
    Path(path).write_text("#!/bin/sh\n" + body)
    var mode = run_program(["chmod", "+x", path], 10)
    if mode.status != 0:
        raise Error(mode.output)


def test_a_missing_runtime_is_refused() raises:
    var root = _dir()
    var lua = root + "/main.lua"
    Path(lua).write_text("mod\n")
    var arguments = List[String]()
    arguments.append("--root")
    arguments.append(root)
    arguments.append("--lua")
    arguments.append(lua)
    arguments.append("--limit")
    arguments.append("1")
    arguments.append("Town01")
    var ran = _cli(arguments^)
    assert_equal(ran.status, 1)
    assert_true(ran.errors.find("UE4SS is not in ") >= 0)
    _remove(root)


def test_a_finished_dump_is_reported() raises:
    var root = _dir()
    var binaries = root + "/release/CarlaUE4/Binaries/Win64"
    _ = run_program(["mkdir", "-p", binaries + "/ue4ss"], 10)
    var lua = root + "/main.lua"
    Path(lua).write_text("-- layout mod\n")
    _exe(binaries + "/CarlaUE4-Win64-Shipping.exe", "sleep 30\n")
    var client = root + "/client"
    _exe(
        client,
        (
            'target=\nwhile [ $# -gt 0 ]; do\n  if [ "$1" = --target ]; then'
            " target=$2; shift 2; else shift; fi\ndone\nprintf '4"
            ' components\\n\' > "$target.done"\n'
        ),
    )
    var arguments = List[String]()
    arguments.append("--root")
    arguments.append(root)
    arguments.append("--lua")
    arguments.append(lua)
    arguments.append("--client")
    arguments.append(client)
    arguments.append("--limit")
    arguments.append("5")
    arguments.append("Town10HD_Opt")
    var ran = _cli(arguments^)
    if ran.status != 0:
        raise Error(ran.errors + ran.output)
    assert_equal(ran.output, "Town10HD_Opt: 4 components\n")
    assert_equal(
        Path(binaries + "/ue4ss/Mods/LayoutDump/Scripts/main.lua").read_text(),
        "-- layout mod\n",
    )
    assert_equal(
        Path(binaries + "/ue4ss/Mods/mods.txt").read_text(),
        "LayoutDump : 1\n",
    )
    assert_true(Path(root + "/layout/Town10HD.jsonl.done").exists())
    assert_true(not Path(root + "/layout/Town10HD_Opt.jsonl.done").exists())
    _remove(root)


def test_a_silent_server_is_reported() raises:
    var root = _dir()
    var binaries = root + "/release/CarlaUE4/Binaries/Win64"
    _ = run_program(["mkdir", "-p", binaries + "/ue4ss"], 10)
    var lua = root + "/main.lua"
    Path(lua).write_text("mod\n")
    _exe(binaries + "/CarlaUE4-Win64-Shipping.exe", "sleep 30\n")
    var client = root + "/client"
    _exe(client, "exit 2\n")
    var arguments = List[String]()
    arguments.append("--root")
    arguments.append(root)
    arguments.append("--lua")
    arguments.append(lua)
    arguments.append("--client")
    arguments.append(client)
    arguments.append("--limit")
    arguments.append("1")
    arguments.append("Town01")
    var ran = _cli(arguments^)
    if ran.status != 0:
        raise Error(ran.errors + ran.output)
    assert_equal(ran.output, "Town01: the server did not answer\n")
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_layout"],
        180,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
    TestSuite.discover_tests[__functions_in_module()]().run()
