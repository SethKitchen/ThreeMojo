# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The tools that suites build are found in both of their written forms."""

from std.testing import TestSuite, assert_equal, assert_true

from tools.suite_tools import built_tools, run, string_literals


def test_literals_keep_escapes_and_order() raises:
    var found = string_literals('a("x", "y\\"z") # "c"\n')
    assert_equal(len(found), 3)
    assert_equal(found[0], "x")
    assert_equal(found[1], 'y\\"z')
    assert_equal(found[2], "c")


def test_one_line_and_wrapped_builds_are_found() raises:
    var text = (
        'run(["sh", "tools/tool.sh", tool_mojo(), "--build", "cache_key"])\n'
        + 'run(\n    [\n        "sh",\n        "tools/tool.sh",\n'
        + '        tool_mojo(),\n        "--build",\n        "suite_key",\n'
        + "    ]\n)\n"
    )
    var names = built_tools(".", text)
    assert_equal(len(names), 2)
    assert_equal(names[0], "cache_key")
    assert_equal(names[1], "suite_key")


def test_other_build_flags_and_unknown_tools_are_left_out() raises:
    var text = (
        '["anatomy_validity", "--build", "--pair"]\n'
        + '["sh", "tools/tool.sh", mojo, "--build", "no_such_tool"]\n'
    )
    assert_equal(len(built_tools(".", text)), 0)


def test_the_repository_suites_name_their_tools() raises:
    var names = run(
        ".",
        [
            "tests/test_carla_gltf_package_tool.mojo",
            "tests/test_carla_gltf_rebuild_tool.mojo",
        ],
    )
    assert_true(len(names) >= 2)
    var package = False
    var rebuild = False
    for name in names:
        package = package or name == "carla_gltf_package"
        rebuild = rebuild or name == "carla_gltf_rebuild"
    assert_true(package and rebuild)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
