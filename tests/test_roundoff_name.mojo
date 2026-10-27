# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The roundoff envelope name follows the module path."""

from std.testing import TestSuite, assert_equal

from tools._roundoff_name import roundoff_envelope_name


def test_the_envelope_name_follows_the_module_path() raises:
    """Only the grouped proof path selects the grouped envelope."""
    assert_equal(
        roundoff_envelope_name(
            "extensions/carla/spiral_grouped_roundoff_proof.mojo"
        ),
        "_try_spiral_grouped_roundoff_envelope",
    )
    assert_equal(
        roundoff_envelope_name("extensions/carla/spiral_roundoff_proof.mojo"),
        "_try_spiral_roundoff_envelope",
    )
    assert_equal(roundoff_envelope_name("a"), "_try_spiral_roundoff_envelope")
    assert_equal(
        roundoff_envelope_name("/spiral_grouped_roundoff_proof.mojo"),
        "_try_spiral_grouped_roundoff_envelope",
    )


def main() raises:
    """Run the roundoff name tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
