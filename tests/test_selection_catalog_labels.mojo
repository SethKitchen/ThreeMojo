# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The selection labels are returned after the producer check."""

from std.testing import TestSuite, assert_raises

from tools.carla_selection_gate import selection_catalog_then_labels


def test_wrong_names_fail_before_the_labels_are_returned() raises:
    """A wrong producer set fails before the labels are returned."""
    var payload = (
        '{"modules":{"other.mojo":"def main():\\n    pass\\n"},'
        + '"interval":"def main():\\n    pass\\n",'
        + '"trig":"def main():\\n    pass\\n"}'
    )
    with assert_raises(contains="Wrong selection producer set"):
        _ = selection_catalog_then_labels(payload)


def test_a_changed_token_fails_before_the_labels_are_returned() raises:
    """A changed producer token fails before the labels are returned."""
    var grouped = "extensions/carla/spiral_grouped_roundoff_proof.mojo"
    var roundoff = "extensions/carla/spiral_roundoff_proof.mojo"
    var payload = (
        '{"modules":{"'
        + grouped
        + '":"def main():\\n    pass\\n","'
        + roundoff
        + '":"def main():\\n    pass\\n"},'
        + '"interval":"def main():\\n    pass\\n",'
        + '"trig":"def main():\\n    pass\\n"}'
    )
    with assert_raises(
        contains="Selection producer/input/error/phase graph changed: "
        + grouped
    ):
        _ = selection_catalog_then_labels(payload)


def main() raises:
    """Run the selection-label return tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
