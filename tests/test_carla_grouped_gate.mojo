# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed grouped consumer fails the token gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_grouped_gate import grouped_table


def test_a_changed_module_is_refused() raises:
    """Stand-in sources do not have the reviewed digest."""
    with assert_raises(contains="Reviewed grouped consumer graph changed"):
        _ = grouped_table("def main():\n    pass\n", "def main():\n    pass\n")


def main() raises:
    """Run the grouped-gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
