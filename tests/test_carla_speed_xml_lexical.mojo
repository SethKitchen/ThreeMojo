# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Reject malformed speed numbers through unchanged OpenDRIVE boundaries."""
from extensions.carla.opendrive import load_opendrive
from tests.test_carla_speed_units import speed_town
from std.testing import TestSuite, assert_raises


def test_road_and_lane_speed_reject_malformed_decimal_placements() raises:
    for text in ["0f", "0F", "+.", "1..0", "1e2e3", "0-0", "0+0"]:
        with assert_raises(contains="numeric max value"):
            _ = load_opendrive(speed_town("<speed max='" + text + "'/>"))
        with assert_raises(contains="numeric max value"):
            _ = load_opendrive(
                speed_town("", "<speed sOffset='0' max='" + text + "'/>")
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
