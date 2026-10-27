# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed lane-control record fails the gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_lane_control_gate import lane_control_record


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(contains="lane-control migration record changed"):
        lane_control_record(String("").as_bytes())


def main() raises:
    """Run the lane-control gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
