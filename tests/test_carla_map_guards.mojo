# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Refusals and edge cases of map construction, lookup and work ledgers."""

from extensions.carla.geometry import (
    ARC,
    LINE,
    RoadGeometry,
    RoadGeometryKind,
    _Sample,
    with_arc,
)
from extensions.carla.map import (
    Controller,
    Junction,
    Signal,
    Map,
    Waypoint,
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
from extensions.carla.map_validation import (
    _count_information,
    _preflight_road_records,
    _reserve_lane_boundaries,
    _reserve_road_scan,
    _reserve_straightness,
)
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    InformationSet,
    JuncId,
    LANE_DRIVING,
    LANE_SIDEWALK,
    LaneId,
    LaneType,
    NO_JUNCTION,
    RoadId,
    RoadInfoGeometry,
    RoadInfoSpeed,
    SectionId,
)
from extensions.carla.speed_limits import read_speed_number
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime TOWN = "assets/carla/town.xodr"


def _w(road: Int, lane: Int, s: Float64) -> Waypoint:
    return Waypoint(RoadId(road), SectionId(0), LaneId(lane), s)


def _bare_road() raises -> Road:
    var road = Road(
        RoadId(1), "bare", 10.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = road.add_section(SectionId(0), 0.0)
    return road^


# --- speeds -------------------------------------------------------------------


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


def test_speed_limit_refuses_bad_stations_and_keyword_lane_speeds() raises:
    var map = load_opendrive_file(TOWN)
    for s in [nan[DType.float64](), -1.0, 1.0e9]:
        with assert_raises(contains="Speed-limit station"):
            _ = map.speed_limit_at(_w(1, -1, s))
    var at = map._locate(_w(1, -1, 5.0))
    ref lane = map.roads[at[0]].sections[at[1]].lanes[at[2]]
    lane.info.speeds.clear()
    lane.info.speeds.append(
        RoadInfoSpeed.from_opendrive(0, "no limit", "Town", "", True)
    )
    with assert_raises(contains="numeric"):
        _ = map.speed_limit_at(_w(1, -1, 5.0))


# --- roads and validation -----------------------------------------------------


def test_offset_point_needs_a_geometry_record() raises:
    var road = _bare_road()
    with assert_raises(contains="no geometry"):
        _ = road._offset_lane_point(1.0, 0.0)


def _record(which: Int) raises -> RoadInfoGeometry:
    var geometry = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 10.0)
    var s = 0.0
    var bad = nan[DType.float64]()
    if which == 0:
        s = bad
    elif which == 1:
        geometry.length = bad
    elif which == 2:
        geometry.length = 0.0
    elif which == 3:
        geometry.kind = RoadGeometryKind(99)
    elif which == 4:
        geometry.x = bad
    elif which == 5:
        geometry.y = bad
    elif which == 6:
        geometry.heading = bad
    elif which == 7:
        geometry.curvature_start = bad
    elif which == 8:
        geometry.curvature_end = bad
    return RoadInfoGeometry(s, geometry^)


def _sampled(which: Int) raises -> RoadInfoGeometry:
    var geometry = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 10.0)
    var bad = nan[DType.float64]()
    var sample = _Sample(0, 0, 1, 1, 0)
    if which == 0:
        sample.s = bad
    elif which == 1:
        sample.s = -1
    elif which == 3:
        sample.u = bad
    elif which == 4:
        sample.v = bad
    elif which == 5:
        sample.tu = bad
    elif which == 6:
        sample.tv = bad
    geometry.samples.append(_Sample(0, 0, 0.5, 1, 0))
    if which == 2:
        sample.s = 0.5
    geometry.samples.append(sample)
    return RoadInfoGeometry(0.0, geometry^)


def test_information_counting_refuses_each_invalid_geometry_field() raises:
    for which in range(9):
        var info = InformationSet()
        info.geometries.append(_record(which))
        var work = _MapBuildWork(MapBuildBudget())
        with assert_raises(contains="invalid finite domain"):
            _count_information(info, work)
    for which in range(7):
        var info = InformationSet()
        info.geometries.append(_sampled(which))
        var work = _MapBuildWork(MapBuildBudget())
        with assert_raises(contains="invalid sample domain"):
            _count_information(info, work)


