# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Public route boundaries and analytic OpenDRIVE topology transitions."""

from extensions.carla.agents_route import GlobalRoutePlanner, RouteNodeId
from extensions.carla.agents_misc import (
    OPTION_LANE_FOLLOW,
    OPTION_LEFT,
    OPTION_STRAIGHT,
    OPTION_CHANGE_LANE_RIGHT,
)
from extensions.carla.opendrive import load_opendrive
from math.vector3 import Vector3
from tests.test_carla_agents import ODD, TWO_LANE
from tests.test_carla_route_search import _road, _line, _junction_fixture
from std.testing import TestSuite, assert_equal, assert_false, assert_raises
from units.si import Length, METER


def _lane(id: Int, type: String, predecessor: Int, successor: Int) -> String:
    return String(
        '<lane id="',
        id,
        '" type="',
        type,
        '"><link><predecessor id="',
        predecessor,
        '"/><successor id="',
        successor,
        '"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane>',
    )


def _section(s: Float64, type: String, turnaround: Bool = False) -> String:
    var text = String(
        '<laneSection s="', s, '"><center><lane id="0" type="none"/></center>'
    )
    if turnaround:
        text += "<left>" + _lane(1, type, -1, 0) + "</left>"
    text += "<right>" + _lane(-1, type, -1, 1 if turnaround else -1)
    return text + "</right></laneSection>"


def _loose_fixture(boundary: Int) -> String:
    var xml = String("<OpenDRIVE>")
    xml += _road(
        1,
        10,
        -1,
        '<successor elementType="road" elementId="2" contactPoint="start"/>',
        _line(0, 0, 0, 0, 10),
    )
    xml += (
        '<road id="2" length="10" junction="100"><link><predecessor'
        ' elementType="road" elementId="1" contactPoint="end"/>'
    )
    if boundary == 1:
        xml += (
            '<successor elementType="road" elementId="3" contactPoint="start"/>'
        )
    if boundary == 3:
        xml += (
            '<successor elementType="road" elementId="2" contactPoint="end"/>'
        )
    xml += "</link><planView>" + _line(0, 10, 0, 0, 10)
    xml += '</planView><lanes><laneOffset s="0" a="1.75" b="0" c="0" d="0"/>'
    xml += _section(0, "parking", boundary == 3)
    if boundary == 2:
        xml += _section(5, "parking")
    xml += "</lanes></road>"
    if boundary == 1:
        xml += _road(
            3,
            10,
            100,
            (
                '<predecessor elementType="road" elementId="2"'
                ' contactPoint="end"/>'
            ),
            _line(0, 20, 0, 0, 10),
        ).replace('type="driving"', 'type="parking"')
    return xml + "</OpenDRIVE>"


def test_loose_ends_stop_at_road_section_and_lane_boundaries() raises:
    # A driving lane leads into a parking lane. Only the driving lane
    # has topology, so the planner constructs a real loose end for the
    # parking lane. Its sampling must stop at each kind of boundary.
    for boundary in range(4):
        var map = load_opendrive(_loose_fixture(boundary))
        var graph = GlobalRoutePlanner(map, Length(2, METER))
        assert_equal(graph.edge_count(), 2)
        var entry = graph.localize(map, Vector3(2, 0, 0)).value()
        var tails = graph.successors(entry[1])
        assert_equal(len(tails), 1)
        assert_equal(tails[0].value, -1)
        var edge = graph.edge(entry[1], tails[0])
        assert_equal(edge.entry_waypoint.road_id.value, 2)
        assert_equal(edge.exit_waypoint.road_id.value, 2)
        assert_equal(edge.exit_waypoint.section_id.value, 0)
        assert_equal(edge.exit_waypoint.lane_id.value, -1)
        assert_equal(len(edge.path), 2 if boundary == 2 else 4)
        assert_equal(edge.length, len(edge.path) + 1)
        assert_false(Bool(edge.exit_vector))
        var route: List[RouteNodeId] = [entry[0], entry[1], tails[0]]
        # A junction loose end has no exit vector. The public turn helper
        # must use lane follow without trying to compare absent vectors.
        assert_equal(graph.turn_decision(1, route), OPTION_LANE_FOLLOW)


def test_public_edge_checks_the_second_node_id() raises:
    var graph = GlobalRoutePlanner(load_opendrive(TWO_LANE), Length(2, METER))
    with assert_raises(contains="Route node id is not valid"):
        _ = graph.edge(RouteNodeId(0), RouteNodeId(1 << 40))


