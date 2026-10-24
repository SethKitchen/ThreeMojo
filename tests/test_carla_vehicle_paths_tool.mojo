# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Blueprint files and cooked vehicle packages.

A name matches without case. A missing package name falls back to the one
file that extends it, and a cooked file becomes a `/Game/...` path.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_vehicle_paths import (
    blueprint_path,
    game_path,
    gltf_path,
    package_path,
)


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test vehicle paths ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    var result = run_program(["rm", "-rf", root], 10)
    if result.status != 0:
        raise Error(result.output)


def _touch(path: String) raises:
    """Write an empty file, making its directories."""
    var slash = path.rfind("/")
    if slash > 0:
        var made = run_program(["mkdir", "-p", String(path[byte=:slash])], 10)
        if made.status != 0:
            raise Error(made.output)
    Path(path).write_text("")


def _cli(first: String, second: String, third: String) raises -> ProcessResult:
    """Run the built program. An empty first argument asks for usage."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_vehicle_paths")
    if first.byte_length() > 0:
        command.append(first)
        command.append(second)
        command.append(third)
    return run_program(command, 30, merge_errors=False)


def test_a_blueprint_matches_without_case_and_skips_wheels() raises:
    var root = _dir()
    _touch(root + "/Make/bp_audi.uasset")
    assert_equal(
        blueprint_path(root, "Make/BP_Audi"), root + "/Make/bp_audi.uasset"
    )
    _touch(root + "/Only/BP_zeta.uasset")
    _touch(root + "/Only/BP_alpha.uasset")
    _touch(root + "/Only/BP_Car_FLW.uasset")
    _touch(root + "/Only/BP_Car_RW.uasset")
    assert_equal(
        blueprint_path(root, "Only/Missing"), root + "/Only/BP_alpha.uasset"
    )
    _touch(root + "/Wheels/BP_Car_FW.uasset")
    with assert_raises(contains="not found"):
        _ = blueprint_path(root, "Wheels/Missing")
    with assert_raises():
        _ = blueprint_path(root, "Absent/Missing")
    _remove(root)


def test_a_package_uses_the_one_longer_name() raises:
    var root = _dir()
    var content = root + "/cooked"
    _touch(content + "/Carla/A.uasset")
    assert_equal(
        package_path(content, "/Game/Carla/A"), content + "/Carla/A.uasset"
    )
    _touch(content + "/Carla/SK_Foo_2021.uasset")
    _touch(content + "/Carla/SK_Foo_Skeleton.uasset")
    _touch(content + "/Carla/SK_Foo_Physics.uasset")
    assert_equal(
        package_path(content, "/Game/Carla/SK_Foo"),
        content + "/Carla/SK_Foo_2021.uasset",
    )
    _touch(content + "/Carla/SK_Foo_2022.uasset")
    assert_equal(package_path(content, "/Game/Carla/SK_Foo"), "")
    assert_equal(package_path(content, "/Game/Missing/None"), "")
    assert_equal(
        game_path(content, content + "/Carla/SK_Foo_2021.uasset"),
        "/Game/Carla/SK_Foo_2021",
    )
    assert_equal(
        game_path(content, root + "/other/A.uasset"), "/Game/../other/A"
    )
    _remove(root)


def test_an_exported_gltf_replaces_the_uasset_suffix() raises:
    assert_equal(
        gltf_path("/out", "/content", "/content/Carla/Static/SK.uasset"),
        "/out/Carla/Static/SK.gltf",
    )
    assert_equal(
        gltf_path("/out", "/content", "/content/SK.uasset"), "/out/SK.gltf"
    )
    var script = (
        "import os\n"
        + "raw, content, package = '/out', '/content/Carla', "
        "'/content/Other/A/B.uasset'\n"
        + "rel = os.path.relpath(package, content).replace('\\\\', '/')\n"
        + "name = os.path.basename(rel)[:-len('.uasset')]\n"
        + "folder = os.path.join(raw, *rel.split('/')[:-1])\n"
        + "print(os.path.join(folder, name + '.gltf'))\n"
    )
    var result = run_program(["python3", "-c", script], 10, merge_errors=False)
    if result.status != 0:
        raise Error(result.errors)
    var expected = String(result.output)
    if expected.endswith("\n"):
        var end = expected.byte_length() - 1
        var trimmed = String(expected[byte=0:end])
        expected = trimmed
    assert_equal(
        gltf_path("/out", "/content/Carla", "/content/Other/A/B.uasset"),
        expected,
    )


def test_the_command_prints_a_path_and_refuses_bad_use() raises:
    var root = _dir()
    _touch(root + "/Make/BP_Audi.uasset")
    var found = _cli("blueprint", root, "Make/bp_audi")
    assert_equal(found.status, 0)
    assert_equal(found.errors, "")
    assert_equal(found.output, root + "/Make/BP_Audi.uasset\n")
    var missing = _cli("package", root, "/Game/None")
    assert_equal(missing.status, 0)
    assert_equal(missing.output, "\n")
    var usage = _cli("", "", "")
    assert_equal(usage.status, 2)
    assert_true(usage.errors.startswith("usage: carla_vehicle_paths "))
    var failed = _cli("blueprint", root, "Missing/No")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_vehicle_paths:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_vehicle_paths"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