def test_road_preflight_and_empty_reservations() raises:
    var road = _bare_road()
    road.length = -1.0
    var work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="invalid finite domain"):
        _preflight_road_records(road, work)
    # A section with no lanes and a road with no sections reserve nothing.
    var empty = _bare_road()
    work = _MapBuildWork(MapBuildBudget())
    _reserve_lane_boundaries(empty, 0, work)
    _reserve_straightness(empty, 0, work)
    var none = Road(
        RoadId(2), "none", 10.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _reserve_road_scan(none, work)
    assert_equal(work.records, 0)


# --- map lookups --------------------------------------------------------------


def test_lookups_refuse_invalid_missing_roads_and_lanes() raises:
    var map = load_opendrive_file(TOWN)
    var work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="Road id is not valid"):
        _ = _map_locate_with_work(
            map.roads, map._road_index, _w(-1, -1, 1), work
        )
    with assert_raises(contains="no road"):
        _ = _map_locate_with_work(
            map.roads, map._road_index, _w(999, -1, 1), work
        )
    with assert_raises(contains="no lane"):
        _ = _map_locate_with_work(map.roads, map._road_index, _w(1, 9, 1), work)
    var query = _MapQueryWork(MapQueryBudget())
    with assert_raises(contains="no lane"):
        _ = map._query_locate(_w(1, 9, 1), query)
    with assert_raises(contains="not representable"):
        _ = _query_node_step_cost(-1)


def test_metadata_preflight_counts_junction_conflicts() raises:
    var junction = Junction(JuncId(1), "j")
    junction.conflicts.append([RoadId(2), RoadId(3)])
    var junctions = List[Junction]()
    junctions.append(junction^)
    var work = _MapBuildWork(MapBuildBudget())
    _preflight_map_metadata(junctions, List[Signal](), List[Controller](), work)
    assert_true(work.records >= 2)


def test_selected_poses_and_build_steps_need_geometry() raises:
    var map = load_opendrive_file(TOWN)
    var at = map.road_index(RoadId(1))
    map.roads[at].info.geometries.clear()
    var query = _MapQueryWork(MapQueryBudget())
    with assert_raises(contains="unresolved quadrature"):
        map._validate_query_pose(_w(1, -1, 5.0), query)
    with assert_raises(contains="pose quadrature"):
        _ = map._build_transform(_w(1, -1, 5.0))
    with assert_raises(contains="point quadrature"):
        map._reserve_build_point(at, 0, 5.0)
    var work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="quadrature"):
        _ = _signal_lane_pose(map, _w(1, -1, 5.0), work)
    with assert_raises(contains="Lane 0"):
        _ = _signal_side(map, _w(1, 0, 5.0), True, work)


def test_build_steps_refuse_bad_distances_and_leaving_the_road() raises:
    var map = load_opendrive_file(TOWN)
    var start = _w(1, -1, 5.0)
    with assert_raises(contains="positive distance"):
        _ = map._build_next(start, 0.0)
    assert_equal(map._build_next(start, 1.0e-16).s, 5.0)
    with assert_raises(contains="cannot remain"):
        _ = map._build_next(start, 1.0e9)
    with assert_raises(contains="left the road"):
        _ = map._build_next(_w(1, -1, -1.0), 0.5)


def test_junction_waypoints_edge_cases() raises:
    var map = load_opendrive_file(TOWN)
    var work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="Lane type"):
        _ = map._junction_waypoints_with_work(JuncId(100), LaneType(0), work)
    _ = map._junction_waypoints_with_work(JuncId(100), LANE_SIDEWALK, work)
    var at = 0
    for i in range(len(map.junctions)):
        if map.junctions[i].id == JuncId(100):
            at = i
    map.junctions[at].connections.clear()
    assert_equal(len(map.junction_waypoints(JuncId(100), LANE_DRIVING)), 0)


