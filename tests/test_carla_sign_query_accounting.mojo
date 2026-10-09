# Budgeted CARLA sign queries preserve default results and admit metadata first.
from extensions.carla.map import (
    Controller,
    EPSILON,
    Junction,
    Map,
    Signal,
    Waypoint,
    _query_node_step_cost,
    _try_winner_seed,
    _winner_seed_room,
)
from extensions.carla.curve_bounds import _reference_work
from extensions.carla.math import distance_segment_to_point
from extensions.carla.map_builder import _check_signals_on_roads_with_work
from extensions.carla.map_search import (
    MapBuildBudget,
    MapQueryBudget,
    _MapBuildWork,
    _MapQueryWork,
)
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
    info_index,
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
from tests.test_carla_winner_seed_recovery import (
    _assert_optional_seed_debits,
    _attempt,
    _produced_seed,
    _same_certificate_except_work,
    _seed_road,
)


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


def test_optional_seed_missing_geometry_keeps_real_certificates() raises:
    for missing_owner in range(3):
        var road = _seed_road()
        var target_road = _seed_road(2)
        var work = _MapQueryWork(MapQueryBudget())
        var certificate = _produced_seed(road, 0.25, 0.3, work)
        var target = _produced_seed(target_road, 0.25, 0.3, work)
        assert_false(certificate.exact_witness)
        assert_false(target.exact_witness)
        assert_equal(certificate.s, 0.25)
        assert_equal(certificate.point, target.point)
        assert_equal(len(certificate.cells), 1)
        assert_equal(len(target.cells), 1)
        var before = certificate.copy()
        var target_before = target.copy()
        var entry_steps = work.steps
        # Deliberately make one road's metadata incomplete only after the
        # real producer returns. This tests defensive eligibility, not a
        # reachable state of an immutable, normally constructed Map.
        if missing_owner == 0:
            road.info.geometries.clear()
        elif missing_owner == 1:
            target_road.info.geometries.clear()
        assert_equal(
            info_index(road.info.geometries, 0.25),
            -1 if missing_owner == 0 else 0,
        )
        assert_equal(
            info_index(target_road.info.geometries, 0.25),
            -1 if missing_owner == 1 else 0,
        )
        assert_false(
            _attempt(road, target_road, 0.25, 0.3, certificate, target, 0, work)
        )
        # The intact control visits the all-false eligibility decision in
        # this same test and performs the established 255 proposal path.
        var nodes = 87 if missing_owner == 2 else 0
        var terms = 2570 if missing_owner == 2 else 0
        _assert_optional_seed_debits(
            before,
            certificate,
            target_before,
            target,
            entry_steps,
            _query_node_step_cost(1, True, True),
            nodes,
            terms,
            work,
        )


def test_sign_query_rejects_negative_selected_index_with_retained_work() raises:
    var map = _one_lane_many_equal_sections(64)
    var query = Vector3(2, 0, 0)
    var expected = map.closest_waypoint_on_road(query)
    assert_true(Bool(expected))
    assert_equal(len(map._carla_segments), 1)
    assert_equal(len(map._carla_tree._tree.start_values), 1)
    assert_equal(map._carla_tree._tree.start_values[0], 0)
    # Preserve the actual constructed geometry, tree, filter and segments.
    # Only the selected scalar metadata is deliberately malformed.
    map._carla_tree._tree.start_values[0] = -1
    var rejected = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="invalid segment"):
        _ = map._closest_lane_with_build_work(query, LANE_DRIVING, rejected)
    assert_equal(rejected.steps, 5)
    assert_equal(rejected.segments, 0)
    assert_equal(rejected.records, 0)
    assert_equal(rejected.terms, 0)
    assert_false(rejected.exhausted)
    # Restore the scalar and exercise the all-false index decision in the
    # same test. Refusal must not damage the tree or query behavior.
    map._carla_tree._tree.start_values[0] = 0
    var accepted = _MapBuildWork(MapBuildBudget())
    _same_waypoint(
        map._closest_lane_with_build_work(query, LANE_DRIVING, accepted),
        expected,
    )
    assert_equal(accepted.steps, 136)
    assert_equal(accepted.terms, 0)
    assert_false(accepted.exhausted)


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


