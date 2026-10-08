# Budgeted CARLA sign queries preserve default results and admit metadata first.
from extensions.carla.map import (
    Controller,
    EPSILON,
    Junction,
    Map,
    Signal,
    Waypoint,
)
from extensions.carla.map_builder import _check_signals_on_roads_with_work
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Lane, LaneKey, LaneSection, Road
from extensions.carla.road_info import (
    LANE_BIKING,
    LANE_DRIVING,
    LaneId,
    RoadId,
    RoadInfoLaneWidth,
    SectionId,
    SignalId,
)
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_carla_cross_candidate_certificates import _road


def _one_lane_many_equal_sections(count: Int, lane_id: Int = -1) raises -> Map:
    var road = _road()
    road.sections.clear()
    for i in range(count):
        var section = LaneSection(SectionId(i), 0.0)
        if i == count - 1:
            var lane = Lane(LaneId(lane_id), SectionId(i), 0.0)
            lane.type = LANE_DRIVING
            lane.info.widths.append(
                RoadInfoLaneWidth(0.0, CubicPolynomial.constant(2.0))
            )
            section.lanes.append(lane^)
        road.sections.append(section^)
    var roads = List[Road]()
    roads.append(road^)
    return Map(roads^, List[Junction](), List[Signal](), List[Controller]())


def _same_waypoint(one: Optional[Waypoint], two: Optional[Waypoint]) raises:
    assert_equal(Bool(one), Bool(two))
    if one:
        var a = one.value()
        var b = two.value()
        assert_equal(a.road_id, b.road_id)
        assert_equal(a.section_id, b.section_id)
        assert_equal(a.lane_id, b.lane_id)
        assert_equal(bitcast[DType.uint64](a.s), bitcast[DType.uint64](b.s))


def test_sign_query_reserves_section_visits_before_default_next() raises:
    var map = _one_lane_many_equal_sections(64)
    assert_equal(len(map._carla_segments), 1)
    var work = _MapBuildWork(MapBuildBudget(1, max_steps=2))
    with assert_raises(contains="step budget"):
        _ = map._closest_lane_with_build_work(
            Vector3(2.0, 0.0, 0.0), LANE_DRIVING, work
        )


def test_sign_query_exact_and_one_short_step_caps() raises:
    var map = _one_lane_many_equal_sections(64)
    var q = Vector3(2.0, 0.0, 0.0)
    var expected = map.closest_waypoint_on_road(q)
    # Entry1 + tree4 + locate(1+64+1) + successor scan64 + scalar step1.
    var exact = _MapBuildWork(MapBuildBudget(1, max_steps=136))
    _same_waypoint(
        map._closest_lane_with_build_work(q, LANE_DRIVING, exact), expected
    )
    assert_equal(exact.steps, 136)
    assert_equal(exact.terms, 0)
    var short = _MapBuildWork(MapBuildBudget(1, max_steps=135))
    with assert_raises(contains="step budget"):
        _ = map._closest_lane_with_build_work(q, LANE_DRIVING, short)
    assert_equal(short.steps, 135)
    assert_true(short.exhausted)


def test_sign_query_retains_heap_debits_on_refusal() raises:
    var map = _one_lane_many_equal_sections(64)
    for cap in range(5):
        var work = _MapBuildWork(MapBuildBudget(1, max_steps=cap))
        with assert_raises(contains="step budget"):
            _ = map._closest_lane_with_build_work(
                Vector3(2.0, 0.0, 0.0), LANE_DRIVING, work
            )
        assert_equal(work.steps, cap)
        assert_true(work.exhausted)
        with assert_raises(contains="already exhausted"):
            _ = map._closest_lane_with_build_work(
                Vector3(2.0, 0.0, 0.0), LANE_DRIVING, work
            )


def test_sign_query_refuses_before_each_metadata_scan() raises:
    var map = _one_lane_many_equal_sections(64)
    for cap in [6, 70, 71]:
        var work = _MapBuildWork(MapBuildBudget(1, max_steps=cap))
        with assert_raises(contains="step budget"):
            _ = map._closest_lane_with_build_work(
                Vector3(2.0, 0.0, 0.0), LANE_DRIVING, work
            )
        assert_equal(work.steps, cap)
        assert_true(work.exhausted)


