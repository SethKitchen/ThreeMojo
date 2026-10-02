# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Minimum sample-count routes checked without a search-queue oracle.

Floyd-Warshall computes all-pairs distances by dynamic programming. It
uses neither coordinates, a frontier, nor the production search. Exact
path expectations below come from hand-worked edge costs.
"""

from extensions.carla.agents_route import GlobalRoutePlanner, RouteNodeId
from extensions.carla.map import Map, Waypoint
from extensions.carla.opendrive import load_opendrive, load_opendrive_file
from extensions.carla.road_info import LaneId, RoadId, SectionId
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Length, METER
from tests.test_carla_agents import TWO_LANE


def _graph() raises -> GlobalRoutePlanner:
    return GlobalRoutePlanner(load_opendrive("<OpenDRIVE/>"), Length(2, METER))


def _node(mut graph: GlobalRoutePlanner, x: Float64, y: Float64 = 0) -> Int:
    return graph._node_of(
        String(len(graph._nodes)), SIMD[DType.float64, 4](x, y, 0, 0)
    )


def _link(mut graph: GlobalRoutePlanner, a: Int, b: Int, cost: Int) raises:
    var w = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 0.0)
    var edge = graph._add_edge(a, b, w, w)
    graph._edges[edge].length = cost


def _all_pairs(graph: GlobalRoutePlanner) raises -> List[Int64]:
    # -1 means unreachable. A separate sentinel preserves zero-cost paths.
    var n = graph.node_count()
    var distance = List[Int64]()
    for i in range(n * n):
        distance.append(Int64(0 if i // n == i % n else -1))
    for edge in graph._edges:
        var a = graph._node_index[edge.source.value]
        var b = graph._node_index[edge.target.value]
        var at = a * n + b
        if distance[at] < 0 or Int64(edge.length) < distance[at]:
            distance[at] = Int64(edge.length)
    for via in range(n):
        for a in range(n):
            for b in range(n):
                var left = distance[a * n + via]
                var right = distance[via * n + b]
                if left >= 0 and right >= 0:
                    var candidate = left + right
                    var at = a * n + b
                    if distance[at] < 0 or candidate < distance[at]:
                        distance[at] = candidate
    return distance^


def _cost(graph: GlobalRoutePlanner, route: List[RouteNodeId]) raises -> Int64:
    var cost = Int64(0)
    for i in range(len(route) - 1):
        cost += Int64(graph.edge(route[i], route[i + 1]).length)
    return cost


def _check(
    graph: GlobalRoutePlanner,
    source: Int,
    target: Int,
    distance: List[Int64],
) raises:
    var want = distance[
        graph._node_index[source] * graph.node_count()
        + graph._node_index[target]
    ]
    var route = graph._search(source, target)
    if want < 0:
        assert_equal(len(route), 0)
        return
    assert_true(len(route) > 0)
    assert_equal(route[0].value, source)
    assert_equal(route[len(route) - 1].value, target)
    assert_equal(_cost(graph, route), want)
    var seen = Dict[Int, Bool]()
    for node in route:
        assert_true(node.value not in seen)
        seen[node.value] = True


def test_distance_in_meters_cannot_bound_sample_count() raises:
    var graph = _graph()
    var s = _node(graph, 0)
    var a = _node(graph, 1)
    var b = _node(graph, 100)
    var t = _node(graph, 2)
    _link(graph, s, a, 1)
    _link(graph, a, t, 10)
    _link(graph, s, b, 1)
    _link(graph, b, t, 1)
    # Euclidean A* settled S-A-T at 11 before it considered B. The
    # optimum S-B-T costs 2, independently of the vertex coordinates.
    var route = graph._search(s, t)
    assert_equal(len(route), 3)
    assert_equal(route[1].value, b)
    assert_equal(_cost(graph, route), 2)
    _check(graph, s, t, _all_pairs(graph))


def test_zero_cost_cycles_and_displaced_nodes() raises:
    var graph = _graph()
    for x in [0.0, 1000.0, -1000.0, 1.0]:
        _ = _node(graph, x)
    _link(graph, 0, 0, 0)
    _link(graph, 0, 1, 0)
    _link(graph, 1, 0, 0)
    _link(graph, 1, 2, 0)
    _link(graph, 2, 1, 0)
    _link(graph, 2, 3, 1)
    _link(graph, 0, 3, 2)
    var route = graph._search(0, 3)
    assert_equal(len(route), 4)
    assert_equal(_cost(graph, route), 1)
    var oracle = _all_pairs(graph)
    for a in range(4):
        for b in range(4):
            _check(graph, a, b, oracle)


def test_integer_cost_order_is_exact_above_float64_precision() raises:
    var graph = _graph()
    for i in range(4):
        _ = _node(graph, Float64(i))
    _link(graph, 0, 1, 9007199254740993)
    _link(graph, 0, 2, 9007199254740992)
    _link(graph, 1, 3, 0)
    _link(graph, 2, 3, 0)
    var route = graph._search(0, 3)
    assert_equal(route[1].value, 2)
    assert_equal(_cost(graph, route), 9007199254740992)


def test_graph_validation_rejects_negative_costs() raises:
    var graph = _graph()
    for i in range(4):
        _ = _node(graph, Float64(i))
    _link(graph, 0, 1, 1)
    _link(graph, 2, 3, -1)
    # Private graph edits must revalidate. Production graph construction
    # validates once; each short query must not scan unrelated edges.
    with assert_raises(contains="must be nonnegative"):
        graph._validate_costs()


def test_cost_accumulation_checks_the_signed_64_bit_boundary() raises:
    var graph = _graph()
    for i in range(3):
        _ = _node(graph, Float64(i))
    _link(graph, 0, 1, 9223372036854775807)
    _link(graph, 1, 2, 0)
    assert_equal(_cost(graph, graph._search(0, 2)), 9223372036854775807)
    _link(graph, 1, 2, 1)
    with assert_raises(contains="exceeds the signed 64-bit range"):
        _ = graph._search(0, 2)


def test_irrelevant_overflow_does_not_block_a_representable_route() raises:
    var graph = _graph()
    for i in range(4):
        _ = _node(graph, Float64(i))
    _link(graph, 0, 1, 9223372036854775806)
    _link(graph, 1, 2, 10)
    _link(graph, 0, 3, 9223372036854775807)
    # The overflowing dead end is reached before the valid target pops.
    var route = graph._search(0, 3)
    assert_equal(len(route), 2)
    assert_equal(_cost(graph, route), 9223372036854775807)
    # An overflowing candidate to the target must not replace its valid
    # distance either. It also must not abort the search.
    _link(graph, 1, 3, 10)
    assert_equal(_cost(graph, graph._search(0, 3)), 9223372036854775807)


def test_representable_route_replaces_an_overflow_marker() raises:
    var graph = _graph()
    for i in range(4):
        _ = _node(graph, Float64(i))
    _link(graph, 0, 1, 9223372036854775806)
    _link(graph, 1, 3, 10)
    _link(graph, 0, 2, 9223372036854775807)
    _link(graph, 2, 3, 0)
    # Node 1 first queues the target with an overflow marker. Node 2 then
    # supplies a representable route before that target entry can pop.
    var route = graph._search(0, 3)
    assert_equal(len(route), 3)
    assert_equal(route[1].value, 2)
    assert_equal(_cost(graph, route), 9223372036854775807)


def test_overflow_propagates_without_fabricating_reachability() raises:
    var graph = _graph()
    for i in range(5):
        _ = _node(graph, Float64(i))
    _link(graph, 0, 1, 9223372036854775807)
    _link(graph, 1, 2, 1)
    _link(graph, 2, 1, 0)
    _link(graph, 2, 3, 9223372036854775807)
    # A reachable target beyond the supported cost range is an error.
    # The saturated cost remains saturated across more edges and cycles.
    with assert_raises(contains="exceeds the signed 64-bit range"):
        _ = graph._search(0, 3)
    # An unrelated overflow does not turn an unreachable target into an
    # error or a route. The saturated subgraph must still terminate.
    assert_equal(len(graph._search(0, 4)), 0)


def test_generated_routes_match_independent_all_pairs_distances() raises:
    for seed in range(8):
        var graph = _graph()
        for i in range(12):
            _ = _node(graph, Float64((i * 19 + seed) % 31) * 1000)
        for a in range(12):
            for b in range(12):
                # Some graphs isolate the last node. Others have zero
                # cycles, self edges, ties, and multiple improvements.
                if seed % 3 == 0 and (a == 11 or b == 11):
                    continue
                if (a * 7 + b * 13 + seed) % 11 < 3:
                    _link(graph, a, b, (a * 3 + b + seed) % 5)
        var oracle = _all_pairs(graph)
        for source in range(12):
            for target in range(12):
                _check(graph, source, target, oracle)


def _check_public_map(map: Map, resolution: Float64) raises:
    var graph = GlobalRoutePlanner(map, Length(Float32(resolution), METER))
    var oracle = _all_pairs(graph)
    var origins = List[Vector3]()
    for segment in graph._topology:
        # Use interior samples where possible to avoid an endpoint that
        # belongs to two different road pieces at the same location.
        var w = segment.entry
        if len(segment.path) > 0:
            w = segment.path[0]
        origins.append(map.compute_transform(w).location)
    for origin in origins:
        for destination in origins:
            var start = graph.localize(map, origin).value()
            var end = graph.localize(map, destination).value()
            var want = oracle[
                graph._node_index[start[0].value] * graph.node_count()
                + graph._node_index[end[0].value]
            ]
            var route = graph.path_search(map, origin, destination)
            if want < 0:
                assert_equal(len(route), 0)
                continue
            assert_true(len(route) >= 2)
            assert_equal(route[0], start[0])
            assert_equal(route[len(route) - 2], end[0])
            assert_equal(route[len(route) - 1], end[1])
            # path_search appends the fixed destination piece. Its cost
            # does not affect which preceding route is the minimum.
            want += Int64(graph.edge(end[0], end[1]).length)
            assert_equal(_cost(graph, route), want)


def test_public_town_routes_match_all_pairs_at_two_resolutions() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    _check_public_map(map, 2)
    _check_public_map(map, 5)


def test_public_lane_change_routes_match_all_pairs() raises:
    _check_public_map(load_opendrive(TWO_LANE), 2)


def _road(
    id: Int, length: Float64, junction: Int, link: String, geometry: String
) -> String:
    return String(
        '<road id="',
        id,
        '" length="',
        length,
        '" junction="',
        junction,
        '"><link>',
        link,
        "</link><planView>",
        geometry,
        (
            '</planView><lanes><laneOffset s="0" a="1.75" b="0" c="0"'
            ' d="0"/><laneSection s="0"><center><lane id="0"'
            ' type="none"/></center><right><lane id="-1"'
            ' type="driving"><link><predecessor id="-1"/><successor'
            ' id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0"'
            ' d="0"/></lane></right></laneSection></lanes></road>'
        ),
    )


def _line(
    s: Float64, x: Float64, y: Float64, hdg: Float64, length: Float64
) -> String:
    return String(
        '<geometry s="',
        s,
        '" x="',
        x,
        '" y="',
        y,
        '" hdg="',
        hdg,
        '" length="',
        length,
        '"><line/></geometry>',
    )


def _junction_fixture() -> String:
    var xml = String("<OpenDRIVE>")
    xml += _road(
        1,
        5,
        -1,
        '<successor elementType="junction" elementId="100"/>',
        _line(0, -5, 0, 0, 5),
    )
    xml += _road(
        10,
        5,
        100,
        (
            '<predecessor elementType="road" elementId="1"'
            ' contactPoint="end"/><successor elementType="road" elementId="12"'
            ' contactPoint="start"/>'
        ),
        _line(0, 0, 0, 0, 5),
    )
    xml += _road(
        11,
        10,
        100,
        (
            '<predecessor elementType="road" elementId="1"'
            ' contactPoint="end"/><successor elementType="road" elementId="13"'
            ' contactPoint="start"/>'
        ),
        _line(0, 0, 0, 1.5707963267948966, 10),
    )
    xml += _road(
        12,
        20,
        100,
        (
            '<predecessor elementType="road" elementId="10"'
            ' contactPoint="end"/><successor elementType="road" elementId="20"'
            ' contactPoint="start"/>'
        ),
        _line(0, 5, 0, 0, 7.5)
        + _line(7.5, 12.5, 0, 1.5707963267948966, 10)
        + _line(17.5, 12.5, 10, 3.141592653589793, 2.5),
    )
    xml += _road(
        13,
        10,
        100,
        (
            '<predecessor elementType="road" elementId="11"'
            ' contactPoint="end"/><successor elementType="road" elementId="20"'
            ' contactPoint="start"/>'
        ),
        _line(0, 0, 10, 0, 10),
    )
    xml += _road(
        20,
        10,
        -1,
        '<predecessor elementType="junction" elementId="100"/>',
        _line(0, 10, 10, 0, 10),
    )
    return (
        xml
        + '<junction id="100"><connection id="0" incomingRoad="1"'
        ' connectingRoad="10" contactPoint="start"><laneLink from="-1"'
        ' to="-1"/></connection><connection id="1" incomingRoad="1"'
        ' connectingRoad="11" contactPoint="start"><laneLink from="-1"'
        ' to="-1"/></connection></junction></OpenDRIVE>'
    )


def test_public_opendrive_junction_uses_the_less_costly_branch() raises:
    # Lane offsets put lane centers on the reference lines. In CARLA's
    # coordinates S=(0,0), A=(5,0), B=(0,-10), T=(10,-10). Road 12 is a
    # continuous three-line detour with corners, not an internal graph edit.
    # At resolution 2, the straight 5 m pieces sample s=2: cost 2.
    # The straight 10 m pieces sample s=2,4,6: cost 4.
    # Road 12 samples s=2,4,...,16 before it is within 2 m of T: cost 9.
    # Thus S-A-T costs 2+9=11, while S-B-T costs 4+4=8.
    # Euclidean A* expands A at 2+sqrt(125), ahead of B at 4+10;
    # it then incorrectly settles T at 11. Entry/destination add 2+4.
    var map = load_opendrive(_junction_fixture())
    var graph = GlobalRoutePlanner(map, Length(2, METER))
    var costs = [2, 2, 4, 9, 4, 4]
    var roads = [1, 10, 11, 12, 13, 20]
    for i in range(len(graph._edges)):
        assert_equal(graph._edges[i].entry_waypoint.road_id.value, roads[i])
        assert_equal(graph._edges[i].length, costs[i])
    assert_equal(graph.edge_count(), 6)
    var route = graph.path_search(map, Vector3(-3, 0, 0), Vector3(16, -10, 0))
    var expected_roads = [1, 11, 13, 20]
    assert_equal(len(route), 5)
    for i in range(4):
        assert_equal(
            graph.edge(route[i], route[i + 1]).entry_waypoint.road_id.value,
            expected_roads[i],
        )
    assert_equal(_cost(graph, route), 14)
    _check_public_map(map, 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