def test_sign_query_refuses_each_mismatched_owner_label() raises:
    for road_mismatch in [True, False]:
        var map = _one_lane_many_equal_sections(3)
        if road_mismatch:
            map._carla_segments[0].second.road_id = RoadId(2)
        else:
            map._carla_segments[0].second.lane_id = LaneId(-2)
        var work = _MapBuildWork(MapBuildBudget())
        with assert_raises(contains="one finite lane section"):
            _ = map._closest_lane_with_build_work(
                Vector3(2, 0, 0), LANE_DRIVING, work
            )
        assert_equal(work.steps, 5)
        assert_false(work.exhausted)


def test_sign_graph_refuses_a_nonfinite_section_origin() raises:
    var map = _graph_map(1)
    map.roads[0].sections[0].s = bitcast[DType.float64](
        UInt64(0x7FF8000000000000)
    )
    var start = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 1.0)
    var work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="invalid length"):
        _ = map._next_with_build_work(start, 1.0, work)
    assert_true(work.steps >= 2)
    assert_false(work.exhausted)


def test_sign_query_keeps_a_positive_sub_epsilon_projection() raises:
    var map = _one_lane_many_equal_sections(1)
    var start = map._carla_segments[0].start
    var query = Vector3(start.x + Float32(1e-16), start.y, start.z)
    var delta = distance_segment_to_point(
        query, start, map._carla_segments[0].end
    )[0].value
    assert_true(delta > 0.0)
    assert_true(Float64(delta) <= EPSILON)
    var expected = map.closest_waypoint_on_road(query)
    var work = _MapBuildWork(MapBuildBudget())
    var actual = map._closest_lane_with_build_work(query, LANE_DRIVING, work)
    _same_waypoint(actual, expected)
    assert_equal(actual.value().s, map._carla_segments[0].first.s)
    assert_false(work.exhausted)


def test_sign_query_refuses_nan_projection_from_finite_long_segment() raises:
    # The ordinary straight-road producer keeps one finite stored segment.
    # Its Float32 squared length overflows, while projecting its own start
    # gives t == 0 and therefore the legacy projection computes 0 * inf.
    var road = _road()
    road.length = 1e20
    road.info.geometries[0].geometry.length = 1e20
    var roads = List[Road]()
    roads.append(road^)
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    assert_equal(len(map._carla_segments), 1)
    var query = map._carla_segments[0].start
    var delta = distance_segment_to_point(
        query, query, map._carla_segments[0].end
    )[0].value
    assert_true(delta != delta)
    var work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="A step needs a positive distance"):
        _ = map._closest_lane_with_build_work(query, LANE_DRIVING, work)
    assert_true(work.steps > 5)
    assert_false(work.exhausted)


