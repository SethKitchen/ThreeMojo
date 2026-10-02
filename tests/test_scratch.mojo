# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Isolated test paths supplied by the test and coverage runners."""

from std.os import getenv, setenv
from std.pathlib import Path
from std.testing import TestSuite, assert_true, assert_raises


def temporary_path(name: String) raises -> String:
    """Return a file or directory under this suite's temporary root.

    Args:
        name: A relative name. An empty name returns the root with a slash.

    Returns:
        An absolute path inside the runner's private temporary directory.

    Raises:
        Error: If no test runner supplied a root, or the name escapes it.
    """
    var root = getenv("THREEMOJO_TEST_TMPDIR", "")
    if root == "":
        raise Error(
            "Run this suite through tools/run_suite.py or coverage_io.py"
        )
    if (
        name.startswith("/")
        or name.find("\\") >= 0
        or name == ".."
        or name.startswith("../")
        or name.endswith("/..")
        or name.find("/../") >= 0
    ):
        raise Error("A temporary test name must stay inside its root")
    return root + "/" + name


def test_the_runner_provides_an_existing_root() raises:
    assert_true(Path(temporary_path("")).exists())
    assert_true(temporary_path("example.bin").endswith("/example.bin"))


def test_a_temporary_name_cannot_escape_its_root() raises:
    for name in ["/absolute", "..", "../x", "x/..", "x/../y", "x\\y"]:
        with assert_raises(contains="inside its root"):
            _ = temporary_path(name)


def test_no_shared_fallback_is_used_without_a_runner() raises:
    var saved = getenv("THREEMOJO_TEST_TMPDIR", "")
    _ = setenv("THREEMOJO_TEST_TMPDIR", "")
    with assert_raises(contains="Run this suite"):
        _ = temporary_path("example.bin")
    _ = setenv("THREEMOJO_TEST_TMPDIR", saved)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
