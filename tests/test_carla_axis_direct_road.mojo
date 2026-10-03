# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Direct Road proof controls, separate from required full-Map construction.

The translated-grid Map case separately checks explicit construction refusal.
These direct-Road controls retain the successful exact minimum and tie cases.
"""

from extensions.carla.geometry import LINE, RoadGeometry
from extensions.carla.lane_refinement import _axis_lane_minimum
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    LANE_DRIVING, LaneId, NO_JUNCTION, RoadId, RoadInfoElevation,
    RoadInfoGeometry, RoadInfoLaneOffset, RoadInfoLaneWidth, SectionId,
)
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_true


def test_direct_road_translated_grid_and_exact_tie() raises:
    var base = Float64(1e20)
    var length = Float64(81920.0)
    var geometry = RoadGeometry(LINE, base, 0.0, 0.0, 0.0, length)
    var road = Road(RoadId(1), "grid", base + length, NO_JUNCTION, RoadId(0), RoadId(0), True)
    _ = road.add_section(SectionId(0), base)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(base, CubicPolynomial.constant(0.0002))
    )
    road.info.geometries.append(RoadInfoGeometry(base, geometry^))
    road.info.elevations.append(RoadInfoElevation(0.0, CubicPolynomial.constant(0.0)))
    road.info.lane_offsets.append(RoadInfoLaneOffset(0.0, CubicPolynomial.constant(0.0)))
    # Legal stored s values are base + k*16384. The x coordinate is exactly
    # k*16384, and y/z are constant. These answers follow from integer gaps.
    for sample in [
        (10000.0, base + 16384.0),
        (8192.0, base),
        (5000.0, base),
        (-1.0, base),
        (100000.0, base + length),
    ]:
        var found = _axis_lane_minimum(
            road, 0, 0, base, base + length,
            Vector3(Float32(sample[0]), Float32(0.0001), 0),
        )
        assert_true(Bool(found))
        ref result = found.value()
        assert_equal(result[0], sample[1])
        assert_equal(result[2][0], sample[1] - base)
        assert_true(result[3] >= 1)
        assert_true(result[4] >= 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
