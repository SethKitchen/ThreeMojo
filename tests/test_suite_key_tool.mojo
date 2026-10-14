# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The cache key of a test suite follows everything the suite can use.

A key changes with the files the suite reaches, the assets it quotes, the
tools that build and run it, and the settings. It does not change with a
file the suite cannot reach.
"""

from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_not_equal,
    assert_raises,
    assert_true,
)

from tests._tree import Tree
from tools._imports import SourceCache, closure
from tools.suite_key import (
    KeyInputs,
    TOOLING,
    asset_files,
    fixture_inputs,
    run,
    suite_key,
)

comptime FILES = [
    ("Makefile", "all:\n"),
    ("tools/tool.sh", ""),
    ("tools/run_suite.mojo", ""),
    ("tools/compiler_telemetry.py", ""),
    ("tools/native_test_support.py", ""),
    ("tools/suite_key.mojo", "from tools._helper import f\n"),
    ("tools/_helper.mojo", "def f():\n    pass\n"),
    ("pkg/__init__.mojo", ""),
    ("pkg/used.mojo", "from pkg.deep import f\n"),
    ("pkg/deep.mojo", "def f():\n    pass\n"),
    ("pkg/unused.mojo", "def g():\n    pass\n"),
    (
        "tests/test_x.mojo",
        'from pkg.used import f\n\ndef test_a():\n    _ = "assets/box/"\n',
    ),
    ("assets/box/a.bin", "1"),
    ("assets/other.bin", "2"),
]


def _tree() raises -> Tree:
    """Return a tree with a suite, its imports, assets and the tools."""
    var tree = Tree()
    for entry in materialize[FILES]():
        tree.write(entry[0], entry[1])
    return tree^


def _key(tree: Tree, setting: String = "s") raises -> String:
    """Return the suite's key, with fresh inputs."""
    var inputs = KeyInputs.standard(tree.root)
    return suite_key("tests/test_x.mojo", [setting], inputs)


def test_closure_follows_imports_and_packages() raises:
    var tree = _tree()
    var cache = SourceCache()
    var files = closure(tree.root, "tests/test_x.mojo", tree.known(), cache)
    assert_equal(
        " ".join(files),
        "pkg/__init__.mojo pkg/deep.mojo pkg/used.mojo tests/test_x.mojo",
    )
    tree.close()


def test_the_tooling_is_the_table_and_this_tool_s_closure() raises:
    var tree = _tree()
    var inputs = KeyInputs.standard(tree.root)
    var expected = materialize[TOOLING]()
    assert_equal(len(inputs.tooling), len(expected) + 2)
    assert_equal(inputs.tooling[len(expected)], "tools/_helper.mojo")
    assert_equal(inputs.tooling[len(expected) + 1], "tools/suite_key.mojo")
    assert_equal(" ".join(inputs.assets), "assets/box/a.bin assets/other.bin")
    tree.close()


def test_key_is_stable() raises:
    var tree = _tree()
    var key = _key(tree)
    assert_equal(key, _key(tree))
    assert_equal(key.byte_length(), 20)
    tree.close()


def test_reached_files_quoted_assets_tools_and_settings_change_the_key() raises:
    var tree = _tree()
    var before = _key(tree)
    for path in [
        "pkg/deep.mojo",
        "assets/box/a.bin",
        "Makefile",
        "tools/tool.sh",
        "tools/run_suite.mojo",
        "tools/compiler_telemetry.py",
        "tools/_helper.mojo",
    ]:
        tree.write(path, "changed")
        var after = _key(tree)
        assert_not_equal(before, after, path)
        before = after
    assert_not_equal(before, _key(tree, "t"))
    tree.close()


def test_unreached_files_and_assets_leave_the_key() raises:
    var tree = _tree()
    var before = _key(tree)
    tree.write("pkg/unused.mojo", "changed")
    tree.write("assets/other.bin", "changed")
    assert_equal(before, _key(tree))
    tree.close()


def test_a_changed_nested_helper_changes_the_key() raises:
    var tree = Tree()
    tree.write("math/measured.mojo", "def value() -> Int:\n    return 1\n")
    tree.write("tests/_nested.mojo", "from math.measured import value\n")
    tree.write("tests/_shared.mojo", "from tests._nested import value\n")
    tree.write("tests/test_driver.mojo", "from tests._shared import value\n")
    var inputs = KeyInputs(tree.root, List[String](), List[String]())
    var before = suite_key("tests/test_driver.mojo", [], inputs)
    tree.write(
        "tests/_nested.mojo", "from math.measured import value\n# changed\n"
    )
    inputs = KeyInputs(tree.root, List[String](), List[String]())
    assert_not_equal(before, suite_key("tests/test_driver.mojo", [], inputs))
    tree.close()


def test_native_fixtures_are_part_of_a_linking_suite_s_key() raises:
    assert_equal(
        " ".join(
            fixture_inputs(
                ["tests/test_carla_sum2_environment.mojo", "core/a.mojo"]
            )
        ),
        "tools/fixtures/carla_sum2_fp_state.c",
    )
    assert_equal(len(fixture_inputs(["tests/test_other.mojo"])), 0)


def test_the_fixture_table_matches_the_native_support_tool() raises:
    var source = Path("tools/native_test_support.py").read_text()
    var start = source.find("FIXTURES = {")
    var end = source.find("}", start)
    assert_true(start >= 0 and end > start)
    var table = String(source[byte=start:end])
    var count = 0
    for line in table.split("\n"):
        if String(line).find("': (") >= 0:
            count += 1
    var suites = [
        "tests/test_carla_sum2_environment.mojo",
        "tests/test_carla_junction_endpoint_refusals.mojo",
    ]
    assert_equal(count, len(suites))
    for suite in suites:
        var fixtures = fixture_inputs([suite])
        assert_equal(len(fixtures), 1)
        assert_true(
            table.find("'" + suite + "': ('" + fixtures[0] + "',)") >= 0, suite
        )


def test_prints_only_the_suites_without_a_stamp() raises:
    var tree = _tree()
    var stamps = tree.root + "/stamps"
    tree.write("stamps/.keep", "")
    var arguments: List[String] = [
        "--stamps",
        stamps,
        "--setting=s",
        "tests/test_x.mojo",
    ]
    var first = run(tree.root, arguments)
    var key = _key(tree)
    assert_equal(first[0], "tests/test_x.mojo " + key)
    assert_equal(first[1], "0 of 1 suites passed before and are unchanged.")
    tree.write("stamps/test_x-" + key, "")
    var second = run(
        tree.root, ["--stamps=" + stamps, "--setting", "s", "tests/test_x.mojo"]
    )
    assert_equal(second[0], "")
    assert_equal(second[1], "1 of 1 suites passed before and are unchanged.")
    tree.close()


def test_command_line_errors() raises:
    var tree = _tree()
    with assert_raises(contains="--stamps is required"):
        _ = run(tree.root, ["tests/test_x.mojo"])
    with assert_raises(contains="--setting needs a value"):
        _ = run(tree.root, ["--stamps", "x", "--setting"])
    with assert_raises(contains="unknown option: --fast"):
        _ = run(tree.root, ["--stamps", "x", "--fast"])
    tree.close()


def test_asset_files_are_sorted() raises:
    var tree = _tree()
    tree.write("assets/a/z.bin", "")
    assert_equal(
        " ".join(asset_files(tree.root)),
        "assets/a/z.bin assets/box/a.bin assets/other.bin",
    )
    tree.close()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