def test_optional_seed_room_refuses_direct_invalid_scalar_arguments() raises:
    # These are defensive helper-boundary calls, not states reached by the
    # maintained caller. Both certificates come from the real producer;
    # no certificate field or retained frontier is changed for this test.
    var road = _seed_road()
    var target_road = _seed_road(2)
    var work = _MapQueryWork(MapQueryBudget())
    var certificate = _produced_seed(road, 0.25, 0.3, work)
    var target = _produced_seed(target_road, 0.25, 0.3, work)
    var before = certificate.copy()
    var target_before = target.copy()
    var work_before = work
    var winner_cost = _query_node_step_cost(
        len(road.sections[0].lanes), True, True
    )
    var target_cost = _query_node_step_cost(
        len(target_road.sections[0].lanes), True, True
    )
    var winner_reference = _reference_work(road, 0.25, 0.3)
    var target_reference = _reference_work(target_road, 0.25, 0.3)
    assert_false(certificate.exact_witness)
    assert_false(target.exact_witness)
    assert_equal(len(certificate.cells), 1)
    assert_equal(len(target.cells), 1)
    assert_true(winner_reference > 0)
    assert_true(target_reference > 0)
    for invalid in range(5):
        # Each accepting call is the same-test all-false guard control.
        # For the upper proof limit, use its valid endpoint of five.
        var proof_nodes = 5 if invalid == 1 else 0
        assert_true(
            _winner_seed_room(
                work,
                certificate,
                target.nodes,
                target.terms,
                len(target.cells),
                winner_cost,
                target_cost,
                winner_reference,
                target_reference,
                proof_nodes,
                0,
            )
        )
        var target_cells = len(target.cells)
        var followup_steps = 0
        if invalid == 0:
            proof_nodes = -1
        elif invalid == 1:
            proof_nodes = 6
        elif invalid == 2:
            followup_steps = -1
        elif invalid == 3:
            target_cells = -1
        else:
            target_cells = 16373
        assert_false(
            _winner_seed_room(
                work,
                certificate,
                target.nodes,
                target.terms,
                target_cells,
                winner_cost,
                target_cost,
                winner_reference,
                target_reference,
                proof_nodes,
                followup_steps,
            )
        )
        _same_certificate_except_work(before, certificate, 0, 0)
        _same_certificate_except_work(target_before, target, 0, 0)
        assert_equal(work.candidates, work_before.candidates)
        assert_equal(work.nodes, work_before.nodes)
        assert_equal(work.terms, work_before.terms)
        assert_equal(work.index_pops, work_before.index_pops)
        assert_equal(work.peak_queue_entries, work_before.peak_queue_entries)
        assert_equal(work.steps, work_before.steps)
        assert_equal(work.max_total_steps, work_before.max_total_steps)
        assert_equal(work.exhausted, work_before.exhausted)
        assert_equal(
            work.policy.max_candidates, work_before.policy.max_candidates
        )
        assert_equal(work.policy.max_nodes, work_before.policy.max_nodes)
        assert_equal(work.policy.max_terms, work_before.policy.max_terms)
        assert_equal(
            work.policy.max_index_pops, work_before.policy.max_index_pops
        )
        assert_equal(
            work.policy.max_queue_entries, work_before.policy.max_queue_entries
        )
        assert_equal(work.policy.max_steps, work_before.policy.max_steps)


def test_optional_seed_refuses_direct_invalid_interval_arguments() raises:
    # Only helper arguments change: both certificates retain the real
    # producer's finite positive scale, witness, and unresolved frontier.
    # Each invalid call has a same-test all-false entry-guard control.
    var road = _seed_road()
    var target_road = _seed_road(2)
    var price = _query_node_step_cost(1, True, True)
    for invalid in range(17):
        for valid in [True, False]:
            var work = _MapQueryWork(MapQueryBudget())
            var certificate = _produced_seed(road, 0.25, 0.3, work)
            var target = _produced_seed(target_road, 0.25, 0.3, work)
            assert_false(certificate.exact_witness)
            assert_equal(certificate.s, 0.25)
            assert_equal(len(certificate.cells), 1)
            var before = certificate.copy()
            var target_before = target.copy()
            var entry_steps = work.steps
            var low = Float64(0.25)
            var high = Float64(0.3)
            var target_low = Float64(0.25)
            var target_high = Float64(0.3)
            if not valid:
                if invalid < 12:
                    # Quiet NaN and both infinities at each scalar endpoint.
                    var word = UInt64(0x7FF8000000000000)
                    if invalid % 3 == 1:
                        word = UInt64(0x7FF0000000000000)
                    elif invalid % 3 == 2:
                        word = UInt64(0xFFF0000000000000)
                    var endpoint = bitcast[DType.float64](word)
                    if invalid // 3 == 0:
                        low = endpoint
                    elif invalid // 3 == 1:
                        high = endpoint
                    elif invalid // 3 == 2:
                        target_low = endpoint
                    else:
                        target_high = endpoint
                elif invalid == 12:
                    # Equality isolates high <= low with s still contained.
                    high = low
                elif invalid == 13:
                    high = 0.2
                elif invalid == 14:
                    low = 0.26
                elif invalid == 15:
                    low = 0.2
                    high = 0.24
                else:
                    target_high = 0.2
            assert_false(
                _try_winner_seed(
                    road,
                    0,
                    0,
                    low,
                    high,
                    target_road,
                    0,
                    target_low,
                    target_high,
                    Vector3(0, 1, 0),
                    certificate,
                    target.nodes,
                    target.terms,
                    len(target.cells),
                    0,
                    work,
                )
            )
            _assert_optional_seed_debits(
                before,
                certificate,
                target_before,
                target,
                entry_steps,
                price,
                87 if valid else 0,
                2570 if valid else 0,
                work,
            )


