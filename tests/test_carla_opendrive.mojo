# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's OpenDRIVE reader: every record of `assets/carla/town.xodr`.

The expected values are read off the file by hand, or come from a
Python copy of CARLA's C++ in the scratchpad where they need arithmetic.
"""

from extensions.carla.geometry import ARC, LINE, PARAM_POLY3, POLY3, SPIRAL
from extensions.carla.map import Map
from extensions.carla.opendrive import (
    load_opendrive,
    load_opendrive_file,
    xml_as_bool,
    xml_as_int,
    xml_as_uint,
)
from extensions.carla.road_info import (
    LANE_BIKING,
    LANE_BORDER,
    LANE_DRIVING,
    LANE_NONE,
    LANE_PARKING,
    LANE_SHOULDER,
    LANE_SIDEWALK,
    LaneId,
    MARK_CHANGE_BOTH,
    MARK_CHANGE_DECREASE,
    MARK_CHANGE_INCREASE,
    MARK_CHANGE_NONE,
    NO_JUNCTION,
    JuncId,
    RoadId,
    SignalId,
    ControllerId,
)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime TOWN = "assets/carla/town.xodr"


def _road(map: Map, id: Int) raises -> Int:
    return map.road_index(RoadId(id))


# --- pugixml's readers ----------------------------------------------------


def test_as_int_reads_like_pugixml() raises:
    assert_equal(xml_as_int(""), 0)
    assert_equal(xml_as_int("42"), 42)
    assert_equal(xml_as_int("  \\t\\n\\r-17abc"), 0)
    assert_equal(xml_as_int(" \t\n\r-17abc"), -17)
    assert_equal(xml_as_int("+5"), 5)
    assert_equal(xml_as_int("0x1F"), 31)
    assert_equal(xml_as_int("0XaB"), 171)
    assert_equal(xml_as_int("0"), 0)
    assert_equal(xml_as_int("007"), 7)
    assert_equal(xml_as_int("0y"), 0)
    assert_equal(xml_as_int("-"), 0)
    assert_equal(xml_as_int("2147483647"), 2147483647)
    assert_equal(xml_as_int("2147483648"), 2147483647)
    assert_equal(xml_as_int("-2147483648"), -2147483648)
    assert_equal(xml_as_int("-2147483649"), -2147483648)
    assert_equal(xml_as_int("99999999999"), 2147483647)
    assert_equal(xml_as_int("-99999999999"), -2147483648)
    assert_equal(xml_as_int("0x7FFFFFFF"), 2147483647)
    assert_equal(xml_as_int("0x123456789"), 2147483647)
    assert_equal(xml_as_int("1.9"), 1)


def test_as_uint_reads_like_pugixml() raises:
    assert_equal(xml_as_uint("4294967295"), 4294967295)
    assert_equal(xml_as_uint("4294967296"), 4294967295)
    assert_equal(xml_as_uint("5000000000"), 4294967295)
    assert_equal(xml_as_uint("0xFFFFFFFF"), 4294967295)
    assert_equal(xml_as_uint("-1"), 0)
    assert_equal(xml_as_uint("-0"), 0)
    assert_equal(xml_as_uint("12"), 12)


def test_as_bool_reads_like_pugixml() raises:
    assert_false(xml_as_bool(""))
    assert_true(xml_as_bool("1"))
    assert_true(xml_as_bool("true"))
    assert_true(xml_as_bool("True"))
    assert_true(xml_as_bool("yes"))
    assert_true(xml_as_bool("Yes"))
    assert_false(xml_as_bool("false"))
    assert_false(xml_as_bool("0"))


# --- the town -------------------------------------------------------------


def test_roads_and_sections() raises:
    var map = load_opendrive_file(TOWN)
    assert_equal(len(map.roads), 8)
    var ids = List[Int]()
    for road in map.roads:
        ids.append(road.id.value)
    assert_true(ids == [1, 2, 3, 5, 6, 7, 10, 11])
    ref one = map.road(RoadId(1))
    assert_equal(one.name, "incoming")
    assert_equal(one.length, 60.0)
    assert_false(one.is_junction)
    assert_equal(one.junction_id, NO_JUNCTION)
    assert_true(one.is_rht)
    assert_equal(one.successor, RoadId(100))
    assert_equal(one.predecessor, RoadId(0))
    assert_equal(len(one.sections), 2)
    assert_equal(one.sections[1].s, 30.0)
    assert_equal(one.sections[1].id.value, 1)
    assert_equal(len(one.sections[0].lanes), 5)
    assert_equal(one.sections[0].lanes[0].id, LaneId(-2))
    assert_equal(one.sections[0].lanes[0].type, LANE_SIDEWALK)
    assert_equal(one.sections[0].lanes[2].type, LANE_NONE)
    # Links within the road.
    assert_equal(one.sections[0].lanes[1].successor, LaneId(-1))
    assert_equal(one.sections[1].lanes[3].predecessor, LaneId(1))
    ref through = map.road(RoadId(10))
    assert_true(through.is_junction)
    assert_equal(through.junction_id, JuncId(100))
    assert_equal(through.predecessor, RoadId(1))
    assert_equal(through.successor, RoadId(2))
    # A left-hand road, a rule CARLA does not know, and no junction
    # attribute, which pugixml reads as junction 0.
    assert_false(map.road(RoadId(6)).is_rht)
    ref odd = map.road(RoadId(7))
    assert_true(odd.is_rht)
    assert_true(odd.is_junction)
    assert_equal(odd.junction_id, JuncId(0))


def test_lane_types() raises:
    var map = load_opendrive_file(TOWN)
    ref left = map.road(RoadId(6)).sections[0]
    assert_equal(left.lanes[left.lane_index(LaneId(2))].type, LANE_PARKING)
    assert_equal(left.lanes[left.lane_index(LaneId(-2))].type, LANE_BIKING)
    assert_equal(left.lanes[left.lane_index(LaneId(-3))].type, LANE_NONE)
    ref curvy = map.road(RoadId(5)).sections[0]
    assert_equal(curvy.lanes[curvy.lane_index(LaneId(-2))].type, LANE_SHOULDER)
    assert_equal(curvy.lanes[curvy.lane_index(LaneId(-3))].type, LANE_BORDER)
    assert_equal(curvy.lanes[curvy.lane_index(LaneId(1))].type, LANE_DRIVING)


def test_geometries() raises:
    var map = load_opendrive_file(TOWN)
    ref curvy = map.road(RoadId(5)).info.geometries
    assert_equal(len(curvy), 4)
    assert_equal(curvy[0].geometry.kind, SPIRAL)
    assert_equal(curvy[0].geometry.curvature_end, 0.05)
    assert_equal(curvy[1].geometry.kind, POLY3)
    assert_equal(curvy[1].s, 20.0)
    assert_equal(curvy[1].geometry.heading, 0.5)
    assert_equal(curvy[2].geometry.kind, PARAM_POLY3)
    # arcLength: p runs to the length, one interval per half meter.
    assert_almost_equal(curvy[2].geometry.samples[1].u, 0.5, atol=1e-12)
    assert_equal(curvy[3].geometry.kind, PARAM_POLY3)
    # No pRange reads as "", which CARLA takes as normalized: p runs to 1
    # in 20 intervals, and u = 10 p.
    assert_almost_equal(curvy[3].geometry.samples[1].u, 0.5, atol=1e-12)
    assert_equal(len(curvy[3].geometry.samples), 21)
    assert_equal(map.road(RoadId(11)).info.geometries[0].geometry.kind, ARC)
    assert_equal(
        map.road(RoadId(11)).info.geometries[0].geometry.curvature_start,
        -0.05,
    )
    # An unknown record and a record with no child are skipped.
    ref odd = map.road(RoadId(7)).info.geometries
    assert_equal(len(odd), 1)
    assert_equal(odd[0].geometry.kind, LINE)


def test_road_records() raises:
    var map = load_opendrive_file(TOWN)
    ref curvy = map.road(RoadId(5)).info
    assert_equal(len(curvy.elevations), 2)
    assert_equal(curvy.elevations[1].s, 30.0)
    # The cubic is shifted to read the road's s: 1.6 + 0.001 (s - 30)^2.
    assert_almost_equal(curvy.elevations[1].polynomial.evaluate(40.0), 1.7)
    assert_equal(len(curvy.lane_offsets), 2)
    assert_almost_equal(curvy.lane_offsets[1].polynomial.evaluate(30.0), 0.6)
    assert_equal(len(curvy.speeds), 1)
    assert_equal(curvy.speeds[0].speed, 80.0)
    assert_equal(curvy.speeds[0].type, "Town")
    # A road with no laneOffset and no elevation gets zero records.
    ref through = map.road(RoadId(10)).info
    assert_equal(len(through.lane_offsets), 1)
    assert_equal(through.lane_offsets[0].polynomial.evaluate(12.0), 0.0)
    assert_equal(len(through.elevations), 1)


def test_lane_records() raises:
    var map = load_opendrive_file(TOWN)
    ref one = map.road(RoadId(1))
    ref right = one.sections[1].lanes[one.sections[1].lane_index(LaneId(-1))]
    assert_equal(len(right.info.widths), 2)
    # sOffset 10 in the section at 30 starts at s = 40.
    assert_equal(right.info.widths[1].s, 40.0)
    assert_almost_equal(right.info.widths[1].polynomial.evaluate(50.0), 4.0)
    ref lane = one.sections[0].lanes[one.sections[0].lane_index(LaneId(-1))]
    assert_equal(len(lane.info.materials), 1)
    assert_equal(lane.info.materials[0].surface, "asphalt")
    assert_equal(lane.info.materials[0].friction, 0.8)
    assert_equal(lane.info.materials[0].roughness, 0.01)
    assert_equal(lane.info.visibilities[0].forward, 100.0)
    assert_equal(lane.info.visibilities[0].back, 50.0)
    assert_equal(lane.info.visibilities[0].left, 5.0)
    assert_equal(lane.info.visibilities[0].right, 5.0)
    assert_equal(lane.info.speeds[0].speed, 40.0)
    assert_equal(lane.info.accesses[0].restriction, "bus")
    assert_equal(lane.info.rules[0].value, "no stopping")
    ref mark = lane.info.marks[0]
    assert_equal(mark.type, "broken")
    assert_equal(mark.color, "standard")
    assert_equal(mark.material, "standard")
    assert_equal(mark.weight, "standard")
    assert_equal(mark.width, 0.15)
    assert_equal(mark.height, 0.01)
    assert_equal(mark.lane_change, MARK_CHANGE_INCREASE)
    assert_equal(mark.type_name, "broken")
    assert_equal(mark.type_width, 0.15)
    assert_true(mark.is_rht)
    assert_equal(len(mark.lines), 1)
    assert_equal(mark.lines[0].length, 3.0)
    assert_equal(mark.lines[0].space, 9.0)
    assert_equal(mark.lines[0].rule, "caution")
    ref walk = one.sections[0].lanes[0]
    assert_equal(walk.info.borders[0].polynomial.evaluate(3.0), 5.5)
    assert_equal(walk.info.heights[0].inner, 0.15)
    assert_equal(walk.info.heights[0].outer, 0.15)
    # No laneChange reads as both, and no type child gives no lines.
    assert_equal(walk.info.marks[0].lane_change, MARK_CHANGE_BOTH)
    assert_equal(walk.info.marks[0].type_name, "")
    assert_equal(len(walk.info.marks[0].lines), 0)
    ref left = one.sections[0].lanes[one.sections[0].lane_index(LaneId(1))]
    assert_equal(left.info.marks[0].lane_change, MARK_CHANGE_BOTH)
    ref center = one.sections[0].lanes[one.sections[0].lane_index(LaneId(0))]
    assert_equal(center.info.marks[0].lane_change, MARK_CHANGE_NONE)
    assert_equal(center.info.marks[0].color, "yellow")
    # A lane with no width element gets a zero width record.
    ref curvy = map.road(RoadId(5)).sections[0]
    ref border = curvy.lanes[curvy.lane_index(LaneId(-3))]
    assert_equal(len(border.info.widths), 1)
    assert_equal(border.info.widths[0].polynomial.evaluate(3.0), 0.0)
    ref left_hand = map.road(RoadId(6)).sections[0]
    ref parking = left_hand.lanes[left_hand.lane_index(LaneId(2))]
    assert_equal(parking.info.marks[0].lane_change, MARK_CHANGE_DECREASE)
    assert_false(parking.info.marks[0].is_rht)


def test_junctions_and_controllers() raises:
    var map = load_opendrive_file(TOWN)
    assert_equal(len(map.junctions), 1)
    ref junction = map.junction(JuncId(100))
    assert_equal(junction.name, "center")
    assert_equal(len(junction.connections), 3)
    assert_equal(junction.connections[1].connecting_road, RoadId(11))
    assert_equal(junction.connections[2].incoming_road, RoadId(2))
    assert_equal(len(junction.connections[2].lane_links), 1)
    assert_equal(junction.connections[2].lane_links[0].from_lane, LaneId(1))
    assert_equal(len(junction.controllers), 1)
    assert_equal(junction.controllers[0], ControllerId("1"))
    assert_equal(len(map.controllers), 2)
    ref one = map.controller(ControllerId("1"))
    assert_equal(one.name, "ctrl1")
    assert_equal(one.sequence, 0)
    assert_equal(len(one.signals), 1)
    assert_equal(one.signals[0], SignalId("1001"))
    assert_equal(one.junctions[0], JuncId(100))
    assert_equal(len(map.controller(ControllerId("2")).junctions), 0)


def test_signals() raises:
    var map = load_opendrive_file(TOWN)
    assert_equal(len(map.signals), 7)
    ref light = map.signal(SignalId("1001"))
    assert_true(light.is_dynamic())
    assert_equal(light.type, "1000001")
    assert_equal(light.country, "OpenDRIVE")
    assert_equal(light.z_offset, 3.0)
    assert_equal(len(light.dependencies), 1)
    assert_equal(light.dependencies[0].dependency_id, "1003")
    assert_equal(light.dependencies[0].type, "yield")
    assert_equal(len(light.controllers), 1)
    ref stop = map.signal(SignalId("1002"))
    assert_false(stop.is_dynamic())
    assert_equal(stop.h_offset, 0.1)
    assert_equal(len(stop.controllers), 0)
    ref yield_sign = map.signal(SignalId("1003"))
    assert_true(yield_sign.using_inertial_position)
    # RoadRunner's objects become signals.
    ref speed = map.signal(SignalId("2001"))
    assert_equal(speed.type, "274")
    assert_equal(speed.subtype, "30")
    assert_equal(speed.value, 30.0)
    assert_equal(speed.unit, "mph")
    assert_equal(speed.text, "30")
    assert_equal(speed.dynamic, "no")
    ref fixed = map.signal(SignalId("2002"))
    assert_equal(fixed.value, 40.0)
    ref stencil = map.signal(SignalId("2003"))
    assert_equal(stencil.type, "206")
    assert_equal(stencil.value, 0.0)
    # References: the one whose validity is lane 0 to lane 0 is gone.
    ref refs = map.road(RoadId(1)).info.signals
    var ids = List[String]()
    for r in refs:
        ids.append(r.signal_id.value)
    assert_true(ids == ["2001", "2002", "1004", "2003", "1002", "1001", "1002"])
    # A reference with no validity gets the lanes that face it: "none"
    # faces both ways.
    ref both = refs[6]
    assert_equal(len(both.validities), 2)
    assert_equal(both.validities[0].from_lane, LaneId(1))
    assert_equal(both.validities[0].to_lane, LaneId(2))
    assert_equal(both.validities[1].from_lane, LaneId(-2))
    assert_equal(both.validities[1].to_lane, LaneId(-1))
    # "-" faces the right lanes.
    assert_equal(len(refs[4].validities), 1)
    assert_equal(refs[4].validities[0].from_lane, LaneId(-2))


def test_crosswalks() raises:
    var map = load_opendrive_file(TOWN)
    ref walks = map.road(RoadId(1)).info.crosswalks
    assert_equal(len(walks), 2)
    assert_equal(walks[0].name, "cw")
    assert_equal(walks[0].length, 10.0)
    assert_equal(walks[0].width, 3.0)
    assert_equal(walks[0].orientation, "none")
    assert_equal(len(walks[0].points), 5)
    assert_equal(walks[0].points[1].u, 5.0)
    # The second has no outline and reuses the first's corners.
    assert_equal(len(walks[1].points), 5)
    assert_equal(walks[1].points[2].v, 1.5)


def test_geo_reference() raises:
    var map = load_opendrive_file(TOWN)
    assert_equal(map.geo_reference.latitude_degrees, 49.0)
    assert_equal(map.geo_reference.longitude_degrees, 8.0)
    assert_equal(map.geo_projection.transverse_mercator.lat_0_degrees, 49.0)


def test_empty_and_bad_files() raises:
    var empty = load_opendrive("<Other><road id='1'/></Other>")
    assert_equal(len(empty.roads), 0)
    with assert_raises():
        _ = load_opendrive("<OpenDRIVE><road>")
    with assert_raises():
        _ = load_opendrive_file("assets/carla/missing.xodr")
    # std::stod on a speed that is not a number throws in CARLA.
    var head = String(
        "<OpenDRIVE><road id='1' length='10' junction='-1'><planView>"
        + "<geometry s='0' x='0' y='0' hdg='0' length='10'><line/>"
        + "</geometry></planView><lanes><laneSection s='0'><center>"
        + "<lane id='0' type='none'/></center><right><lane id='-1'"
        + " type='driving'><width sOffset='0' a='3' b='0' c='0' d='0'/>"
        + "</lane></right></laneSection></lanes><objects>"
    )
    var tail = String("</objects></road></OpenDRIVE>")
    with assert_raises():
        _ = load_opendrive(
            head + "<object id='5' name='Speed_fast' s='1' t='-5'/>" + tail
        )
    # A name with STATIC shorter than 13 bytes: substr throws.
    with assert_raises():
        _ = load_opendrive(
            head + "<object id='5' name='Speed_STATIC' s='1' t='-5'/>" + tail
        )
    var fine = load_opendrive(
        head + "<object id='5' name='speed_12' s='1' t='-5'/>" + tail
    )
    assert_equal(fine.signal(SignalId("5")).value, 12.0)
    # A signal on a road with no plan view cannot be placed.
    with assert_raises():
        _ = load_opendrive(
            "<OpenDRIVE><road id='1' length='10'><signals><signal id='x'"
            + " s='1'/></signals></road><road id='2'/></OpenDRIVE>"
        )


def test_sparse_file() raises:
    # Each element here leaves out the children it may have.
    var map = load_opendrive(
        "<OpenDRIVE><road id='1' length='10' junction='-1'><type s='0'"
        + " type='town'/><planView><geometry s='0' x='0' y='0' hdg='0'"
        + " length='10'><line/></geometry></planView><lanes><laneSection"
        + " s='0'><left/><center><lane id='0' type='none'/></center>"
        + "</laneSection></lanes><objects><object id='7' type='crosswalk'"
        + " name='cw' s='2' t='0'><outline/></object></objects></road>"
        + "<road id='2' length='5' junction='-1'><lanes/></road>"
        + "<junction id='5' name='bare'/><junction id='6' name='links'>"
        + "<connection id='0' incomingRoad='1' connectingRoad='2'/>"
        + "</junction><controller id='c' name='none'/></OpenDRIVE>"
    )
    ref one = map.road(RoadId(1))
    assert_equal(len(one.info.speeds), 1)
    assert_equal(one.info.speeds[0].speed, 0.0)
    assert_equal(len(one.sections[0].lanes), 1)
    assert_equal(len(one.info.crosswalks[0].points), 0)
    assert_equal(len(map.road(RoadId(2)).sections), 0)
    assert_equal(len(map.junction(JuncId(5)).connections), 0)
    assert_equal(len(map.junction(JuncId(6)).connections[0].lane_links), 0)
    assert_equal(len(map.controller(ControllerId("c")).signals), 0)
    # A number longer than twelve digits overflows, as in pugixml.
    assert_equal(xml_as_int("1234567890123"), 2147483647)
    assert_equal(xml_as_uint("00001234567890123"), 4294967295)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