def test_sign_query_preserves_multinode_tree_ties() raises:
    var roads = List[Road]()
    for i in range(20):
        roads.append(_road(i + 1))
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    assert_equal(len(map._carla_segments), 20)
    var work = _MapBuildWork(MapBuildBudget())
    var q = Vector3(2.0, 0.0, 0.0)
    var actual = map._closest_lane_with_build_work(q, LANE_DRIVING, work)
    _same_waypoint(actual, map.closest_waypoint_on_road(q))
    assert_equal(actual.value().road_id, RoadId(1))
    assert_true(work.steps > len(map._carla_segments) + 1)


def test_sign_query_cumulative_and_maximum_caps() raises:
    var map = _one_lane_many_equal_sections(64)
    var work = _MapBuildWork(MapBuildBudget(1, max_steps=272))
    for _ in range(2):
        _ = map._closest_lane_with_build_work(
            Vector3(2.0, 0.0, 0.0), LANE_DRIVING, work
        )
    assert_equal(work.steps, 272)
    with assert_raises(contains="step budget"):
        _ = map._closest_lane_with_build_work(
            Vector3(2.0, 0.0, 0.0), LANE_DRIVING, work
        )
    var large = _MapBuildWork(MapBuildBudget(1, max_steps=9223372036854775807))
    _ = map._closest_lane_with_build_work(
        Vector3(2.0, 0.0, 0.0), LANE_DRIVING, large
    )
    assert_equal(large.steps, 136)


def test_sign_query_matches_default_endpoints_and_both_directions() raises:
    for lane_id in [-1, 1]:
        var map = _one_lane_many_equal_sections(3, lane_id)
        for q in [
            Vector3(-2.0, 0.0, 0.0),
            Vector3(0.0, 0.0, 0.0),
            Vector3(0.25, 2.0, 1.0),
            Vector3(2.0, 0.0, 0.0),
            Vector3(4.0, -3.0, 0.0),
            Vector3(6.0, 0.0, 0.0),
        ]:
            var work = _MapBuildWork(MapBuildBudget())
            var actual = map._closest_lane_with_build_work(
                q, LANE_DRIVING, work
            )
            _same_waypoint(actual, map.closest_waypoint_on_road(q))


def test_sign_query_keeps_rounded_reverse_section_endpoint() raises:
    var road = _road()
    road.length = 82936303789.90771
    road.info.geometries[0].geometry.length = road.length
    road.sections[0].s = 29164287313.443638
    road.sections[0].lanes[0].id = LaneId(1)
    road.sections[0].lanes[0].distance = road.sections[0].s
    var roads = List[Road]()
    roads.append(road^)
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    assert_equal(len(map._carla_segments), 1)
    assert_true(map._carla_segments[0].second.s < map.roads[0].sections[0].s)
    for q in [
        Vector3(56050295551.675674, 0.0, 0.0),
        Vector3(29164287313.443638, 0.0, 0.0),
    ]:
        var work = _MapBuildWork(MapBuildBudget())
        _same_waypoint(
            map._closest_lane_with_build_work(q, LANE_DRIVING, work),
            map.closest_waypoint_on_road(q, LANE_DRIVING),
        )


def test_sign_query_empty_and_filtered_trees() raises:
    var empty = Map(
        List[Road](), List[Junction](), List[Signal](), List[Controller]()
    )
    var empty_work = _MapBuildWork(MapBuildBudget(1, max_steps=1))
    assert_false(
        Bool(
            empty._closest_lane_with_build_work(
                Vector3(0.0, 0.0, 0.0), LANE_DRIVING, empty_work
            )
        )
    )
    assert_equal(empty_work.steps, 1)
    var map = _one_lane_many_equal_sections(64)
    var work = _MapBuildWork(MapBuildBudget(1, max_steps=5))
    assert_false(
        Bool(
            map._closest_lane_with_build_work(
                Vector3(2.0, 0.0, 0.0), LANE_BIKING, work
            )
        )
    )
    assert_equal(work.steps, 5)


