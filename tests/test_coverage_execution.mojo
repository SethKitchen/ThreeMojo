# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""An unstaged capture suite is refused before the compiler is bound."""

from std.testing import TestSuite, assert_raises

from tools.coverage_execution import execution_contract


def test_an_unstaged_suite_is_refused() raises:
    """A suite that is not in the staged inputs is refused."""
    with assert_raises(contains="Capture suite inventory is invalid or not staged"):
        _ = execution_contract(
            '{"inputs":["mod.mojo"],"suites":["tests/test_missing.mojo"],'
            + '"mojo":"mojo","python":"/usr/bin/python3"}',
            "/tmp",
            "/tmp/build",
        )


def main() raises:
    """Run the execution contract tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
