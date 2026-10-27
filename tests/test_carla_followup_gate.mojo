# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed coverage-followup record fails the gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_followup_gate import followup_digest, followup_record


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="coverage followup successor: unreviewed migration record"
    ):
        followup_record(String("").as_bytes(), String("").as_bytes(), "", False)


def test_a_changed_pin_reconstruction_is_refused() raises:
    """A different reconstructed pin digest fails closed."""
    with assert_raises(
        contains=(
            "coverage followup successor: historical pin reconstruction failed"
        )
    ):
        followup_digest(
            String("nope").as_bytes(),
            "00",
            "before",
            "runtime-source-pins.json",
        )


def main() raises:
    """Run the coverage-followup gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