def test_sign_query_rejects_invalid_policy_mask_and_segment() raises:
    var map = _one_lane_many_equal_sections(64)
    var work = _MapBuildWork(MapBuildBudget())
    work.policy.max_steps = -1
    with assert_raises(contains="nonnegative"):
        _ = map._closest_lane_with_build_work(
            Vector3(2, 0, 0), LANE_DRIVING, work
        )
    assert_equal(work.steps, 0)
    var invalid = LANE_DRIVING
    invalid.value = -1
    work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="Lane type is not valid"):
        _ = map._closest_lane_with_build_work(Vector3(2, 0, 0), invalid, work)
    assert_equal(work.steps, 1)
    map._carla_segments[0].second.section_id = SectionId(999)
    work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="one finite lane section"):
        _ = map._closest_lane_with_build_work(
            Vector3(2, 0, 0), LANE_DRIVING, work
        )
    assert_equal(work.steps, 5)
    assert_false(work.exhausted)
    map._carla_segments.clear()
    work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="invalid segment"):
        _ = map._closest_lane_with_build_work(
            Vector3(2, 0, 0), LANE_DRIVING, work
        )
    assert_equal(work.steps, 5)
    assert_false(work.exhausted)


def test_static_sign_loop_still_reserves_its_query() raises:
    var map = _one_lane_many_equal_sections(64)
    var signal = Signal(
        RoadId(1),
        SignalId("static"),
        2.0,
        0.0,
        "STATIC",
        "no",
        "+",
        0.0,
        "",
        "",
        "",
        0.0,
        "",
        0.0,
        0.0,
        "",
        0.0,
        0.0,
        0.0,
    )
    signal.transform.location = Vector3(2.0, 0.0, 0.0)
    map.signals.append(signal^)
    var exact = _MapBuildWork(MapBuildBudget(1, max_steps=137))
    _check_signals_on_roads_with_work(map, exact)
    assert_equal(exact.steps, 137)
    var short = _MapBuildWork(MapBuildBudget(1, max_steps=136))
    with assert_raises(contains="step budget"):
        _check_signals_on_roads_with_work(map, short)
    assert_equal(short.steps, 136)
    assert_true(short.exhausted)


def test_sign_query_refuses_malformed_station_and_step_domains() raises:
    for kind in range(7):
        var map = _one_lane_many_equal_sections(3)
        var expected: String
        if kind == 0:
            map._carla_segments[0].first.s = bitcast[DType.float64](
                UInt64(0x7FF8000000000000)
            )
            expected = "one finite lane section"
        elif kind == 1:
            map._carla_segments[0].second.s = bitcast[DType.float64](
                UInt64(0x7FF8000000000000)
            )
            expected = "one finite lane section"
        elif kind == 2:
            map.roads[0].length = bitcast[DType.float64](
                UInt64(0x7FF0000000000000)
            )
            expected = "invalid length"
        elif kind == 3:
            map.roads[0].length = -1.0
            expected = "invalid length"
        elif kind == 4:
            map._carla_segments[0].first.s = 4.0
            map._carla_segments[0].second.s = 0.0
            expected = "inconsistent lane direction"
        elif kind == 5:
            map._carla_segments[0].first.s = 3.0
            map._carla_segments[0].second.s = 10.0
            expected = "has no successor"
        else:
            map._carla_segments[0].first.s = -10.0
            map._carla_segments[0].second.s = -4.0
            expected = "A step left the road"
        var work = _MapBuildWork(MapBuildBudget())
        with assert_raises(contains=expected):
            _ = map._closest_lane_with_build_work(
                Vector3(2.0, 0.0, 0.0), LANE_DRIVING, work
            )
        assert_false(work.exhausted)


