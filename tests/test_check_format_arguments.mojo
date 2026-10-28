# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The old format command exceeds one shell argument."""

from std.sys import CompilationTarget
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tools.check_format_arguments import (
    long_format_paths,
    reject_oversized_shell_argument,
    repeated_shell_command,
)


def test_the_old_command_exceeds_one_argument() raises:
    """1789 long paths make a command longer than 32 pages."""
    var paths = long_format_paths()
    assert_equal(len(paths), 1789)
    assert_equal(paths[0], "src/0000_" + "x" * 67 + ".mojo")
    assert_equal(paths[1788], "src/1788_" + "x" * 67 + ".mojo")
    var command = repeated_shell_command(paths)
    assert_true(command.byte_length() > 131072)
    assert_true(command.startswith("for f in src/0000_"))
    assert_true(command.endswith("; do :; done; "))


def test_linux_refuses_the_old_command() raises:
    """Linux with 4096-byte pages refuses the old command."""
    var command = repeated_shell_command(long_format_paths())
    if CompilationTarget.is_linux():
        reject_oversized_shell_argument(command)
    else:
        with assert_raises(contains="fits in one shell argument"):
            reject_oversized_shell_argument("true")


def main() raises:
    """Run the format-argument tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