def test_a_sharp_short_arc_splits_on_its_turn_bound() raises:
    # A 1 cm radius over 8 mm turns 0.8 rad. Its quarter-point chord error
    # stays below 1 mm, so only the turn bound requires the split.
    var builder = MapBuilder()
    var r = builder.add_road(
        RoadId(1), "sharp", 0.008, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    var sec = builder.add_road_section(r, SectionId(0), 0.0)
    for id in [-1, 0]:
        _ = builder.add_road_section_lane(
            r, sec, LaneId(id), LANE_DRIVING, False, LaneId(0), LaneId(0)
        )
    builder.create_lane_width(
        builder.lane(RoadId(1), LaneId(-1), 0.0), 0.0, 0.00002, 0, 0, 0
    )
    builder.create_lane_width(
        builder.lane(RoadId(1), LaneId(0), 0.0), 0.0, 0.0, 0, 0, 0
    )
    builder.create_section_offset(r, 0.0, 0, 0, 0, 0)
    builder.add_road_elevation_profile(r, 0.0, 0, 0, 0, 0)
    builder.add_road_geometry_line(r, 0.0, 0.0, 0.0, 0.0, 0.008)
    var geometry = builder.roads[r].info.geometries[0].geometry.copy()
    builder.roads[r].info.geometries[0].geometry = with_arc(geometry^, 100.0)
    var map = builder.build()
    assert_true(map.segment_count() >= 2)


# --- work ledgers -------------------------------------------------------------


def test_budget_policies_refuse_each_negative_limit() raises:
    for field in range(4):
        var budget = MapBuildBudget()
        if field == 0:
            budget.max_segments = -1
        elif field == 1:
            budget.max_steps = -1
        elif field == 2:
            budget.max_terms = -1
        else:
            budget.max_records = -1
        with assert_raises(contains="nonnegative"):
            budget.validate()
    for field in range(6):
        var budget = MapQueryBudget()
        if field == 0:
            budget.max_candidates = -1
        elif field == 1:
            budget.max_nodes = -1
        elif field == 2:
            budget.max_terms = -1
        elif field == 3:
            budget.max_index_pops = -1
        elif field == 4:
            budget.max_queue_entries = -1
        else:
            budget.max_steps = -1
        with assert_raises(contains="nonnegative"):
            budget.validate()


def test_build_ledger_refuses_each_invalid_counter() raises:
    for field in range(8):
        var work = _MapBuildWork(MapBuildBudget(10, 10, 10, 10))
        if field == 0:
            work.segments = -1
        elif field == 1:
            work.segments = 11
        elif field == 2:
            work.steps = -1
        elif field == 3:
            work.steps = 11
        elif field == 4:
            work.terms = -1
        elif field == 5:
            work.terms = 11
        elif field == 6:
            work.records = -1
        else:
            work.records = 11
        with assert_raises(contains="invalid consumed work"):
            work.validate()
    var work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="step budget"):
        work.step(-1)
    work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="record budget"):
        work.record(-1)
    work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="term budget"):
        work.term(-1)
    work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="nonnegative work factors"):
        work.step_product(-1, 1)
    work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="nonnegative work factors"):
        work.step_product(1, -1)


def test_query_ledger_refuses_each_invalid_counter() raises:
    var policy = MapQueryBudget(10, 10, 10, 10, 10, 10)
    for field in range(14):
        var work = _MapQueryWork(policy)
        if field == 0:
            work.max_total_steps = -1
        elif field == 1:
            work.steps = -1
        elif field == 2:
            work.max_total_steps = 5
            work.steps = 6
        elif field == 3:
            work.max_total_steps = 20
            work.steps = 11
        elif field == 4:
            work.candidates = -1
        elif field == 5:
            work.candidates = 11
        elif field == 6:
            work.nodes = -1
        elif field == 7:
            work.nodes = 11
        elif field == 8:
            work.terms = -1
        elif field == 9:
            work.terms = 11
        elif field == 10:
            work.index_pops = -1
        elif field == 11:
            work.index_pops = 11
        elif field == 12:
            work.peak_queue_entries = -1
        else:
            work.peak_queue_entries = 11
        with assert_raises(contains="invalid consumed work"):
            work.validate()


def test_query_ledger_refuses_negative_and_invalid_requests() raises:
    var policy = MapQueryBudget()
    var work = _MapQueryWork(policy)
    with assert_raises(contains="step budget"):
        work._step(-1)
    for factors in [(-1, 1), (1, -1)]:
        work = _MapQueryWork(policy)
        with assert_raises(contains="step budget"):
            work._step_product(factors[0], factors[1])
    work = _MapQueryWork(policy)
    work._step_product(1, 0)
    assert_equal(work.steps, 0)
    with assert_raises(contains="queue budget"):
        work.queue_push(-1)
    work = _MapQueryWork(policy)
    with assert_raises(contains="node work"):
        _ = work.node_cap(20000)
    with assert_raises(contains="node work"):
        _ = work.node_cap(0, 0)
    with assert_raises(contains="term work"):
        _ = work.term_cap(-1)
    with assert_raises(contains="node budget"):
        work.charge(-1, 0)
    work = _MapQueryWork(policy)
    with assert_raises(contains="term budget"):
        work.charge(0, -1)
    work = _MapQueryWork(policy)
    with assert_raises(contains="step cost"):
        work.charge(0, 0, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
