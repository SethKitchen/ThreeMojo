# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The constant-loop manifest keeps only the requested fixture rows."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools.check_coverage_loop_fixture import diagnostic_manifest


def test_the_manifest_keeps_the_requested_loops() raises:
    """A masked manifest projects the named fixture lines."""
    var lines = List[Int]()
    lines.append(4)
    lines.append(9)
    var manifest = (
        "P schema digest\nB other 4\nB fixture 4\nR fixture 9 T\nB fixture 3\n"
    )
    assert_equal(
        diagnostic_manifest(manifest, "fixture", lines),
        "P schema digest\nB fixture 4\nR fixture 9 T\n",
    )
    with assert_raises(contains="Diagnostic loop identity is missing"):
        _ = diagnostic_manifest("P schema digest\n", "fixture", lines)


def main() raises:
    """Run the manifest projection tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
