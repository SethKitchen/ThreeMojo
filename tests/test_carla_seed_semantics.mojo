# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Seed scheduling preserves exact ties and explicit finite-work failures."""
from extensions.carla.curve_bounds import _lane_jet
from extensions.carla.curve_distance import (
    _wide_point_order,
)
from extensions.carla.lane_distance import (
    _wide_plan_contains,
)
from extensions.carla.geometry import SPIRAL, RoadGeometry, with_spiral
from extensions.carla.lane_refinement import (
    _checked_center,
    _local_seed,
    _refine_lane_certificate,
)
from extensions.carla.map import (
    Map,
    Junction,
    Signal,
    Controller,
    _use_projected_spiral_seed,
)
from extensions.carla.road import Road
from extensions.carla.road_info import RoadId
from tests.test_carla_cross_candidate_certificates import _road
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_raises,
)


def _spiral_road(id: Int = 1, width: Float64 = 2.0) raises -> Road:
    var road = _road(id=id, width=width)
    road.info.geometries[0].geometry = with_spiral(
        RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, 4.0), 0.0, 0.0
    )
    return road^


def test_exact_rounded_plateau_retains_current_witness_and_classification() raises:
    var road = _spiral_road()
    road.info.geometries[0].geometry.x = 1.0
    # Every positive displacement is less than one quarter ULP at x=1.
    # The y and z expressions are exactly zero. Thus all centers are (1,0,0).
    var low = bitcast[DType.float64](UInt64(0x3C10000000000000))
    var high = bitcast[DType.float64](UInt64(0x3C30000000000000))
    var query = Vector3(1, 0, 0)
    var wide: Array[Float64, 3] = [1.0, 0.0, 0.0]
    var domain = _lane_jet(road, 0, 0, low, high)
    var bounds = (
        domain[0].rounded_value(),
        -domain[1].rounded_value(),
        domain[2].rounded_value(),
    )
    assert_true(
        _use_projected_spiral_seed(road, 0, 0, low, high, bounds, query)
    )
    var first = _refine_lane_certificate(road, 0, 0, low, high, query, low, 0.0)
    var last = _refine_lane_certificate(road, 0, 0, low, high, query, high, 0.0)
    assert_equal(first.s, low)
    assert_equal(last.s, high)
    assert_true(first.exact_witness and last.exact_witness)
    assert_equal(_wide_point_order(first.point, last.point, wide), 0)
    for axis in range(3):
        assert_equal(first.point[axis], wide[axis])
        assert_equal(last.point[axis], wide[axis])
    assert_true(_wide_plan_contains(first.point, wide, 2.0))
    assert_true(_wide_plan_contains(last.point, wide, 2.0))
    var terms = 0
    var local = _local_seed(
        road, 0, 0, low, high, wide, low, first.point, terms, 2000000
    )
    assert_equal(local[0], low)
    assert_true(terms > 0 and terms <= 2000000)


def test_tolerance_close_points_are_not_exact_ties() raises:
    var query: Array[Float64, 3] = [1.0, 0.0, 0.0]
    var exact: Array[Float64, 3] = [1.0, 0.0, 0.0]
    var adjacent: Array[Float64, 3] = [
        bitcast[DType.float64](UInt64(0x3FF0000000000001)),
        0.0,
        0.0,
    ]
    assert_equal(_wide_point_order(exact, adjacent, query), -1)
    assert_equal(_wide_point_order(adjacent, exact, query), 1)
    var road = _spiral_road()
    road.info.geometries[0].geometry.x = 1.0
    var terms = 0
    var point = _checked_center(road, 0, 0, 0.0, terms, 2000000)
    var seeded = _local_seed(
        road, 0, 0, 0.0, 0.25, query, 0.0, point, terms, 2000000
    )
    assert_equal(seeded[0], 0.0)
    assert_equal(_wide_point_order(seeded[1], exact, query), 0)


def test_duplicate_spirals_keep_segment_tie_order_and_deterministic_station() raises:
    var roads = List[Road]()
    roads.append(_spiral_road(id=1, width=2.0))
    roads.append(_spiral_road(id=2, width=4.0))
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    var query = Vector3(1, 0, 0)
    var first = map.certified_closest_waypoint_on_road(query).value()
    assert_equal(first.road_id, RoadId(1))
    for _ in range(3):
        var again = map.certified_closest_waypoint_on_road(query).value()
        assert_equal(again.road_id, first.road_id)
        assert_equal(again.lane_id, first.lane_id)
        assert_equal(
            bitcast[DType.uint64](again.s), bitcast[DType.uint64](first.s)
        )
        assert_true(Bool(map.certified_waypoint(query)))


def test_initial_seed_does_not_bypass_zero_work_refusals() raises:
    var road = _spiral_road()
    var query = Vector3(1, 0, 0)
    for seed in [Float64(1.0), Float64(2.0)]:
        with assert_raises(contains="interval work limit"):
            _ = _refine_lane_certificate(
                road, 0, 0, 0.0, 4.0, query, seed, 0.0, max_nodes=0
            )
        with assert_raises(contains="quadrature work limit"):
            _ = _refine_lane_certificate(
                road, 0, 0, 0.0, 4.0, query, seed, 0.0, max_terms=0
            )
        var result = _refine_lane_certificate(
            road, 0, 0, 0.0, 4.0, query, seed, 0.0
        )
        assert_true(result.nodes <= 16384 and result.terms <= 2000000)
        assert_equal(result.point[0], 1.0)
        assert_equal(result.point[1], 0.0)
        assert_equal(result.point[2], 0.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
