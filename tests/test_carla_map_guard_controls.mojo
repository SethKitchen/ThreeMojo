# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Direct map boundary, metadata admission and retained helper controls."""

from extensions.carla.map import (
    Connection,
    Controller,
    EPSILON,
    Junction,
    Map,
    Signal,
    Waypoint,
    _add_conflict,
    _add_conflict_with_work,
    _map_locate_with_work,
    _preflight_map_metadata,
    _query_node_step_cost,
)
from extensions.carla.map_builder import (
    MapBuilder,
    _signal_lane_pose,
    _signal_side,
)
from extensions.carla.map_search import (
    MapBuildBudget,
    MapQueryBudget,
    _MapBuildWork,
    _MapQueryWork,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    ConId,
    JuncId,
    LANE_DRIVING,
    LANE_SHOULDER,
    LaneId,
    LaneType,
    RoadId,
    RoadInfoSpeed,
    SectionId,
)
from extensions.carla.speed_limits import NO_SPEED_LIMIT
from math.vector3 import Vector3
from std.math import nan
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from tests.test_carla_cross_candidate_certificates import _road


def _map() raises -> Map:
    var roads = List[Road]()
    roads.append(_road())
    return Map(roads^, List[Junction](), List[Signal](), List[Controller]())


def _waypoint(s: Float64 = 1.0) -> Waypoint:
    return Waypoint(RoadId(1), SectionId(0), LaneId(-1), s)


def test_map_metered_lookup_rejects_bad_road_and_missing_lane() raises:
    var map = _map()
    var work = _MapBuildWork(MapBuildBudget())
    for road in [-1, 2]:
        var waypoint = _waypoint()
        waypoint.road_id = RoadId(road)
        with assert_raises():
            _ = _map_locate_with_work(
                map.roads, map._road_index, waypoint, work
            )
    var absent = _waypoint()
    absent.lane_id = LaneId(-2)
    with assert_raises(contains="no lane"):
        _ = _map_locate_with_work(map.roads, map._road_index, absent, work)
    var query_work = _MapQueryWork(MapQueryBudget())
    with assert_raises(contains="no lane"):
        _ = map._query_locate(absent, query_work)
    assert_equal(map._query_locate(_waypoint(), query_work), (0, 0, 0))


def test_map_query_price_preserves_each_mode_and_rejects_overflow() raises:
    for goal in [False, True]:
        for witness in [False, True]:
            var fixed = 42 if goal else 36
            if witness:
                fixed += 40
            assert_equal(_query_node_step_cost(0, goal, witness), fixed)
            assert_equal(_query_node_step_cost(1, goal, witness), 100 + fixed)
            with assert_raises(contains="not representable"):
                _ = _query_node_step_cost(-1, goal, witness)
            with assert_raises(contains="not representable"):
                _ = _query_node_step_cost(9223372036854775807, goal, witness)


def test_map_speed_station_checks_each_domain_failure() raises:
    var map = _map()
    for s in [nan[DType.float64](), -0.5, 4.5]:
        with assert_raises(contains="finite and within the road"):
            _ = map.speed_limit_at(_waypoint(s))
    for s in [0.0, 1.0, 4.0]:
        assert_equal(Bool(map.speed_limit_at(_waypoint(s))), False)


def test_map_rejects_mutated_nonnumeric_lane_speed() raises:
    var map = _map()
    var speed = RoadInfoSpeed(0.0, 10.0, "Town")
    speed.kind = NO_SPEED_LIMIT
    map.roads[0].sections[0].lanes[0].info.speeds.append(speed^)
    with assert_raises(contains="lane speed must be numeric"):
        _ = map.speed_limit_at(_waypoint())


def test_build_step_checks_distance_and_section_boundary() raises:
    var map = _map()
    for distance in [0.0, -1.0, nan[DType.float64]()]:
        with assert_raises(contains="positive distance"):
            _ = map._build_next(_waypoint(), distance)
    assert_equal(map._build_next(_waypoint(), EPSILON).s, Float64(1.0))
    with assert_raises(contains="remain in its section"):
        _ = map._build_next(_waypoint(3.0), 2.0)
    assert_true(map._build_next(_waypoint(1.0), 1.0).s > 1.0)
    with assert_raises(contains="left the road"):
        _ = map._build_next(_waypoint(-1.0), 0.5)


def test_map_build_helpers_reject_unrepresentable_pose_work() raises:
    var map = _map()
    map.roads[0].info.geometries[0].geometry.kind.value = 2
    map.roads[0].info.geometries[0].geometry.curvature_start = 1e308
    map.roads[0].info.geometries[0].geometry.curvature_end = 1e308
    with assert_raises(contains="pose quadrature work"):
        _ = map._build_transform(_waypoint())
    with assert_raises(contains="point quadrature work"):
        map._reserve_build_point(0, 0, 1.0)
    var work = _MapQueryWork(MapQueryBudget())
    with assert_raises(contains="unresolved quadrature work"):
        map._validate_query_pose(_waypoint(), work)


def test_metered_junction_query_rejects_invalid_mask_before_lookup() raises:
    var map = _map()
    var work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="Lane type is not valid"):
        _ = map._junction_waypoints_with_work(JuncId(1), LaneType(0), work)