def test_sign_graph_refuses_rounded_same_section_overflow() raises:
    var map = _graph_map(1)
    # Keep an ordinary constructed tree, then supply finite defensive metadata.
    # Rounded section subtraction admits this distance, but addition overflows.
    map.roads[0].length = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    map.roads[0].sections[0].s = bitcast[DType.float64](
        UInt64(0x7C5288F5635A6592)
    )
    var start = Waypoint(
        RoadId(1),
        SectionId(0),
        LaneId(-1),
        bitcast[DType.float64](UInt64(0x7FD14D4C7C789E87)),
    )
    var remaining = map.roads[0].section_length(0) - (
        start.s - map.roads[0].sections[0].s
    )
    assert_equal(bitcast[DType.uint64](remaining), UInt64(0x7FE75959C1C3B0BC))
    for valid in [True, False]:
        var distance = bitcast[DType.float64](
            UInt64(0x7FE75959C1C3B0BC) - UInt64(Int(valid))
        )
        assert_true(distance <= remaining)
        var work = _MapBuildWork(MapBuildBudget())
        if valid:
            var result = map._next_with_build_work(start, distance, work)
            assert_equal(len(result), 1)
            assert_equal(
                bitcast[DType.uint64](result[0].s), UInt64(0x7FEFFFFFFFFFFFFE)
            )
        else:
            with assert_raises(contains="A step left the road"):
                _ = map._next_with_build_work(start, distance, work)
        assert_equal(work.steps, 7 if valid else 6)
        assert_equal(work.terms, 0)
        assert_false(work.exhausted)


