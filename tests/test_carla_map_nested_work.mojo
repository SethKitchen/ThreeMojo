# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Nested linear and quadratic helpers must be admitted before their calls."""

from extensions.carla.map import Controller, Junction, Map, Signal, Waypoint
from extensions.carla.map_builder import MapBuilder
from extensions.carla.map_search import (
    MapBuildBudget,
    MapQueryBudget,
    _MapBuildWork,
    _MapQueryWork,
)
from math.vector3 import Vector3
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Lane, LaneSection, Road
from extensions.carla.road_info import (
    ConId,
    JuncId,
    LANE_DRIVING,
    LaneId,
    RoadId,
    RoadInfoLaneWidth,
    SectionId,
)
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from tests.test_carla_cross_candidate_certificates import _road


def _many_sections(count: Int, duplicate_start: Bool = False) raises -> Road:
    var road = _road()
    road.length = Float64(count)
    road.info.geometries[0].geometry.length = Float64(count)
    road.sections.clear()
    for i in range(count):
        var station = Float64(i)
        if duplicate_start and i == 1:
            station = 0.0
        var section = LaneSection(SectionId(i), station)
        var lane = Lane(LaneId(-1), SectionId(i), station)
        lane.type = LANE_DRIVING
        lane.info.widths.append(
            RoadInfoLaneWidth(station, CubicPolynomial.constant(2.0))
        )
        section.lanes.append(lane^)
        road.sections.append(section^)
    return road^


def _many_lane_junction(count: Int) raises -> MapBuilder:
    var builder = MapBuilder()
    var road = _road()
    road.predecessor = RoadId(99)
    road.successor = RoadId(99)
    road.sections[0].lanes.clear()
    for i in range(count):
        var lane = Lane(LaneId(i + 1), SectionId(0), 0.0)
        lane.predecessor = LaneId(99)
        lane.successor = LaneId(99)
        road.sections[0].lanes.append(lane^)
    builder.roads.append(road^)
    builder.add_junction(JuncId(7), "nested")
    builder.add_connection(JuncId(7), ConId(0), RoadId(99), RoadId(1))
    return builder^


def test_junction_ordering_reserves_quadratic_work_before_lanes_at() raises:
    var builder = _many_lane_junction(256)
    var index = Dict[Int, Int]()
    index[1] = 0
    builder._build_work = _MapBuildWork(MapBuildBudget(1, max_steps=1000))
    with assert_raises(contains="step budget"):
        _ = builder._junction_lanes(index, JuncId(7), RoadId(99), LaneId(99))
    # Only linear admission occurred; the32640 ordering comparisons were
    # refused as a unit before constructing Road.lanes_at's ordered result.
    assert_equal(builder._build_work.steps, 516)
    assert_true(builder._build_work.exhausted)


def test_predecessor_and_successor_ordering_reserve_separately() raises:
    var builder = _many_lane_junction(8)
    var index = Dict[Int, Int]()
    index[1] = 0
    builder._build_work = _MapBuildWork(MapBuildBudget(1, max_steps=57))
    with assert_raises(contains="step budget"):
        _ = builder._junction_lanes(index, JuncId(7), RoadId(99), LaneId(99))
    # The first branch consumed56 units. The second's two section scans
    # cannot start with one unit left; its ordering work is not reused/reset.
    assert_equal(builder._build_work.steps, 56)


def test_many_short_sections_refuse_before_quadratic_start_enumeration() raises:
    var roads = List[Road]()
    roads.append(_many_sections(1024))
    # Original linear accounting reached segment admission only after about
    # half a million unmetered upper_bound comparisons. The step Error now
    # occurs while reserving the second lane start; no segment was emitted.
    with assert_raises(contains="step budget"):
        _ = Map(
            roads^,
            List[Junction](),
            List[Signal](),
            List[Controller](),
            MapBuildBudget(0, max_steps=5000),
        )