def test_public_route_to_an_unsampled_lane_is_empty() raises:
    var map = load_opendrive(ODD)
    var graph = GlobalRoutePlanner(map, Length(2, METER))
    # These two connected half-meter lanes have no first 2 m sample.
    assert_false(Bool(graph.localize(map, Vector3(0.2, -48.25, 0))))
    assert_equal(
        len(
            graph.path_search(
                map, Vector3(5.3, 1.75, 0), Vector3(0.2, -48.25, 0)
            )
        ),
        0,
    )


def test_trace_can_finish_across_a_short_section_boundary() raises:
    var xml = String(
        '<OpenDRIVE><road id="1" length="10" junction="-1"><planView>'
    )
    xml += _line(0, 0, 0, 0, 10)
    xml += '</planView><lanes><laneOffset s="0" a="1.75" b="0" c="0" d="0"/>'
    xml += _section(0, "driving") + _section(1, "driving")
    xml += "</lanes></road></OpenDRIVE>"
    var map = load_opendrive(xml)
    var graph = GlobalRoutePlanner(map, Length(2, METER))
    # A distant lateral destination still projects onto the short first
    # section. The first 2 m sample lies in the second section.
    var route = graph.trace_route(map, Vector3(0.2, 0, 0), Vector3(0.8, 100, 0))
    assert_equal(len(route), 3)
    assert_equal(route[0].waypoint.section_id.value, 0)
    assert_equal(route[1].waypoint.section_id.value, 1)
    assert_equal(route[2].waypoint.section_id.value, 1)


def test_trace_can_finish_at_a_successor_lane_on_the_same_road() raises:
    var xml = String(
        '<OpenDRIVE><road id="1" length="10" junction="-1"><link><successor'
        ' elementType="road" elementId="1"'
        ' contactPoint="end"/></link><planView>'
    )
    xml += _line(0, 0, 0, 0, 10)
    xml += "</planView><lanes>" + _section(0, "driving", True)
    xml += "</lanes></road></OpenDRIVE>"
    var map = load_opendrive(xml)
    var graph = GlobalRoutePlanner(map, Length(2, METER))
    var route = graph.trace_route(
        map, Vector3(5.3, 1.75, 0), Vector3(9, 100, 0)
    )
    assert_equal(len(route), 3)
    assert_equal(route[0].waypoint.lane_id.value, -1)
    assert_equal(route[1].waypoint.lane_id.value, -1)
    assert_equal(route[2].waypoint.lane_id.value, 1)


def test_public_turn_queries_handle_lane_changes_and_nonsequential_steps() raises:
    var destination = _road(
        20,
        10,
        -1,
        '<predecessor elementType="junction" elementId="100"/>',
        _line(0, 10, 10, 0, 10),
    )
    var two_lanes = destination.replace(
        "</right>", _lane(-2, "driving", -2, -2) + "</right>"
    ).replace(
        "</lane>",
        '<roadMark sOffset="0" type="broken" laneChange="both"/></lane>',
    )
    var map = load_opendrive(
        _junction_fixture().replace(destination, two_lanes)
    )
    var graph = GlobalRoutePlanner(map, Length(2, METER))
    var start = graph.localize(map, Vector3(-3, 0, 0)).value()
    var branch = graph.localize(map, Vector3(0, -5, 0)).value()
    var a = graph.localize(map, Vector3(16, -10, 0)).value()
    var b = graph.localize(map, Vector3(16, -6.5, 0)).value()
    var route: List[RouteNodeId] = [
        start[0],
        start[1],
        branch[1],
        a[0],
        b[0],
        b[1],
    ]
    # The junction tail ends at a legal lane-change edge. That edge must
    # not be treated as another lane-follow piece of the junction.
    _ = graph.turn_decision(1, route)
    # The public helper permits individual, nonsequential step queries.
    # The previous junction end is the first node of this valid suffix.
    var suffix: List[RouteNodeId] = [a[0], b[0], b[1]]
    assert_equal(graph.turn_decision(1, suffix), OPTION_LANE_FOLLOW)
    _ = graph.turn_decision(1, route)
    assert_equal(graph.turn_decision(3, route), OPTION_CHANGE_LANE_RIGHT)


def test_lane_change_is_not_a_junction_turn_competitor() raises:
    var map = load_opendrive(TWO_LANE)
    var graph = GlobalRoutePlanner(map, Length(2, METER))
    var a = graph.localize(map, Vector3(5, 1.75, 0)).value()
    var b = graph.localize(map, Vector3(60, 5.25, 0)).value()
    var late_change: List[RouteNodeId] = [a[0], a[1], b[0]]
    # This is a valid late-change route, though equal-cost uniform search
    # currently chooses the early change. No private graph state changes.
    assert_equal(graph.turn_decision(1, late_change), OPTION_CHANGE_LANE_RIGHT)
    # Directly check the turn-comparison helper with an actual node whose
    # outgoing edges include a lane change. It is not an alternative turn.
    assert_equal(
        graph._compare(
            a[0].value, a[1].value, Vector3(1, 0, 0), Vector3(1, 0, 0), 35
        ),
        OPTION_STRAIGHT,
    )