def test_optional_seed_refuses_deliberately_invalid_numerical_records() raises:
    # Existing invalid-input contract only: a real producer supplies each
    # baseline, then one field of a COPY is deliberately made invalid.
    # These inputs do not claim producer or public-query reachability.
    # Each pair crosses the entry decision (current1330 conditions 5/8/9).
    # Infinities also affect later comparisons, masked by short-circuiting;
    # this is not a unique-cause claim for those coupled predicates.
    var road = _seed_road()
    var target_road = _seed_road(2)
    var price = _query_node_step_cost(1, True, True)
    for invalid in range(9):
        for valid in [True, False]:
            var work = _MapQueryWork(MapQueryBudget())
            var produced = _produced_seed(road, 0.25, 0.3, work)
            var certificate = produced.copy()
            var target = _produced_seed(target_road, 0.25, 0.3, work)
            assert_false(produced.exact_witness)
            assert_equal(produced.s, 0.25)
            assert_true(produced.scale > 0.0)
            assert_equal(len(produced.cells), 1)
            if not valid:
                var word = UInt64(0x7FF8000000000000)
                if invalid < 6:
                    # Station NaN/+Inf/-Inf; then scale NaN/+Inf/-Inf.
                    if invalid % 3 == 1:
                        word = UInt64(0x7FF0000000000000)
                    elif invalid % 3 == 2:
                        word = UInt64(0xFFF0000000000000)
                elif invalid == 6:
                    word = UInt64(0x0000000000000000)
                elif invalid == 7:
                    word = UInt64(0x8000000000000000)
                else:
                    word = UInt64(0xBFF0000000000000)
                if invalid < 3:
                    certificate.s = bitcast[DType.float64](word)
                else:
                    certificate.scale = bitcast[DType.float64](word)
            var before = certificate.copy()
            var target_before = target.copy()
            var work_before = work
            assert_false(
                _attempt(
                    road, target_road, 0.25, 0.3, certificate, target, 0, work
                )
            )
            var nodes = 87 if valid else 0
            var terms = 2570 if valid else 0
            # The valid control returns False only AFTER downstream work;
            # invalid records must return at the fixed 60-step entry debit.
            assert_equal(work.steps, work_before.steps + 60 + nodes * price)
            assert_equal(work.nodes, work_before.nodes + nodes)
            assert_equal(work.terms, work_before.terms + terms)
            assert_equal(work.candidates, work_before.candidates)
            assert_equal(work.index_pops, work_before.index_pops)
            assert_equal(
                work.peak_queue_entries, work_before.peak_queue_entries
            )
            assert_equal(work.max_total_steps, work_before.max_total_steps)
            assert_equal(work.exhausted, work_before.exhausted)
            assert_equal(
                work.policy.max_candidates, work_before.policy.max_candidates
            )
            assert_equal(work.policy.max_nodes, work_before.policy.max_nodes)
            assert_equal(work.policy.max_terms, work_before.policy.max_terms)
            assert_equal(
                work.policy.max_index_pops, work_before.policy.max_index_pops
            )
            assert_equal(
                work.policy.max_queue_entries,
                work_before.policy.max_queue_entries,
            )
            assert_equal(work.policy.max_steps, work_before.policy.max_steps)
            # Numeric equality cannot preserve NaN payloads or signed zero.
            # Check every retained floating word before using the existing
            # helper on copies with just the invalid fields normalized.
            assert_equal(
                bitcast[DType.uint64](certificate.s),
                bitcast[DType.uint64](before.s),
            )
            assert_equal(
                bitcast[DType.uint64](certificate.scale),
                bitcast[DType.uint64](before.scale),
            )
            assert_equal(
                bitcast[DType.uint64](certificate.lower),
                bitcast[DType.uint64](before.lower),
            )
            assert_equal(
                bitcast[DType.uint64](certificate.upper),
                bitcast[DType.uint64](before.upper),
            )
            for i in range(3):
                assert_equal(
                    bitcast[DType.uint64](certificate.point[i]),
                    bitcast[DType.uint64](before.point[i]),
                )
            assert_equal(len(certificate.cells), len(before.cells))
            for i in range(len(before.cells)):
                assert_equal(
                    bitcast[DType.uint64](certificate.cells[i].low),
                    bitcast[DType.uint64](before.cells[i].low),
                )
                assert_equal(
                    bitcast[DType.uint64](certificate.cells[i].high),
                    bitcast[DType.uint64](before.cells[i].high),
                )
                assert_equal(
                    bitcast[DType.uint64](certificate.cells[i].lower),
                    bitcast[DType.uint64](before.cells[i].lower),
                )
                assert_equal(
                    bitcast[DType.uint64](certificate.cells[i].scale),
                    bitcast[DType.uint64](before.cells[i].scale),
                )
            var normalized_before = before.copy()
            var normalized_after = certificate.copy()
            normalized_before.s = produced.s
            normalized_after.s = produced.s
            normalized_before.scale = produced.scale
            normalized_after.scale = produced.scale
            _same_certificate_except_work(produced, normalized_before, 0, 0)
            _assert_optional_seed_debits(
                normalized_before,
                normalized_after,
                target_before,
                target,
                work_before.steps,
                price,
                nodes,
                terms,
                work,
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
