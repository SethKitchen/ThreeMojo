# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed selection producer fails the token gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_selection_gate import (
    selection_catalog_checked,
    selection_checked,
    selection_finiteness,
)


def test_a_changed_module_is_refused() raises:
    """Stand-in sources do not have the reviewed digest."""
    with assert_raises(
        contains="Selection producer/input/error/phase graph changed: "
        + "extensions/carla/spiral_grouped_roundoff_proof.mojo"
    ):
        _ = selection_finiteness(
            "def main():\n    pass\n",
            "def main():\n    pass\n",
            "def main():\n    pass\n",
            "def main():\n    pass\n",
        )


def test_wrong_producer_names_fail_before_the_tokens() raises:
    """A wrong producer set is reported before the module tokens are read."""
    var payload = (
        '{"modules":{"other.mojo":"def main():\\n    pass\\n"},'
        + '"expected":["extensions/carla/spiral_grouped_roundoff_proof.mojo",'
        + '"extensions/carla/spiral_roundoff_proof.mojo"],'
        + '"message":"Wrong selection producer set",'
        + '"interval":"def main():\\n    pass\\n",'
        + '"trig":"def main():\\n    pass\\n"}'
    )
    with assert_raises(contains="Wrong selection producer set"):
        _ = selection_checked(payload)


def test_matching_producer_names_reach_the_token_gate() raises:
    """The reviewed paths still refuse a changed producer token."""
    var grouped = "extensions/carla/spiral_grouped_roundoff_proof.mojo"
    var roundoff = "extensions/carla/spiral_roundoff_proof.mojo"
    var payload = (
        '{"modules":{"'
        + grouped
        + '":"def main():\\n    pass\\n","'
        + roundoff
        + '":"def main():\\n    pass\\n"},"expected":["'
        + grouped
        + '","'
        + roundoff
        + '"],"message":"Wrong selection producer set",'
        + '"interval":"def main():\\n    pass\\n",'
        + '"trig":"def main():\\n    pass\\n"}'
    )
    with assert_raises(
        contains="Selection producer/input/error/phase graph changed: "
        + grouped
    ):
        _ = selection_checked(payload)


def test_wrong_catalog_names_fail_before_the_tokens() raises:
    """The selection label names a wrong producer set before the tokens."""
    var payload = (
        '{"modules":{"other.mojo":"def main():\\n    pass\\n"},'
        + '"interval":"def main():\\n    pass\\n",'
        + '"trig":"def main():\\n    pass\\n"}'
    )
    with assert_raises(contains="Wrong selection producer set"):
        _ = selection_catalog_checked(payload)


def test_catalog_paths_reach_the_token_gate() raises:
    """The stored producer paths still refuse a changed producer token."""
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
        _ = selection_catalog_checked(payload)


def main() raises:
    """Run the selection-gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
