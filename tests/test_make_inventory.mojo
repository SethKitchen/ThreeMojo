# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The Makefile finds import-only helpers by name, without a list to edit.

Each test copies the Makefile's inventory section into a small project in a
temporary directory and prints the lists with `make`. No compiler runs. The
suite key of every suite includes the Makefile, so a change to it runs this
suite again.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
)

from tools._process import run_program

comptime _LISTS = [
    "TEST_HELPER_LIBS",
    "HELPER_LIBS",
    "TOOL_LIBS",
    "ENTRY_POINTS",
    "DOC_SOURCES",
    "TESTS",
    "FORMATTED",
]


struct Project(Movable):
    """A small project with the real Makefile inventory section."""

    var root: String

    def __init__(out self) raises:
        self.root = mkdtemp(prefix="test helper inventory ")
        var files = [
            ("math/measured.mojo", "def value() -> Int:\n    return 1\n"),
            ("tests/_nested.mojo", "from math.measured import value\n"),
            ("tests/_shared.mojo", "from tests._nested import value\n"),
            ("tests/test_driver.mojo", "from tests._shared import value\n"),
            ("tests/test_other.mojo", "from math.measured import value\n"),
            ("tests/carla_fixed_s_fixture.mojo", "# named fixture\n"),
            ("tests/exact_predicates_oracle.mojo", "# named oracle\n"),
            ("tools/_helper.mojo", "# any tools/_*.mojo is a helper\n"),
            ("tools/driver.mojo", "def main():\n    pass\n"),
            ("coverage/runtime.mojo", "# runtime\n"),
            ("coverage/build_cli.mojo", "def main():\n    pass\n"),
            ("coverage/report_cli.mojo", "def main():\n    pass\n"),
            ("tests/compile_fail/rejection.mojo", "# rejected\n"),
        ]
        for directory in [
            "math",
            "tests/compile_fail",
            "tools",
            "coverage",
            "examples",
            "bench",
        ]:
            _ = run_program(["mkdir", "-p", self.root + "/" + directory], 10)
        for file in files:
            self.write(file[0], file[1])
        var source = Path("Makefile").read_text()
        var start = source.find("TOOL_CLIS    :=")
        var end = source.find("\n# --- the optional GPU backend", start)
        assert_true(start >= 0 and end > start)
        var makefile = (
            "LIB_SOURCES := math/measured.mojo\n"
            + String(source[byte=start:end])
            + "\n.PHONY: inventory\ninventory:\n"
        )
        for name in materialize[_LISTS]():
            makefile += '\t@printf "%s\\n" "' + name + ":$(" + name + ')"\n'
        self.write("Makefile", makefile)

    def write(self, relative: String, text: String) raises:
        Path(self.root + "/" + relative).write_text(text)

    def values(self, name: String) raises -> List[String]:
        """Return one inventory list, as `make` expands it."""
        # An outer make's flags must not reach this one.
        var result = run_program(
            [
                "env",
                "-u",
                "MAKEFLAGS",
                "-u",
                "MFLAGS",
                "-u",
                "MAKEOVERRIDES",
                "-u",
                "MAKELEVEL",
                "-u",
                "MAKEFILES",
                "-u",
                "GNUMAKEFLAGS",
                "make",
                "-s",
                "inventory",
            ],
            5,
            merge_errors=False,
            directory=self.root,
        )
        assert_equal(result.status, 0, result.output + result.errors)
        assert_equal(result.errors, "")
        for line in result.output.splitlines():
            var text = String(line)
            if text.startswith(name + ":"):
                var words = List[String]()
                for word in String(
                    text[byte = name.byte_length() + 1 :]
                ).split():
                    words.append(String(word))
                return words^
        raise Error("missing inventory list: " + name)

    def close(self) raises:
        """Remove the project. A test calls it last, which also keeps the
        project alive until the test ends."""
        _ = run_program(["rm", "-rf", self.root], 10)


def _count(items: List[String], item: String) -> Int:
    """Return how many times `item` occurs."""
    var count = 0
    for other in items:
        if other == item:
            count += 1
    return count


def _same(actual: List[String], expected: List[String]) raises:
    """Assert two lists hold the same items, in any order."""
    assert_equal(len(actual), len(expected))
    for item in expected:
        assert_equal(_count(actual, item), _count(expected, item), item)


def test_helpers_have_one_inventory_for_docs_formatting_and_copies() raises:
    var project = Project()
    var helpers: List[String] = [
        "tests/_nested.mojo",
        "tests/_shared.mojo",
        "tests/carla_fixed_s_fixture.mojo",
        "tests/exact_predicates_oracle.mojo",
    ]
    _same(project.values("TEST_HELPER_LIBS"), helpers)
    var all_helpers = helpers.copy()
    all_helpers.append("tools/_helper.mojo")
    _same(project.values("HELPER_LIBS"), all_helpers)
    var tool_libs = project.values("TOOL_LIBS")
    var docs = project.values("DOC_SOURCES")
    var formatted = project.values("FORMATTED")
    var entries = project.values("ENTRY_POINTS")
    var tests = project.values("TESTS")
    for helper in all_helpers:
        assert_equal(_count(tool_libs, helper), 1, helper)
        assert_equal(_count(docs, helper), 1, helper)
        assert_equal(_count(formatted, helper), 1, helper)
        assert_equal(_count(entries, helper), 0, helper)
        assert_equal(_count(tests, helper), 0, helper)
    var expected_tests: List[String] = [
        "tests/test_driver.mojo",
        "tests/test_other.mojo",
    ]
    _same(tests, expected_tests)
    var expected_entries = tests.copy()
    expected_entries.append("tools/driver.mojo")
    expected_entries.append("coverage/build_cli.mojo")
    expected_entries.append("coverage/report_cli.mojo")
    _same(entries, expected_entries)
    assert_equal(_count(formatted, "tests/compile_fail/rejection.mojo"), 1)
    project.close()


def test_new_prefixed_helpers_are_found_without_an_edit() raises:
    var project = Project()
    project.write("tests/_future_control.mojo", "# another helper\n")
    project.write("tools/_future_tool.mojo", "# another helper\n")
    var helpers = project.values("HELPER_LIBS")
    var docs = project.values("DOC_SOURCES")
    var formatted = project.values("FORMATTED")
    var entries = project.values("ENTRY_POINTS")
    var tests = project.values("TESTS")
    for helper in ["tests/_future_control.mojo", "tools/_future_tool.mojo"]:
        assert_equal(_count(helpers, helper), 1, helper)
        assert_equal(_count(docs, helper), 1, helper)
        assert_equal(_count(formatted, helper), 1, helper)
        assert_false(_count(entries, helper) > 0)
        assert_false(_count(tests, helper) > 0)
    project.close()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
