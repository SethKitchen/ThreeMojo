# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

from extensions.carla.opendrive import load_opendrive_file
from std.testing import TestSuite, assert_true


def test_existing_town_fixture_loads_with_lane_queries() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    assert_true(map.segment_count() > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