def _graph_map(count: Int) raises -> Map:
    var roads = List[Road]()
    for i in range(count):
        var road = _road(i + 1)
        if i == 1 or i == 5:
            road.length = 10.0
            road.info.geometries[0].geometry.length = 10.0
        roads.append(road^)
    return Map(roads^, List[Junction](), List[Signal](), List[Controller]())


def _link(mut map: Map, source: Int, target: Int, lane: Int = -1):
    map.roads[source - 1].sections[0].lanes[0].next_lanes.append(
        LaneKey(RoadId(target), SectionId(0), LaneId(lane))
    )


def _same_waypoints(one: List[Waypoint], two: List[Waypoint]) raises:
    assert_equal(len(one), len(two))
    for i in range(len(one)):
        _same_waypoint(Optional(one[i]), Optional(two[i]))


def test_sign_graph_fallback_preserves_branch_merge_order_and_step_words() raises:
    var map = _graph_map(6)
    _link(map, 1, 2)
    _link(map, 1, 3)
    _link(map, 1, 6)
    _link(map, 3, 4)
    _link(map, 3, 5)
    var start = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 3.0)
    var expected = map.next(start, 6.0)
    assert_equal(len(expected), 4)
    for i in range(4):
        var ids = [4, 5, 2, 6]
        assert_equal(expected[i].road_id, RoadId(ids[i]))
    var work = _MapBuildWork(MapBuildBudget())
    _same_waypoints(map._next_with_build_work(start, 6.0, work), expected)
    assert_equal(work.terms, 0)
    var used = work.steps
    assert_true(used > 4)
    var exact = _MapBuildWork(MapBuildBudget(1, max_steps=used + 3))
    exact.step(3)
    _same_waypoints(map._next_with_build_work(start, 6.0, exact), expected)
    assert_equal(exact.steps, used + 3)
    var short = _MapBuildWork(MapBuildBudget(1, max_steps=used - 1))
    with assert_raises(contains="step budget"):
        _ = map._next_with_build_work(start, 6.0, short)
    assert_true(short.exhausted)
    assert_true(short.steps <= used - 1)
    with assert_raises(contains="already exhausted"):
        _ = map._next_with_build_work(start, 6.0, short)


def test_sign_query_uses_metered_graph_fallback_when_remainder_is_short() raises:
    var map = _graph_map(2)
    _link(map, 1, 2)
    # Synthetic index station metadata forces the graph dispatch.
    map._carla_segments[0].first.s = 3.0
    map._carla_segments[0].second.s = 10.0
    var q = Vector3(2.0, 0.0, 0.0)
    var expected = map.closest_waypoint_on_road(q)
    assert_equal(expected.value().road_id, RoadId(2))
    var work = _MapBuildWork(MapBuildBudget())
    _same_waypoint(
        map._closest_lane_with_build_work(q, LANE_DRIVING, work), expected
    )
    var used = work.steps
    var exact = _MapBuildWork(MapBuildBudget(1, max_steps=used))
    _same_waypoint(
        map._closest_lane_with_build_work(q, LANE_DRIVING, exact), expected
    )
    assert_equal(exact.steps, used)
    var short = _MapBuildWork(MapBuildBudget(1, max_steps=used - 1))
    with assert_raises(contains="step budget"):
        _ = map._closest_lane_with_build_work(q, LANE_DRIVING, short)
    assert_true(short.exhausted)


def test_sign_graph_keeps_lane_zero_and_two_way_cycle_rules() raises:
    var map = _graph_map(2)
    _link(map, 1, 999, 0)
    _link(map, 1, 2)
    _link(map, 2, 1)
    var start = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 3.0)
    var work = _MapBuildWork(MapBuildBudget())
    var result = map._next_with_build_work(start, 2.0, work)
    assert_equal(len(result), 0)
    _same_waypoints(result, map.next(start, 2.0))


