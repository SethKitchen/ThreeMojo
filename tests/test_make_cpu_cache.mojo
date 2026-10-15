# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The CPU suite recipe builds, runs and stamps only the suites it is given.

Each test copies the recipe from the Makefile into a small project, with a
stand-in compiler that writes a program printing one passing test. No Mojo
compiler runs; the suite runner and the compiler telemetry wrapper are the
ones `tools/tool.sh` already built.
"""

from std.os import getenv, setenv, unsetenv
from std.os.path import isfile
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
)

from tests._tree import Tree, copy_suite_runner, tool_mojo
from tools._process import ProcessResult, run_program

comptime OUTPUT = (
    "Running 1 tests for stub.mojo\n"
    "PASS [ 1.0 ] test_stub\n"
    "Summary [ 1.0 ] 1 tests run: 1 passed , 0 failed , 0 skipped\n"
)


struct Recipe(Movable):
    """A project that holds the CPU suite recipe and a stand-in compiler."""

    var tree: Tree
    """The project."""

    def __init__(out self, compiler_status: Int = 0) raises:
        """Make the project.

        Args:
            compiler_status: The stand-in compiler's exit status.
        """
        self.tree = Tree()
        var source = Path("Makefile").read_text()
        var start = source.find("\t@xargs -n 2 -P $(JOBS)")
        var end = source.find('\n\t@echo "All ', start)
        assert_true(start >= 0 and end > start)
        for folder in ["cache/bin", "cache/suites", "tools", "tests"]:
            self.tree.write(folder + "/.keep", "")
        self.tree.write("cache/bin/preserve", "unchanged")
        for name in ["test_a", "test_b"]:
            self.tree.write(
                "tests/" + name + ".mojo", "def test_stub():\n    pass\n"
            )
        # The recipe wraps each build in the telemetry tool, which must be
        # built before the project gets a copy of the built tools.
        var built = run_program(
            [
                "sh",
                "tools/tool.sh",
                tool_mojo(),
                "--build",
                "compiler_telemetry",
            ],
            120,
        )
        if built.status != 0:
            raise Error("cannot build the telemetry tool: " + built.output)
        copy_suite_runner(
            self.tree,
            [
                "tools/compiler_telemetry.mojo",
                "tools/native_test_support.py",
                "tools/affected.py",
                "tools/suite_key.py",
            ],
        )
        var program = "#!/bin/sh\nprintf '%s' '" + String(OUTPUT) + "'\n"
        self.tree.write(
            "compiler.sh",
            'for last; do :; done; printf "%s\\n" "$last" >> invocations\n'
            + "status="
            + String(compiler_status)
            + '\n[ "$status" -eq 0 ] || exit "$status"\n'
            + 'while [ "$1" != -o ]; do shift; done\n'
            + "cat > \"$2\" <<'PROGRAM'\n"
            + program
            + "PROGRAM\n"
            + 'chmod 700 "$2"\n',
        )
        self.tree.write(
            "Makefile",
            "JOBS := 1\nCACHE_DIR := cache\nBIN_DIR := cache/bin\n"
            + "SUITE_STAMPS := cache/suites\nMOJO := sh compiler.sh\n"
            + "TOOL_MOJO := "
            + tool_mojo()
            + "\nTEST_TIMEOUT := 5\nall:\n"
            + String(source[byte=start:end])
            + "\n",
        )

    def make(self) raises -> ProcessResult:
        """Run `make -s`, with no make settings from outside.

        A parent `make MOJO=...` exports its overrides to every child. The
        project owns its Makefile and must use its own stand-in.
        """
        var command: List[String] = ["env"]
        for name in [
            "MAKEFLAGS",
            "MFLAGS",
            "MAKEOVERRIDES",
            "MAKELEVEL",
            "MAKEFILES",
            "GNUMAKEFLAGS",
        ]:
            command.append("-u")
            command.append(name)
        command.append("make")
        command.append("-s")
        return run_program(command, 5, directory=self.tree.root)

    def calls(self) raises -> String:
        """Return the suites the compiler built, one to a line."""
        if not isfile(self.tree.root + "/invocations"):
            return String()
        return self.tree.read("invocations")

    def stamps(self) raises -> String:
        """Return the stamp names, sorted."""
        var listing = run_program(["ls", self.tree.root + "/cache/suites"], 10)
        return listing.output

    def close(self) raises:
        """Check the sentinel and remove the project."""
        assert_equal(self.tree.read("cache/bin/preserve"), "unchanged")
        self.tree.close()


def test_outer_make_overrides_cannot_replace_the_compiler() raises:
    var recipe = Recipe()
    recipe.tree.write("cache/suites-to-run", "tests/test_a.mojo aaa\n")
    # A parent make leaves these in the environment; the project's make
    # must not see them.
    var outer = [
        ("MAKEFLAGS", "-- MOJO=nonexistent-outer-compiler"),
        ("MAKEOVERRIDES", "MOJO=nonexistent-outer-compiler"),
        ("MFLAGS", "-e"),
        ("GNUMAKEFLAGS", "-e"),
        ("MAKEFILES", "nonexistent-outer-include"),
        ("MAKELEVEL", "7"),
    ]
    var saved = List[String]()
    for entry in outer:
        saved.append(getenv(entry[0]))
        _ = setenv(entry[0], entry[1])
    var result = recipe.make()
    for index in range(len(outer)):
        if saved[index]:
            _ = setenv(outer[index][0], saved[index])
        else:
            _ = unsetenv(outer[index][0])
    assert_equal(result.status, 0, result.output)
    assert_equal(recipe.calls(), "tests/test_a.mojo\n")
    assert_equal(recipe.stamps(), "test_a-aaa\n")
    recipe.close()


def test_an_empty_list_runs_no_compiler_and_writes_no_stamp() raises:
    var recipe = Recipe()
    recipe.tree.write("cache/suites-to-run", "")
    var result = recipe.make()
    assert_equal(result.status, 0, result.output)
    assert_equal(result.output, "")
    assert_equal(recipe.calls(), "")
    assert_equal(recipe.stamps(), "")
    recipe.close()


def test_each_suite_runs_and_gets_its_own_stamp() raises:
    var recipe = Recipe()
    recipe.tree.write(
        "cache/suites-to-run", "tests/test_a.mojo aaa\ntests/test_b.mojo bbb\n"
    )
    var result = recipe.make()
    assert_equal(result.status, 0, result.output)
    assert_equal(recipe.calls(), "tests/test_a.mojo\ntests/test_b.mojo\n")
    assert_equal(recipe.stamps(), "test_a-aaa\ntest_b-bbb\n")
    recipe.close()


def test_a_failed_build_is_not_stamped_or_hidden() raises:
    var recipe = Recipe(7)
    recipe.tree.write("cache/suites-to-run", "tests/test_a.mojo aaa\n")
    var result = recipe.make()
    assert_true(result.status != 0)
    assert_equal(recipe.calls(), "tests/test_a.mojo\n")
    assert_equal(recipe.stamps(), "")
    assert_true(
        result.output.find("Some CPU suites FAILED.") >= 0, result.output
    )
    recipe.close()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
