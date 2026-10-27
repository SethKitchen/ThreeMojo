# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The diagnostic manifest tool keeps the requested loop rows."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools.check_coverage_loop_fixture import diagnostic_manifest


def test_a_schema_row_and_the_requested_loops_stay() raises:
    """A `P` row stays, and only the named module lines stay with it."""
    var lines = List[Int]()
    lines.append(3)
    lines.append(9)
    assert_equal(
        diagnostic_manifest(
            "P schema\nB fixture 3 kept\nR other 3 drop\nB fixture 9 kept\n",
            "fixture",
            lines,
        ),
        "P schema\nB fixture 3 kept\nB fixture 9 kept\n",
    )


def test_a_missing_loop_line_is_refused() raises:
    """A requested line that the manifest does not contain fails closed."""
    var lines = List[Int]()
    lines.append(4)
    with assert_raises(contains="Diagnostic loop identity is missing"):
        _ = diagnostic_manifest("P schema\n", "fixture", lines)


def main() raises:
    """Run the diagnostic manifest tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
