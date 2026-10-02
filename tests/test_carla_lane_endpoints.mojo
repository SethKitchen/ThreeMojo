# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Engineering endpoint regressions, independent of inherited CARLA bugs."""

from extensions.carla.agents_route import GlobalRoutePlanner
from extensions.carla.map import EPSILON, Map, Waypoint
from extensions.carla.opendrive import load_opendrive
from extensions.carla.road import LaneKey
from extensions.carla.road_info import LaneId, RoadId, SectionId
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def _section(s: Float64, linked: Bool) -> String:
    var text = String('<laneSection s="', s, '">')
    for side in ["left", "right"]:
        var id = 1 if side == "left" else -1
        text += String(
            "<", side, '><lane id="', id, '" type="driving" level="false">'
        )
        if linked:
            text += String(
                '<link><predecessor id="',
                id,
                '"/><successor id="',
                id,
                '"/></link>',
            )
        text += String(
            '<width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></', side, ">"
        )
    return (
        text
        + '<center><lane id="0" type="none"'
        ' level="false"/></center></laneSection>'
    )


def _map(
    length: Float64,
    rht: Bool,
    connected: Bool = False,
    sections: Bool = False,
    linked: Bool = True,
) raises -> Map:
    var text = String("<OpenDRIVE>")
    var count = 3 if connected else 1
    for id in range(1, count + 1):
        text += String(
            '<road id="',
            id,
            '" length="',
            length,
            '" junction="-1" rule="',
            "RHT" if rht else "LHT",
            '">',
        )
        text += "<link>"
        if id > 1:
            text += String(
                '<predecessor elementType="road" elementId="',
                id - 1,
                '" contactPoint="end"/>',
            )
        if id < count:
            text += String(
                '<successor elementType="road" elementId="',
                id + 1,
                '" contactPoint="start"/>',
            )
        text += String(
            '</link><planView><geometry s="0" x="',
            Float64(id - 1) * length,
            '" y="0" hdg="0" length="',
            length,
            '"><line/></geometry></planView>',
        )
        text += (
            '<elevationProfile><elevation s="0" a="0" b="0.1" c="0"'
            ' d="0"/></elevationProfile><lanes><laneOffset s="0" a="0" b="0"'
            ' c="0" d="0"/>'
        )
        text += _section(0, linked)
        if sections:
            text += _section(length / 2, linked)
        text += "</lanes></road>"
    return load_opendrive(text + "</OpenDRIVE>")


def _w(road: Int, section: Int, lane: Int, s: Float64) -> Waypoint:
    return Waypoint(RoadId(road), SectionId(section), LaneId(lane), s)


def test_topology_retains_dead_ends_and_section_identity() raises:
    for rht in [True, False]:
        for length in [100.0, 0.04, 733.3]:
            var map = _map(length, rht)
            var topology = map.generate_topology()
            assert_equal(len(topology), 2)
            for i in range(2):
                var entry = topology[i][0]
                var end = topology[i][1]
                assert_equal(entry.lane_id.value, -1 if i == 0 else 1)
                assert_equal(end.road_id, entry.road_id)
                assert_equal(end.section_id, entry.section_id)
                assert_equal(end.lane_id, entry.lane_id)
                var positive = map.is_positive_direction(entry)
                assert_almost_equal(
                    entry.s, 0.0 if positive else length, atol=1e-12
                )
                assert_almost_equal(
                    end.s, length if positive else 0.0, atol=1e-12
                )
                assert_true(end.s >= 0.0)
                assert_true(end.s <= length)
                _ = map.compute_transform(end)
            # Disconnected sections must retain their own endpoint, even
            # when Float32 would round it into the adjacent section.
            map = _map(length, rht, False, True, False)
            topology = map.generate_topology()
            assert_equal(len(topology), 4)
            for pair in topology:
                assert_equal(pair[1].section_id, pair[0].section_id)
                var low = Float64(pair[0].section_id.value) * length / 2
                assert_true(pair[1].s >= low)
                assert_true(pair[1].s <= low + length / 2)


