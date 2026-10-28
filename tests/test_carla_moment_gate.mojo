# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed moment producer fails the token gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_moment_gate import moment_finiteness


def test_a_changed_module_is_refused() raises:
    """Stand-in sources do not have the reviewed digest."""
    with assert_raises(
        contains="Moment producer count/work/arithmetic graph changed"
    ):
        _ = moment_finiteness(
            "def main():\n    pass\n",
            "def main():\n    pass\n",
            "def main():\n    pass\n",
            "def main():\n    pass\n",
        )


def main() raises:
    """Run the moment-gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
