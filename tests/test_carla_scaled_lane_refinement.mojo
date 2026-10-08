# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent scale controls for the shipped sampled-center evaluator."""

from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.geometry import PARAM_POLY3, RoadGeometry, _Sample
from extensions.carla.lane_refinement import _refine_lane
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    LANE_DRIVING,
    LaneId,
    NO_JUNCTION,
    RoadId,
    RoadInfoElevation,
    RoadInfoGeometry,
    RoadInfoLaneOffset,
    RoadInfoLaneWidth,
    SectionId,
)
from math.vector3 import Vector3
from std.math import inf
from std.testing import TestSuite, assert_equal, assert_true


def _scaled_road(scale: Float64) raises -> Road:
    var geometry = RoadGeometry(PARAM_POLY3, 0.0, 0.0, 0.0, 0.0, 1.0)
    geometry.samples.append(_Sample(-scale, 2.0 * scale, 0.0, 1.0, 0.0))
    geometry.samples.append(_Sample(scale, 2.0 * scale, 1.0, 1.0, 0.0))
    var road = Road(
        RoadId(1), "scaled", 1.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(0.0, CubicPolynomial.constant(2.0 * scale))
    )
    road.info.geometries.append(RoadInfoGeometry(0.0, geometry^))
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial.constant(0.0))
    )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(0.0, CubicPolynomial.constant(scale))
    )
    return road^


def test_noncoincident_underflowed_seed_is_not_a_global_zero_certificate() raises:
    var road = _scaled_road(1e-200)
    var location = Vector3(0, 0, 0)
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var seed = road._lane_center(0, 0, 0.1)
    var score = road._lane_distance_squared(0, 0, 0.1, location)
    assert_equal(score, 0.0)
    assert_true(abs(seed[0]) > 0.0)
    assert_true(abs(seed[1]) > 0.0)
    var result = _refine_lane(road, 0, 0, 0.0, 1.0, location, 0.1, score)
    var center = road._lane_center(0, 0, result[0])
    # u=(2s-1)*scale and v=2*scale give their exact continuous minimum
    # at s=1/2. The shipped interpolation evaluates u there as exact zero.
    assert_equal(result[0], 0.5)
    assert_equal(center[0], 0.0)
    assert_true(abs(center[1]) > 0.0)
    assert_equal(_wide_point_order(center, seed, query), -1)


def test_overflowed_seed_square_does_not_reject_finite_centers() raises:
    var road = _scaled_road(1e200)
    var location = Vector3(0, 0, 0)
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var seed = road._lane_center(0, 0, 0.1)
    var score = road._lane_distance_squared(0, 0, 0.1, location)
    assert_equal(score, inf[DType.float64]())
    var result = _refine_lane(road, 0, 0, 0.0, 1.0, location, 0.1, score)
    var center = road._lane_center(0, 0, result[0])
    assert_equal(result[0], 0.5)
    assert_equal(center[0], 0.0)
    assert_equal(_wide_point_order(center, seed, query), -1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