def test_tiny_positive_sections_keep_endpoints_inside() raises:
    # No inward offset may exceed the representable lane length. At the
    # least subnormal, there is no representable strictly interior point.
    for length in [Float64(1e-16), Float64(5e-324)]:
        for rht in [True, False]:
            var map = _map(length, rht)
            var topology = map.generate_topology()
            assert_equal(len(topology), 2)
            for pair in topology:
                for waypoint in [pair[0], pair[1]]:
                    assert_true(waypoint.s >= 0.0)
                    assert_true(waypoint.s <= length)
                    _ = map.compute_transform(waypoint)
                var forward = map.next_until_lane_end(pair[0], 1.0)
                assert_equal(len(forward), 1)
                assert_equal(forward[0], pair[1])
                var backward = map.previous_until_lane_start(pair[1], 1.0)
                assert_equal(len(backward), 1)
                assert_equal(backward[0], pair[0])
                assert_equal(len(map.next_until_lane_end(pair[1], 1.0)), 0)

    # A residual inside the endpoint inset emits the exact endpoint even
    # when the requested spacing is smaller than that residual.
    for rht in [True, False]:
        var map = _map(40.0 * EPSILON, rht)
        for pair in map.generate_topology():
            var middle = pair[0]
            middle.s = (pair[0].s + pair[1].s) / 2.0
            var forward = map.next_until_lane_end(middle, 2.0 * EPSILON)
            assert_equal(len(forward), 1)
            assert_equal(forward[0], pair[1])
            var backward = map.previous_until_lane_start(middle, 2.0 * EPSILON)
            assert_equal(len(backward), 1)
            assert_equal(backward[0], pair[0])