def test_sign_graph_finishes_after_lists_and_propagates_late_errors() raises:
    var map = _graph_map(3)
    _link(map, 1, 2)
    _link(map, 1, 3)
    _link(map, 3, 1)
    _link(map, 3, 999)
    var start = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 3.0)
    with assert_raises(contains="no road with that id"):
        _ = map.next(start, 2.0)
    var work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="no road with that id"):
        _ = map._next_with_build_work(start, 2.0, work)
    assert_false(work.exhausted)
    assert_true(work.steps > 0)


def test_sign_graph_keeps_equal_merge_order_and_duplicate_edges() raises:
    var map = _graph_map(6)
    _link(map, 1, 2)
    _link(map, 1, 6)
    _link(map, 1, 3)
    _link(map, 1, 2)
    _link(map, 3, 4)
    _link(map, 3, 5)
    var start = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 3.0)
    var expected = map.next(start, 6.0)
    assert_equal(len(expected), 5)
    var ids = [2, 6, 4, 5, 2]
    for i in range(5):
        assert_equal(expected[i].road_id, RoadId(ids[i]))
    var work = _MapBuildWork(MapBuildBudget())
    _same_waypoints(map._next_with_build_work(start, 6.0, work), expected)


def test_sign_graph_crosses_section_and_reverse_road_boundaries() raises:
    var road = _road()
    var section = LaneSection(SectionId(1), 2.0)
    var lane = Lane(LaneId(-1), SectionId(1), 2.0)
    lane.type = LANE_DRIVING
    lane.info.widths.append(
        RoadInfoLaneWidth(2.0, CubicPolynomial.constant(2.0))
    )
    section.lanes.append(lane^)
    road.sections.append(section^)
    var roads = List[Road]()
    roads.append(road^)
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    map.roads[0].sections[0].lanes[0].next_lanes.append(
        LaneKey(RoadId(1), SectionId(1), LaneId(-1))
    )
    var start = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 1.5)
    var expected = map.next(start, 1.0)
    assert_equal(expected[0].section_id, SectionId(1))
    var work = _MapBuildWork(MapBuildBudget())
    _same_waypoints(map._next_with_build_work(start, 1.0, work), expected)
    var reverse = _graph_map(2)
    for i in range(2):
        reverse.roads[i].sections[0].lanes[0].id = LaneId(1)
    _link(reverse, 1, 2, 1)
    start = Waypoint(RoadId(1), SectionId(0), LaneId(1), 1.0)
    expected = reverse.next(start, 2.0)
    assert_equal(expected[0].road_id, RoadId(2))
    work = _MapBuildWork(MapBuildBudget())
    _same_waypoints(reverse._next_with_build_work(start, 2.0, work), expected)


def test_sign_graph_longer_cycles_exhaust_without_recursion() raises:
    var map = _graph_map(3)
    _link(map, 1, 2)
    _link(map, 2, 3)
    _link(map, 3, 1)
    for i in range(3):
        map.roads[i].length = 0.0
    var start = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 0.0)
    var work = _MapBuildWork(MapBuildBudget(1, max_steps=500))
    with assert_raises(contains="step budget"):
        _ = map._next_with_build_work(start, 1.0, work)
    assert_true(work.exhausted)
    assert_true(work.steps <= 500)
    with assert_raises(contains="already exhausted"):
        _ = map._next_with_build_work(start, 1.0, work)


def test_sign_graph_refuses_nonfinite_or_invalid_metadata_with_retained_work() raises:
    for kind in range(8):
        var map = _graph_map(2)
        _link(map, 1, 2)
        var start = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 3.0)
        var distance = 2.0
        var expected: String
        if kind == 0:
            distance = bitcast[DType.float64](UInt64(0x7FF0000000000000))
            expected = "finite station and distance"
        elif kind == 1:
            start.s = bitcast[DType.float64](UInt64(0x7FF8000000000000))
            expected = "finite station and distance"
        elif kind == 2:
            distance = 0.0
            expected = "positive distance"
        elif kind == 3:
            map.roads[0].length = -1.0
            expected = "invalid length"
        elif kind == 4:
            map.roads[1].length = bitcast[DType.float64](
                UInt64(0x7FF0000000000000)
            )
            expected = "invalid length"
        elif kind == 5:
            map.roads[1].sections[0].lanes[0].id = LaneId(1)
            map.roads[0].sections[0].lanes[0].next_lanes.clear()
            _link(map, 1, 2, 1)
            map.roads[1].length = bitcast[DType.float64](
                UInt64(0x7FF0000000000000)
            )
            expected = "nonfinite station"
        elif kind == 6:
            var largest = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
            map.roads[0].sections[0].s = -largest
            start.s = largest
            expected = "nonfinite remainder"
        else:
            start.s = -3.0
            expected = "A step left the road"
        var work = _MapBuildWork(MapBuildBudget())
        with assert_raises(contains=expected):
            _ = map._next_with_build_work(start, distance, work)
        assert_false(work.exhausted)
        assert_true(work.steps >= 2)


