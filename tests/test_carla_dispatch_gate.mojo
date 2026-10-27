# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed support and dispatch record fails the gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_dispatch_gate import dispatch_pin, dispatch_record


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="curve support/dispatch contract: unreviewed migration record"
    ):
        dispatch_record(String("").as_bytes())


def test_a_changed_pin_is_refused() raises:
    """Bytes that are not the recorded pin fail closed."""
    with assert_raises(
        contains=(
            "curve support/dispatch contract: standalone historical pin input"
            " changed: pins.json"
        )
    ):
        dispatch_pin(String("nope").as_bytes(), "00", "pins.json")


def main() raises:
    """Run the support and dispatch gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
