# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed ideal-projection digest fails the gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_ideal_gate import ideal_digest


def test_a_changed_legacy_source_is_refused() raises:
    """Bytes that are not the historical ideal source fail closed."""
    with assert_raises(contains="historical ideal source changed"):
        ideal_digest(String("").as_bytes(), "legacy")


def main() raises:
    """Run the ideal gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