def test_conflict_helpers_keep_idempotent_order_and_metered_parity() raises:
    var plain_roads = List[RoadId]()
    var plain_conflicts = List[List[RoadId]]()
    var metered_roads = List[RoadId]()
    var metered_conflicts = List[List[RoadId]]()
    var work = _MapBuildWork(MapBuildBudget())
    for other in [2, 3, 2]:
        _add_conflict(plain_roads, plain_conflicts, RoadId(1), RoadId(other))
        _add_conflict_with_work(
            metered_roads, metered_conflicts, RoadId(1), RoadId(other), work
        )
    _add_conflict(plain_roads, plain_conflicts, RoadId(4), RoadId(2))
    _add_conflict_with_work(
        metered_roads, metered_conflicts, RoadId(4), RoadId(2), work
    )
    assert_equal(plain_roads, metered_roads)
    assert_equal(len(plain_roads), 2)
    assert_equal(plain_conflicts[0], [RoadId(2), RoadId(3)])
    assert_equal(plain_conflicts[1], [RoadId(2)])
    assert_equal(plain_conflicts, metered_conflicts)
    assert_true(work.steps > 0)


def test_metadata_preflight_counts_nested_conflict_records() raises:
    var junction = Junction(JuncId(1), "crossing")
    junction.conflict_roads = [RoadId(1)]
    junction.conflicts.append([RoadId(2), RoadId(3)])
    var junctions = List[Junction]()
    junctions.append(junction^)
    var work = _MapBuildWork(MapBuildBudget())
    _preflight_map_metadata(junctions, List[Signal](), List[Controller](), work)
    assert_equal(work.records, 5)
    assert_equal(work.steps, 2)


def test_builder_numeric_speed_overloads_retain_source_units() raises:
    var builder = MapBuilder()
    builder.roads.append(_road())
    builder.create_lane_speed((0, 0, 0), 0.0, Float64(36.0), "km/h")
    builder.create_road_speed(0, 0.0, "motorway", Float64(10.0), "m/s")
    var map = builder.build()
    assert_equal(map.speed_limit_at(_waypoint()).value().value, Float64(10.0))
    assert_equal(map.roads[0].info.speeds[0].unit, "m/s")
    assert_equal(map.roads[0].sections[0].lanes[0].info.speeds[0].unit, "km/h")


def test_signal_helpers_refuse_center_side_and_unresolved_pose() raises:
    var map = _map()
    var work = _MapBuildWork(MapBuildBudget())
    var center = _waypoint()
    center.lane_id = LaneId(0)
    with assert_raises(contains="Lane 0 has no lane beside it"):
        _ = _signal_side(map, center, True, work)
    map.roads[0].info.geometries[0].geometry.kind.value = 2
    map.roads[0].info.geometries[0].geometry.curvature_start = 1e308
    map.roads[0].info.geometries[0].geometry.curvature_end = 1e308
    with assert_raises(contains="Sign relocation cannot resolve"):
        _ = _signal_lane_pose(map, _waypoint(), work)


def test_junction_queries_keep_empty_and_matching_road_cases() raises:
    var map = _map()
    map.junctions.append(Junction(JuncId(1), "empty"))
    assert_equal(len(map.junction_waypoints(JuncId(1), LANE_DRIVING)), 0)
    map.junctions[0].connections.append(
        Connection(ConId(1), RoadId(1), RoadId(1))
    )
    var work = _MapBuildWork(MapBuildBudget())
    var pairs = map._junction_waypoints_with_work(JuncId(1), LANE_DRIVING, work)
    assert_equal(len(pairs), 1)
    assert_equal(pairs[0][0].road_id, RoadId(1))
    assert_equal(pairs[0][1].lane_id, LaneId(-1))
    assert_true(pairs[0][1].s > pairs[0][0].s)
    var rejected = map._junction_waypoints_with_work(
        JuncId(1), LANE_SHOULDER, work
    )
    assert_equal(len(rejected), 0)


def test_legacy_private_nearest_wrapper_retains_exact_line_result() raises:
    var map = _map()
    var result = map._nearest_on_segment(0, Vector3(2, 3, 0))
    assert_equal(result[0].road_id, RoadId(1))
    assert_equal(result[0].s, Float64(2.0))
    assert_equal(result[1], Float64(9.0))
    assert_equal(result[2][0], Float64(2.0))
    assert_equal(result[2][1], Float64(0.0))


def test_arc_center_cancellation_still_obeys_heading_subdivision() raises:
    # At offset=-radius, every center lies at the circle center, but the
    # directed frame still rotates. The turn criterion must independently
    # subdivide this zero-position-error lane.
    var road = _road()
    road.info.geometries[0].geometry.kind.value = 1
    road.info.geometries[0].geometry.curvature_start = 1.0
    road.info.geometries[0].geometry.curvature_end = 1.0
    road.info.lane_offsets[0].polynomial = CubicPolynomial.constant(2.0)
    var roads = List[Road]()
    roads.append(road^)
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    assert_true(map.segment_count() >= 8)
    var first = map.compute_transform(_waypoint(0.0))
    var last = map.compute_transform(_waypoint(4.0))
    assert_equal(first.location.x, last.location.x)
    assert_equal(first.location.y, last.location.y)
    assert_equal(first.location.z, last.location.z)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
