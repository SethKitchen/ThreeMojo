# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed accepted successor record fails the gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_accepted_gate import accepted_digest, accepted_record


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="accepted source successor: unreviewed migration record"
    ):
        accepted_record(String("").as_bytes(), String("").as_bytes(), "", False)


def test_a_changed_pin_is_refused() raises:
    """A different active pin digest fails closed."""
    with assert_raises(
        contains=(
            "accepted source successor: unreviewed runtime pin successor:"
            " runtime-source-pins.json"
        )
    ):
        accepted_digest(
            String("nope").as_bytes(), "00", "after", "runtime-source-pins.json"
        )


def test_a_changed_pin_reconstruction_is_refused() raises:
    """A different reconstructed pin digest fails closed."""
    with assert_raises(
        contains=(
            "accepted source successor: historical pins failed reconstruction"
        )
    ):
        accepted_digest(
            String("nope").as_bytes(),
            "00",
            "before",
            "runtime-source-pins.json",
        )


def main() raises:
    """Run the accepted successor gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
