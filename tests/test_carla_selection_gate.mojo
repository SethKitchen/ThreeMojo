# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed selection producer fails the token gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_selection_gate import selection_finiteness


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


def main() raises:
    """Run the selection-gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
