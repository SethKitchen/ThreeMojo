# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The native source line lookup stays unique."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._coverage_loop_lines import unique_source_line


def test_the_result_line_is_unique() raises:
    """The constant-loop result occurs on one source line."""
    assert_equal(unique_source_line('print("RESULT constant loops")'), 60)


def test_a_repeated_fragment_is_refused() raises:
    """A fragment on more than one line fails closed."""
    with assert_raises(contains="Fixture identity is not unique: return total"):
        _ = unique_source_line("return total")


def main() raises:
    """Run the native source line tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