def test_budgeted_locate_refuses_before_section_id_scan() raises:
    var roads = List[Road]()
    roads.append(_many_sections(64))
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    var work = _MapBuildWork(MapBuildBudget(1, max_steps=1))
    with assert_raises(contains="step budget"):
        _ = map._locate_with_work(
            Waypoint(RoadId(1), SectionId(63), LaneId(-1), 63.5), work
        )
    assert_equal(work.steps, 1)


def test_equal_start_sections_keep_first_strict_upper_bound() raises:
    var roads = List[Road]()
    roads.append(_many_sections(3, duplicate_start=True))
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    assert_equal(map.roads[0].section_length(0), 2.0)
    assert_equal(map.roads[0].section_length(1), 2.0)
    assert_equal(map.segment_count(), 3)
    assert_equal(map.segment(0)[2].s, map.segment(1)[2].s)
    assert_equal(map.segment(0)[3].s, map.segment(1)[3].s)
    assert_equal(map.segment(0)[2].section_id, SectionId(0))
    assert_equal(map.segment(1)[2].section_id, SectionId(1))


def test_construction_step_preserves_public_same_section_arithmetic() raises:
    var roads = List[Road]()
    roads.append(_road())
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    var waypoint = map.segment(0)[2]
    for distance in [Float64(1e-12), Float64(0.125), Float64(1.25)]:
        var reference = map.next(waypoint, distance)[0]
        var built = map._build_next(waypoint, distance)
        assert_equal(
            bitcast[DType.uint64](reference.s), bitcast[DType.uint64](built.s)
        )
        assert_equal(reference.lane_id, built.lane_id)


def test_query_step_policy_preserves_five_positional_arguments() raises:
    var policy = MapQueryBudget(1, 2, 3, 4, 5)
    assert_equal(policy.max_candidates, 1)
    assert_equal(policy.max_nodes, 2)
    assert_equal(policy.max_terms, 3)
    assert_equal(policy.max_index_pops, 4)
    assert_equal(policy.max_queue_entries, 5)
    assert_equal(policy.max_steps, 4194304)
    with assert_raises(contains="nonnegative"):
        _ = MapQueryBudget(1, max_steps=-1)
    var roads = List[Road]()
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    policy.max_steps = -1
    with assert_raises(contains="nonnegative"):
        _ = map.certified_closest_waypoint_on_road(
            Vector3(0, 0, 0), budget=policy
        )


def test_query_step_boundary_charges_lookup_profiles_and_bookkeeping() raises:
    var roads = List[Road]()
    roads.append(_road())
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    var work = _MapQueryWork(MapQueryBudget())
    var reference = (
        map._closest_lane_certificate_with_work(
            Vector3(2, 0, 0), LANE_DRIVING, work
        )
        .value()
        .copy()
    )
    assert_true(work.steps > work.nodes + work.index_pops)
    var policy = MapQueryBudget(1, max_steps=work.steps)
    var exact = map.certified_closest_waypoint_on_road(
        Vector3(2, 0, 0), budget=policy
    ).value()
    assert_equal(
        bitcast[DType.uint64](exact.s), bitcast[DType.uint64](reference[0].s)
    )
    policy.max_steps -= 1
    with assert_raises(contains="step budget"):
        _ = map.certified_closest_waypoint_on_road(
            Vector3(2, 0, 0), budget=policy
        )
    policy.max_steps = 0
    with assert_raises(contains="step budget"):
        _ = map.certified_closest_waypoint_on_road(
            Vector3(2, 0, 0), budget=policy
        )


def test_query_step_reservations_refuse_overflow_before_increment() raises:
    comptime top = 9223372036854775807
    var work = _MapQueryWork(MapQueryBudget(top, top, top, top, top, top))
    with assert_raises(contains="step budget"):
        work._step_product(top, 2)
    assert_equal(work.steps, 0)
    work = _MapQueryWork(MapQueryBudget(1, max_steps=20))
    work._step(10)
    work.policy.max_steps = 11
    with assert_raises(contains="step budget"):
        work._step(2)
    assert_equal(work.steps, 10)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