def test_sign_graph_same_road_different_lane_is_not_a_return_cycle() raises:
    var map = _graph_map(2)
    var lane = Lane(LaneId(-2), SectionId(0), 0.0)
    lane.type = LANE_DRIVING
    lane.info.widths.append(
        RoadInfoLaneWidth(0.0, CubicPolynomial.constant(2.0))
    )
    map.roads[0].sections[0].lanes.append(lane^)
    _link(map, 1, 2)
    _link(map, 2, 1, -2)
    var start = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 3.0)
    var expected = map.next(start, 12.0)
    assert_equal(len(expected), 1)
    assert_equal(expected[0].road_id, RoadId(1))
    assert_equal(expected[0].section_id, SectionId(0))
    assert_equal(expected[0].lane_id, LaneId(-2))
    var work = _MapBuildWork(MapBuildBudget())
    _same_waypoints(map._next_with_build_work(start, 12.0, work), expected)
    assert_false(work.exhausted)


def test_sign_graph_same_road_and_lane_later_section_is_not_a_return_cycle() raises:
    var first = _road(1)
    var section = LaneSection(SectionId(1), 2.0)
    var lane = Lane(LaneId(-1), SectionId(1), 2.0)
    lane.type = LANE_DRIVING
    lane.info.widths.append(
        RoadInfoLaneWidth(2.0, CubicPolynomial.constant(2.0))
    )
    section.lanes.append(lane^)
    first.sections.append(section^)
    var second = _road(2)
    second.length = 10.0
    second.info.geometries[0].geometry.length = 10.0
    var roads = List[Road]()
    roads.append(first^)
    roads.append(second^)
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    _link(map, 1, 2)
    map.roads[1].sections[0].lanes[0].next_lanes.append(
        LaneKey(RoadId(1), SectionId(1), LaneId(-1))
    )
    var start = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 1.5)
    var expected = map.next(start, 11.5)
    assert_equal(len(expected), 1)
    assert_equal(expected[0].road_id, RoadId(1))
    assert_equal(expected[0].section_id, SectionId(1))
    assert_equal(expected[0].lane_id, LaneId(-1))
    var work = _MapBuildWork(MapBuildBudget())
    _same_waypoints(map._next_with_build_work(start, 11.5, work), expected)
    assert_false(work.exhausted)


def test_sign_graph_tiny_leaf_has_exact_three_step_admission() raises:
    var map = _graph_map(1)
    var start = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 2.0)
    for distance in [Float64(1e-16), Float64(EPSILON)]:
        var expected = map.next(start, distance)
        var exact = _MapBuildWork(MapBuildBudget(1, max_steps=3))
        _same_waypoints(
            map._next_with_build_work(start, distance, exact), expected
        )
        assert_equal(exact.steps, 3)
        assert_equal(exact.terms, 0)
        assert_false(exact.exhausted)
        var short = _MapBuildWork(MapBuildBudget(1, max_steps=2))
        with assert_raises(contains="step budget"):
            _ = map._next_with_build_work(start, distance, short)
        assert_equal(short.steps, 2)
        assert_true(short.exhausted)
        with assert_raises(contains="already exhausted"):
            _ = map._next_with_build_work(start, distance, short)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
