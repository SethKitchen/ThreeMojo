# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""An environment dump rounds each position and keeps an existing file."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="environment-dump-")


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
    command.append("carla_town_environment")
    command.extend(arguments^)
    return run_program(command, 60, merge_errors=False)


def test_positions_match_python_indent_zero() raises:
    var root = _dir()
    var raw = (
        '{"town":"TownA","map":"Carla/Maps/TownA","carla":"0.9.16",'
        + '"objects":[{"id":7,"name":"A \\"b\\"","label":"caf\\u00e9",'
        + '"location":[1.23456789,-5e-05,-1e-08],'
        + '"rotation":[0.0,-0.0,180.00004],'
        + '"box_center":[0.00015,9.99995,-1.23456789],'
        + '"box_extent":[1e-08,2.675,1e+20],'
        + '"box_rotation":[-0.00025,123456.78901,5e-05]}]}'
    )
    var source = root + "/raw.json"
    Path(source).write_text(raw)
    var client = root + "/client"
    Path(client).write_text("#!/bin/sh\ncat " + source + "\n")
    var mode = run_program(["chmod", "+x", client], 10)
    if mode.status != 0:
        raise Error(mode.output)
    var arguments = List[String]()
    arguments.append("--root")
    arguments.append(root)
    arguments.append("--client")
    arguments.append(client)
    arguments.append("TownA")
    var ran = _cli(arguments^)
    if ran.status != 0:
        raise Error(ran.errors + ran.output)
    assert_true(ran.output.startswith("TownA: 1 objects in "))
    assert_true(ran.output.endswith(" s\n"))
    var check = run_program(
        [
            "python3",
            "-c",
            (
                "import"
                " json,sys\nraw=json.load(open(sys.argv[1]))\nkeys=('location','rotation','box_center','box_extent','box_rotation')\nfor"
                " item in raw['objects']:\n    for key in keys:\n       "
                " item[key]=[round(value,4) for value in"
                " item[key]]\nexpected=json.dumps(raw, indent=0,"
                " allow_nan=True)\nactual=open(sys.argv[2]).read()\nif"
                " actual!=expected:\n   "
                " sys.stdout.write(expected+'\\n---\\n'+actual)\n    raise"
                " SystemExit(1)\n"
            ),
            source,
            root + "/environment/TownA.json",
        ],
        20,
        merge_errors=False,
    )
    if check.status != 0:
        raise Error(check.output + check.errors)
    _remove(root)


def test_an_existing_file_is_kept() raises:
    var root = _dir()
    var folder = root + "/environment"
    _ = run_program(["mkdir", "-p", folder], 10)
    Path(folder + "/TownB.json").write_text("keep\n")
    var client = root + "/client"
    Path(client).write_text("#!/bin/sh\nexit 1\n")
    var mode = run_program(["chmod", "+x", client], 10)
    if mode.status != 0:
        raise Error(mode.output)
    var arguments = List[String]()
    arguments.append("--root")
    arguments.append(root)
    arguments.append("--client")
    arguments.append(client)
    arguments.append("TownB")
    var ran = _cli(arguments^)
    if ran.status != 0:
        raise Error(ran.errors + ran.output)
    assert_equal(ran.output, "kept " + folder + "/TownB.json\n")
    assert_equal(Path(folder + "/TownB.json").read_text(), "keep\n")
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "--build",
            "carla_town_environment",
        ],
        180,
    )
    if built.status != 0:
        raise Error(built.output + built.errors)
    TestSuite.discover_tests[__functions_in_module()]().run()
