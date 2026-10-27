# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed coverage-invariant record fails the gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_invariant_gate import invariant_record


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="coverage invariant successor: unreviewed migration record"
    ):
        invariant_record(
            String("").as_bytes(), String("").as_bytes(), "", False
        )


def main() raises:
    """Run the coverage-invariant gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