def test_lane_change_skips_a_driving_lane_without_a_sampled_piece() raises:
    var middle = (
        _road(
            2,
            1.8,
            -1,
            (
                '<predecessor elementType="road" elementId="1"'
                ' contactPoint="end"/><successor elementType="road"'
                ' elementId="3" contactPoint="start"/>'
            ),
            _line(0, 0.5, 0, 0, 1.8),
        )
        .replace(
            "</right>",
            (
                '<lane id="-2" type="driving"><width sOffset="0" a="3.5" b="0"'
                ' c="0" d="0"/></lane></right>'
            ),
        )
        .replace(
            "</lane>",
            '<roadMark sOffset="0" type="broken" laneChange="both"/></lane>',
        )
    )
    var xml = String("<OpenDRIVE>")
    xml += _road(
        1,
        0.5,
        -1,
        '<successor elementType="road" elementId="2" contactPoint="start"/>',
        _line(0, 0, 0, 0, 0.5),
    )
    xml += middle
    xml += _road(
        3,
        10,
        -1,
        '<predecessor elementType="road" elementId="2" contactPoint="end"/>',
        _line(0, 2.3, 0, 0, 10),
    )
    var map = load_opendrive(xml + "</OpenDRIVE>")
    var graph = GlobalRoutePlanner(map, Length(2, METER))
    # The 2 m sample from road 1 lands on road 2 at s=1.5. Its adjacent
    # driving lane ends at s=1.8 and has no first 2 m sample or graph piece.
    # The broken mark alone must not create a link to that absent piece.
    assert_false(Bool(graph.localize(map, Vector3(2, 3.5, 0))))
    var start = graph.localize(map, Vector3(0.2, 0, 0)).value()
    var neighbors = graph.successors(start[0])
    # Half-meter rounding merges the first two entry locations. Both
    # outgoing edges are lane follows; neither is a spurious lane change.
    assert_equal(len(neighbors), 2)
    for next in neighbors:
        assert_equal(graph.edge(start[0], next).type, OPTION_LANE_FOLLOW)


def test_turn_comparison_ignores_a_loose_end_without_a_chord() raises:
    var extra = _road(
        4,
        10,
        100,
        '<predecessor elementType="road" elementId="1" contactPoint="end"/>',
        _line(0, 10, 0, 1.5707963267948966, 10),
    )
    var xml = (
        _loose_fixture(0)
        .replace(
            (
                '<successor elementType="road" elementId="2"'
                ' contactPoint="start"/>'
            ),
            '<successor elementType="junction" elementId="100"/>',
        )
        .replace(
            "</OpenDRIVE>",
            extra
            + '<junction id="100"><connection id="0" incomingRoad="1"'
            ' connectingRoad="4" contactPoint="start"><laneLink from="-1"'
            ' to="-1"/></connection><connection id="1" incomingRoad="1"'
            ' connectingRoad="2" contactPoint="start"><laneLink from="-1"'
            ' to="-1"/></connection></junction></OpenDRIVE>',
        )
    )
    var map = load_opendrive(xml)
    var graph = GlobalRoutePlanner(map, Length(2, METER))
    var start = graph.localize(map, Vector3(2, 0, 0)).value()
    var branch = graph.localize(map, Vector3(10, -5, 0)).value()
    var route: List[RouteNodeId] = [start[0], branch[0], branch[1]]
    # Coincident successor entries share a graph node. The last topology
    # pair uses the east-facing parking entry as its incoming exit vector.
    assert_equal(graph.edge(start[0], branch[0]).exit_vector.value().x, 1)
    assert_equal(graph.turn_decision(1, route), OPTION_LEFT)


def test_lane_link_rejects_a_valid_waypoint_from_another_road() raises:
    var map = load_opendrive(TWO_LANE)
    var graph = GlobalRoutePlanner(map, Length(2, METER))
    var current = map.closest_waypoint_on_road(Vector3(5, 1.75, 0)).value()
    var other = map.closest_waypoint_on_road(Vector3(60, 5.25, 0)).value()
    var source = graph.localize(map, Vector3(5, 1.75, 0)).value()[0]
    var edge_count = graph.edge_count()
    # Both waypoints are valid driving-lane positions. A helper caller
    # that supplies a different road must not create a cross-road change.
    assert_false(graph._link(map, source.value, current, other, True))
    assert_equal(graph.edge_count(), edge_count)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
