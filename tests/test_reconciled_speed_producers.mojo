# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact speed parsing and supported MapBuilder unit records."""

from extensions.carla.map_builder import MapBuilder
from extensions.carla.road_info import (
    LANE_DRIVING,
    LaneId,
    NO_JUNCTION,
    RoadId,
    SectionId,
)
from extensions.carla.speed_limits import read_speed_number
from std.testing import TestSuite, assert_equal, assert_raises


def test_zero_speed_numbers_with_and_without_exponents() raises:
    assert_equal(read_speed_number("0"), 0.0)
    assert_equal(read_speed_number("0e5"), 0.0)
    assert_equal(read_speed_number("0E5"), 0.0)
    with assert_raises(contains="underflows"):
        _ = read_speed_number("1e-400")


def test_builder_numeric_speed_records_keep_their_units() raises:
    var builder = MapBuilder()
    var r = builder.add_road(
        RoadId(1), "road", 10.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    var sec = builder.add_road_section(r, SectionId(0), 0.0)
    _ = builder.add_road_section_lane(
        r, sec, LaneId(-1), LANE_DRIVING, False, LaneId(0), LaneId(0)
    )
    builder.create_lane_speed(
        builder.lane(RoadId(1), LaneId(-1), 0.0), 0.0, 13.5, "m/s"
    )
    builder.create_road_speed(r, 0.0, "town", 50.0, "km/h")
    assert_equal(builder.roads[r].info.speeds[0].unit, "km/h")
    assert_equal(
        builder.roads[r].sections[0].lanes[0].info.speeds[0].unit, "m/s"
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
