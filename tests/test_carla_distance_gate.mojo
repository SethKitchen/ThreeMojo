# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed spiral-domain source fails the token gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_distance_gate import distance_validation


def test_a_changed_module_is_refused() raises:
    """Neither stand-in source has the reviewed digest."""
    with assert_raises(
        contains="Distance validation, derivative/association checks"
    ):
        _ = distance_validation(
            "def main():\n    pass\n", "def main():\n    pass\n"
        )


def main() raises:
    """Run the distance-gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
