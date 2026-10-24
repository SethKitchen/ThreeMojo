# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The class is the word before the package name in a UModel listing."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_umodel_class import class_text


def test_the_first_matching_line_names_the_class() raises:
    var listing = String(
        "too short SkeletalMesh SK_Skip\n"
        + "Export 0 (0x10): StaticMesh SM_Glass\n"
        + "Export 1 (0x20): SkeletalMesh SK_Body\n"
        + "Export 2 (0x30): PhysicsAsset SK_Body\n"
    )
    assert_equal(class_text("SK_Body", listing), "SkeletalMesh")
    assert_equal(class_text("SM_Glass", listing), "StaticMesh")
    assert_equal(class_text("Missing", listing), "")
    assert_equal(
        class_text("SK_Body", "Export\t3\t(0x1):\tSkeletalMesh\tSK_Body\r\n"),
        "SkeletalMesh",
    )
    assert_equal(class_text("SK_Body", ""), "")


def test_the_command_prints_the_class_and_refuses_bad_use() raises:
    var root = mkdtemp(prefix="test umodel class ")
    var path = root + "/list.txt"
    Path(path).write_text("Export 0 (0x1): StaticMesh SM_Sign\n")
    var found = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_umodel_class",
            "SM_Sign",
            path,
        ],
        60,
        merge_errors=False,
    )
    if found.status != 0:
        raise Error(found.output)
    assert_equal(found.output, "StaticMesh\n")
    var empty = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_umodel_class",
            "Missing",
            path,
        ],
        30,
        merge_errors=False,
    )
    assert_equal(empty.status, 0)
    assert_equal(empty.output, "\n")
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_umodel_class"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_umodel_class NAME LISTING\n")
    var failed = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_umodel_class",
            "SM_Sign",
            root + "/missing.txt",
        ],
        30,
        merge_errors=False,
    )
    assert_true(failed.status != 0)
    assert_true(failed.errors.startswith("carla_umodel_class:"))
    _ = run_program(["rm", "-rf", root], 10)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_umodel_class"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