def test_connected_topology_keeps_lane_order() raises:
    for rht in [True, False]:
        var map = _map(100, rht, True, True)
        var topology = map.generate_topology()
        assert_equal(len(topology), 12)
        for i in range(len(topology)):
            var entry = topology[i][0]
            var end = topology[i][1]
            assert_equal(entry.road_id.value, i // 4 + 1)
            assert_equal(entry.section_id.value, (i // 2) % 2)
            assert_equal(entry.lane_id.value, -1 if i % 2 == 0 else 1)
            var positive = map.is_positive_direction(entry)
            var terminal_road = 3 if positive else 1
            var terminal_section = 1 if positive else 0
            if (
                entry.road_id.value == terminal_road
                and entry.section_id.value == terminal_section
            ):
                assert_equal(end.road_id, entry.road_id)
                assert_equal(end.section_id, entry.section_id)
                assert_almost_equal(
                    end.s, 100.0 if positive else 0.0, atol=1e-12
                )
            else:
                var nexts = map.successors(entry)
                assert_equal(len(nexts), 1)
                assert_equal(end, nexts[0])


def _check_walk(
    map: Map, start: Waypoint, distance: Float64, ahead: Bool, target: Float64
) raises:
    var points = map.next_until_lane_end(
        start, distance
    ) if ahead else map.previous_until_lane_start(start, distance)
    assert_true(len(points) > 0)
    var forward = map.is_positive_direction(start) == ahead
    var previous = start.s
    for point in points:
        assert_equal(point.road_id, start.road_id)
        assert_equal(point.lane_id, start.lane_id)
        assert_true(point.s >= 0.0)
        assert_true(point.s <= map.road(start.road_id).length)
        assert_true(point.s > previous if forward else point.s < previous)
        _ = map.compute_transform(point)
        previous = point.s
    assert_almost_equal(points[len(points) - 1].s, target, atol=1e-12)


def test_traversal_directions_connections_and_intervals() raises:
    for rht in [True, False]:
        for connected in [True, False]:
            for sections in [True, False]:
                var map = _map(100, rht, connected, sections)
                var road = 2 if connected else 1
                for lane in [-1, 1]:
                    for ahead in [True, False]:
                        var start = _w(road, 0, lane, 25.0)
                        var forward = map.is_positive_direction(start) == ahead
                        var target = 100.0 if forward else 0.0
                        for distance in [10.0, 25.0, 100.0, 1000000.0]:
                            _check_walk(map, start, distance, ahead, target)
                        var boundary = _w(
                            road, 1 if sections else 0, lane, 100.0
                        )
                        if not forward:
                            _check_walk(map, boundary, 100.0, ahead, 0.0)
                        boundary.s = target
                        boundary.section_id = SectionId(
                            1 if sections and forward else 0
                        )
                        var empty = map.next_until_lane_end(
                            boundary, 10.0
                        ) if ahead else map.previous_until_lane_start(
                            boundary, 10.0
                        )
                        assert_equal(len(empty), 0)
                        if sections:
                            _check_walk(
                                map,
                                _w(road, 1, lane, 50.0),
                                10.0,
                                ahead,
                                target,
                            )


def test_exact_section_boundary_when_epsilon_rounds_away() raises:
    # At s=366.65, the endpoint offset is below half one Float64 ULP.
    # Either section identity at the exact join must follow the link.
    for rht in [True, False]:
        var map = _map(733.3, rht, False, True)
        for lane in [-1, 1]:
            for ahead in [True, False]:
                for section in [0, 1]:
                    var start = _w(1, section, lane, 366.65)
                    var forward = map.is_positive_direction(start) == ahead
                    for distance in [10.0, 1000000.0]:
                        _check_walk(
                            map,
                            start,
                            distance,
                            ahead,
                            733.3 if forward else 0.0,
                        )


def test_short_roads_and_disconnected_sections() raises:
    for rht in [True, False]:
        var short = _map(0.04, rht)
        var split = _map(100, rht, False, True, False)
        for lane in [-1, 1]:
            for ahead in [True, False]:
                var forward = (
                    short.is_positive_direction(_w(1, 0, lane, 0.01)) == ahead
                )
                _check_walk(
                    short,
                    _w(1, 0, lane, 0.01),
                    10.0,
                    ahead,
                    0.04 if forward else 0.0,
                )
                _check_walk(
                    split,
                    _w(1, 0, lane, 25),
                    1000000.0,
                    ahead,
                    50.0 if forward else 0.0,
                )
                _check_walk(
                    split,
                    _w(1, 1, lane, 75),
                    1000000.0,
                    ahead,
                    100.0 if forward else 50.0,
                )


def test_isolated_graded_road_routes() raises:
    for rht in [True, False]:
        var map = _map(100, rht)
        var planner = GlobalRoutePlanner(map, Length(2, METER))
        for lane in [-1, 1]:
            var positive = map.is_positive_direction(_w(1, 0, lane, 10))
            var start = 10.0 if positive else 80.0
            var target = 80.0 if positive else 10.0
            var y = -1.75 * Float64(lane)
            var route = planner.trace_route(
                map,
                Vector3(Float32(start), Float32(y), Float32(start * 0.1)),
                Vector3(Float32(target), Float32(y), Float32(target * 0.1)),
            )
            assert_true(len(route) > 20)
            assert_almost_equal(route[0].waypoint.s, start, atol=2.01)
            assert_almost_equal(
                route[len(route) - 1].waypoint.s, target, atol=2.01
            )
            var previous = start - 2.01 if positive else start + 2.01
            for point in route:
                assert_equal(point.waypoint.road_id, RoadId(1))
                assert_equal(point.waypoint.lane_id, LaneId(lane))
                assert_true(
                    point.waypoint.s
                    >= previous if positive else point.waypoint.s
                    <= previous
                )
                previous = point.waypoint.s


def test_invalid_spacing_and_nonadvancing_steps() raises:
    var map = _map(100, True)
    for ahead in [True, False]:
        for distance in [
            0.0,
            -0.0,
            -1.0,
            EPSILON,
            Float64("inf"),
            Float64("-inf"),
            Float64("nan"),
        ]:
            for s in [25.0, 100.0 if ahead else 0.0]:
                with assert_raises():
                    if ahead:
                        _ = map.next_until_lane_end(_w(1, 0, -1, s), distance)
                    else:
                        _ = map.previous_until_lane_start(
                            _w(1, 0, -1, s), distance
                        )
        with assert_raises():
            if ahead:
                _ = map.next_until_lane_end(_w(1, 0, -1, 75), 2.0 * EPSILON)
            else:
                _ = map.previous_until_lane_start(
                    _w(1, 0, -1, 75), 2.0 * EPSILON
                )


def test_until_lane_rejects_invalid_s_before_endpoint_discovery() raises:
    for rht in [True, False]:
        var map = _map(100, rht, False, True)
        for lane in [-1, 1]:
            for ahead in [True, False]:
                for section in [0, 1]:
                    for s in [
                        Float64("nan"),
                        Float64("inf"),
                        Float64("-inf"),
                        -1.0,
                        101.0,
                        75.0 if section == 0 else 25.0,
                    ]:
                        with assert_raises(contains="outside its lane section"):
                            if ahead:
                                _ = map.next_until_lane_end(
                                    _w(1, section, lane, s), 10
                                )
                            else:
                                _ = map.previous_until_lane_start(
                                    _w(1, section, lane, s), 10
                                )
                    # A shared endpoint belongs to either adjacent section.
                    var start = _w(1, section, lane, 50)
                    var forward = map.is_positive_direction(start) == ahead
                    _check_walk(
                        map, start, 10, ahead, 100.0 if forward else 0.0
                    )


def test_branch_and_cycle_boundaries() raises:
    var map = _map(100, True, False, True)
    # Two same-road successors end the unique path at this section.
    map.roads[0].sections[0].lanes[0].next_lanes.append(
        LaneKey(RoadId(1), SectionId(1), LaneId(-1))
    )
    _check_walk(map, _w(1, 0, -1, 25), 10, True, 50)
    # A reversed same-road link must not make endpoint discovery loop.
    map = _map(100, True, False, True)
    map.roads[0].sections[1].lanes[0].next_lanes.append(
        LaneKey(RoadId(1), SectionId(0), LaneId(-1))
    )
    _check_walk(map, _w(1, 1, -1, 75), 1000, True, 100)
    # The existing step guard rejects a two-section cycle. The helper
    # propagates that failure instead of indexing an empty step.
    with assert_raises(contains="unique path"):
        _ = map.next_until_lane_end(_w(1, 0, -1, 25), 60)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
