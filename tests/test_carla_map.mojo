# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's road model, map builder and map queries.

Most expected values come from `carla_ref.py` in the scratchpad: a
Python copy of CARLA's C++ `road/` code that reads the same town. The
rest are worked by hand from the file: road 1 runs east from the origin,
each lane is 3.5 meters wide, and CARLA's y is OpenDRIVE's y negated.
"""

from extensions.carla.geometry import LINE, RoadGeometry, with_arc
from extensions.carla.map import (
    Connection,
    Controller,
    Junction,
    Landmark,
    Map,
    RoadObject,
    SIGNAL_MAXIMUM_SPEED,
    SIGNAL_STOP,
    Signal,
    Waypoint,
    bump_deformation,
    is_traffic_light,
    map_deformation,
    segment_distance_2d,
    z_pos_in_deformation,
)
from extensions.carla.map_builder import (
    MapBuilder,
    check_signals_on_roads,
    default_validities,
    junction_box,
)
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Lane, LaneKey, LaneSection, Road
from extensions.carla.road_info import (
    BOTTS_DOTS,
    BROKEN,
    CHANGE_BOTH,
    CHANGE_LEFT,
    CHANGE_NONE,
    CHANGE_RIGHT,
    ConId,
    ControllerId,
    CrosswalkPoint,
    CURB,
    GRASS,
    InformationSet,
    JuncId,
    LANE_ANY,
    LANE_BIKING,
    LANE_DRIVING,
    LANE_NONE,
    LANE_ON_RAMP,
    LANE_PARKING,
    LANE_SHOULDER,
    LANE_SIDEWALK,
    LANE_TRAM,
    LaneChange,
    LaneId,
    LaneMarking,
    LaneMarkingColor,
    LaneMarkingType,
    LaneType,
    LaneValidity,
    MARKING_BLUE,
    MARKING_GREEN,
    MARKING_OTHER,
    MARKING_RED,
    MARKING_STANDARD,
    MARKING_WHITE,
    MARKING_YELLOW,
    MARK_CHANGE_BOTH,
    MARK_CHANGE_DECREASE,
    MARK_CHANGE_INCREASE,
    MARK_CHANGE_NONE,
    MarkLaneChange,
    NO_JUNCTION,
    NO_MARKING,
    ORIENTATION_BOTH,
    ORIENTATION_NEGATIVE,
    ORIENTATION_POSITIVE,
    OTHER,
    RoadId,
    RoadInfoElevation,
    RoadInfoGeometry,
    RoadInfoLaneAccess,
    RoadInfoLaneBorder,
    RoadInfoLaneHeight,
    RoadInfoLaneMaterial,
    RoadInfoLaneRule,
    RoadInfoLaneVisibility,
    RoadInfoLaneWidth,
    RoadInfoMarkRecord,
    RoadInfoMarkTypeLine,
    RoadInfoSignal,
    SOLID,
    SOLID_SOLID,
    SectionId,
    SignalId,
    SignalOrientation,
    info_at,
    infos_in_range,
    lane_marking_color_of,
    lane_marking_type_of,
    lane_type_of,
    mark_lane_change_of,
    signal_orientation_of,
    sort_infos,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER

comptime TOWN = "assets/carla/town.xodr"


def _w(road: Int, section: Int, lane: Int, s: Float64) -> Waypoint:
    return Waypoint(RoadId(road), SectionId(section), LaneId(lane), s)


def _m(value: Float32) -> Length:
    return Length(value, METER)


def _near(
    a: Vector3, x: Float64, y: Float64, z: Float64, tol: Float64 = 1e-4
) raises:
    assert_almost_equal(Float64(a.x), x, atol=tol)
    assert_almost_equal(Float64(a.y), y, atol=tol)
    assert_almost_equal(Float64(a.z), z, atol=tol)


def _same(w: Waypoint, road: Int, section: Int, lane: Int, s: Float64) raises:
    assert_equal(w.road_id, RoadId(road))
    assert_equal(w.section_id, SectionId(section))
    assert_equal(w.lane_id, LaneId(lane))
    assert_almost_equal(w.s, s, atol=1e-4)


def _flat_road(
    mut b: MapBuilder,
    id: Int,
    x: Float64,
    y: Float64,
    heading: Float64,
    length: Float64,
    junction: Int,
    predecessor: Int,
    successor: Int,
    rht: Bool,
    lanes: List[Tuple[Int, LaneType, Int, Int]],
) raises -> Int:
    # One flat, straight section; each lane 3.5 m wide, lane 0 none.
    var r = b.add_road(
        RoadId(id),
        "road",
        length,
        JuncId(junction),
        RoadId(predecessor),
        RoadId(successor),
        rht,
    )
    var sec = b.add_road_section(r, SectionId(0), 0.0)
    for lane in lanes:
        _ = b.add_road_section_lane(
            r,
            sec,
            LaneId(lane[0]),
            lane[1],
            False,
            LaneId(lane[2]),
            LaneId(lane[3]),
        )
        var width = 0.0 if lane[0] == 0 else 3.5
        b.create_lane_width(
            b.lane(RoadId(id), LaneId(lane[0]), 0.0), 0.0, width, 0, 0, 0
        )
    b.create_section_offset(r, 0.0, 0, 0, 0, 0)
    b.add_road_elevation_profile(r, 0.0, 0, 0, 0, 0)
    b.add_road_geometry_line(r, 0.0, x, y, heading, length)
    return r


# --- road_info ------------------------------------------------------------


def test_ids_and_kinds() raises:
    assert_true(RoadId(0).is_valid())
    assert_true(RoadId(4294967295).is_valid())
    assert_false(RoadId(-1).is_valid())
    assert_false(RoadId(4294967296).is_valid())
    assert_true(SectionId(3).is_valid())
    assert_false(SectionId(-1).is_valid())
    assert_false(SectionId(1 << 33).is_valid())
    assert_true(JuncId(-1).is_valid())
    assert_false(JuncId(-2147483649).is_valid())
    assert_false(JuncId(2147483648).is_valid())
    assert_true(ConId(7).is_valid())
    assert_false(ConId(-7).is_valid())
    assert_false(ConId(1 << 32).is_valid())
    assert_true(LaneId(-3).is_valid())
    assert_false(LaneId(-2147483649).is_valid())
    assert_true(SignalId("a").is_valid())
    assert_false(SignalId("").is_valid())
    assert_true(ControllerId("c").is_valid())
    assert_false(ControllerId("").is_valid())
    assert_true(LANE_ANY.is_valid())
    assert_true(LANE_ON_RAMP.is_valid())
    assert_false(LaneType(0).is_valid())
    assert_false(LaneType(1 << 21).is_valid())
    assert_false(LaneType(-3).is_valid())
    assert_equal((LANE_DRIVING | LANE_SHOULDER).value, 10)
    assert_true(LANE_DRIVING.matches(LANE_ANY))
    assert_false(LANE_NONE.matches(LANE_ANY))
    assert_true(ORIENTATION_BOTH.is_valid())
    assert_false(SignalOrientation(-1).is_valid())
    assert_false(SignalOrientation(3).is_valid())
    assert_true(MARK_CHANGE_BOTH.is_valid())
    assert_false(MarkLaneChange(-1).is_valid())
    assert_false(MarkLaneChange(4).is_valid())
    assert_true(NO_MARKING.is_valid())
    assert_false(LaneMarkingType(-1).is_valid())
    assert_false(LaneMarkingType(11).is_valid())
    assert_true(MARKING_OTHER.is_valid())
    assert_false(LaneMarkingColor(-1).is_valid())
    assert_false(LaneMarkingColor(6).is_valid())
    assert_true(CHANGE_BOTH.is_valid())
    assert_false(LaneChange(-1).is_valid())
    assert_false(LaneChange(4).is_valid())
    assert_equal(CHANGE_BOTH & CHANGE_LEFT, CHANGE_LEFT)
    assert_equal(CHANGE_RIGHT | CHANGE_LEFT, CHANGE_BOTH)
    assert_equal(MARKING_WHITE, MARKING_STANDARD)


def test_names_to_kinds() raises:
    assert_equal(lane_type_of("Driving"), LANE_DRIVING)
    assert_equal(lane_type_of("onramp"), LANE_ON_RAMP)
    assert_equal(lane_type_of("TRAM"), LANE_TRAM)
    assert_equal(lane_type_of("nonsense"), LANE_NONE)
    assert_equal(signal_orientation_of("+"), ORIENTATION_POSITIVE)
    assert_equal(signal_orientation_of("-"), ORIENTATION_NEGATIVE)
    assert_equal(signal_orientation_of("none"), ORIENTATION_BOTH)
    assert_equal(mark_lane_change_of("Increase"), MARK_CHANGE_INCREASE)
    assert_equal(mark_lane_change_of("decrease"), MARK_CHANGE_DECREASE)
    assert_equal(mark_lane_change_of("NONE"), MARK_CHANGE_NONE)
    assert_equal(mark_lane_change_of(""), MARK_CHANGE_BOTH)
    assert_equal(lane_marking_type_of("Solid Solid"), SOLID_SOLID)
    assert_equal(lane_marking_type_of("botts dots"), BOTTS_DOTS)
    assert_equal(lane_marking_type_of("none"), NO_MARKING)
    assert_equal(lane_marking_type_of("zigzag"), OTHER)
    assert_equal(lane_marking_color_of("Standard"), MARKING_STANDARD)
    assert_equal(lane_marking_color_of("white"), MARKING_STANDARD)
    assert_equal(lane_marking_color_of("blue"), MARKING_BLUE)
    assert_equal(lane_marking_color_of("green"), MARKING_GREEN)
    assert_equal(lane_marking_color_of("red"), MARKING_RED)
    assert_equal(lane_marking_color_of("YELLOW"), MARKING_YELLOW)
    assert_equal(lane_marking_color_of("pink"), MARKING_OTHER)


def test_lane_marking() raises:
    # `LaneMarking(RoadInfoMarkRecord)`: increase is right on a right-hand
    # road and left on a left-hand one.
    var right = RoadInfoMarkRecord(
        0.0,
        0,
        "solid",
        "",
        "yellow",
        "",
        0.2,
        MARK_CHANGE_INCREASE,
        0,
        "",
        0,
        True,
    )
    var m = LaneMarking(right)
    assert_equal(m.type, SOLID)
    assert_equal(m.color, MARKING_YELLOW)
    assert_equal(m.lane_change, CHANGE_RIGHT)
    assert_equal(m.width, 0.2)
    assert_equal(m.color_name(), "yellow")
    right.is_rht = False
    assert_equal(LaneMarking(right).lane_change, CHANGE_LEFT)
    right.lane_change = MARK_CHANGE_DECREASE
    assert_equal(LaneMarking(right).lane_change, CHANGE_RIGHT)
    right.is_rht = True
    assert_equal(LaneMarking(right).lane_change, CHANGE_LEFT)
    right.lane_change = MARK_CHANGE_BOTH
    assert_equal(LaneMarking(right).lane_change, CHANGE_BOTH)
    right.lane_change = MARK_CHANGE_NONE
    assert_equal(LaneMarking(right).lane_change, CHANGE_NONE)
    right.color = "blue"
    assert_equal(LaneMarking(right).color_name(), "white")
    assert_equal(
        String(LaneMarking(right)),
        "LaneMarking(type=2, color=1, lane_change=0, width=0.2)",
    )
    # CARLA's defaults: white standard paint 0.15 m wide, right-hand.
    var plain = RoadInfoMarkRecord(3.0, 1)
    assert_equal(plain.color, "white")
    assert_equal(plain.material, "standard")
    assert_equal(plain.width, 0.15)
    assert_equal(plain.lane_change, MARK_CHANGE_NONE)
    assert_true(plain.is_rht)
    assert_equal(plain.distance(), 3.0)
    # A marking made from its parts checks each part.
    var made = LaneMarking(SOLID, MARKING_WHITE, CHANGE_LEFT, 0.25)
    assert_equal(made.lane_change, CHANGE_LEFT)
    assert_equal(made.width, 0.25)
    with assert_raises():
        _ = LaneMarking(LaneMarkingType(11), MARKING_WHITE, CHANGE_NONE, 0.1)
    with assert_raises():
        _ = LaneMarking(SOLID, LaneMarkingColor(6), CHANGE_NONE, 0.1)
    with assert_raises():
        _ = LaneMarking(SOLID, MARKING_WHITE, LaneChange(4), 0.1)


def test_information_set() raises:
    var widths = List[RoadInfoLaneWidth]()
    widths.append(RoadInfoLaneWidth(10.0, CubicPolynomial.constant(2.0)))
    widths.append(RoadInfoLaneWidth(0.0, CubicPolynomial.constant(1.0)))
    widths.append(RoadInfoLaneWidth(10.0, CubicPolynomial.constant(3.0)))
    sort_infos(widths)
    assert_equal(widths[0].s, 0.0)
    # A tie keeps the order the records came in.
    assert_equal(widths[1].polynomial.a, 2.0)
    assert_equal(widths[2].polynomial.a, 3.0)
    assert_false(info_at(widths, -1.0))
    assert_equal(info_at(widths, 5.0).value().polynomial.a, 1.0)
    # The last record at s wins.
    assert_equal(info_at(widths, 10.0).value().polynomial.a, 3.0)
    var forward = infos_in_range(widths, 0.0, 10.0)
    assert_equal(len(forward), 3)
    var backward = infos_in_range(widths, 20.0, 5.0)
    assert_equal(len(backward), 2)
    assert_equal(backward[0].polynomial.a, 3.0)
    var none = infos_in_range(widths, 1.0, 2.0)
    assert_equal(len(none), 0)
    var info = InformationSet()
    info.elevations.append(RoadInfoElevation(5.0, CubicPolynomial.constant(1)))
    info.elevations.append(RoadInfoElevation(1.0, CubicPolynomial.constant(2)))
    for s in [5.0, 1.0]:
        var c = CubicPolynomial.constant(s)
        info.borders.append(RoadInfoLaneBorder(s, c))
        info.heights.append(RoadInfoLaneHeight(s, s, s))
        info.materials.append(RoadInfoLaneMaterial(s, "asphalt", s, s))
        info.visibilities.append(RoadInfoLaneVisibility(s, s, s, s, s))
        info.accesses.append(RoadInfoLaneAccess(s, "bus"))
        info.rules.append(RoadInfoLaneRule(s, "no stopping"))
    info.sort()
    assert_equal(info.elevations[0].s, 1.0)
    assert_equal(info.borders[0].s, 1.0)
    assert_equal(info.heights[0].inner, 1.0)
    assert_equal(info.materials[0].friction, 1.0)
    assert_equal(info.visibilities[0].back, 1.0)
    assert_equal(info.accesses[1].s, 5.0)
    assert_equal(info.rules[1].s, 5.0)
    var lines = List[RoadInfoMarkTypeLine]()
    lines.append(RoadInfoMarkTypeLine(5.0, 0, 3.0, 9.0, 0.0, "none", 0.15))
    lines.append(RoadInfoMarkTypeLine(1.0, 0, 3.0, 9.0, 0.0, "none", 0.15))
    sort_infos(lines)
    assert_equal(lines[0].s, 1.0)
    # A backward walk over no records finds none.
    assert_equal(len(infos_in_range(List[RoadInfoLaneWidth](), 20.0, 5.0)), 0)
    var v = LaneValidity(LaneId(-2), LaneId(-1))
    assert_true(v.holds_for(LaneId(-1)))
    assert_false(v.holds_for(LaneId(0)))
    assert_false(v.holds_for(LaneId(-3)))
    var reference = RoadInfoSignal(
        SignalId("s"), RoadId(1), 4.0, 1.0, "-", List[LaneValidity]()
    )
    assert_equal(reference.orientation(), ORIENTATION_NEGATIVE)
    assert_equal(reference.distance(), 4.0)


# --- road -----------------------------------------------------------------


def test_sections_and_lanes() raises:
    with assert_raises():
        _ = LaneSection(SectionId(-1), 0.0)
    var section = LaneSection(SectionId(0), 5.0)
    assert_equal(section.add_lane(LaneId(1)), 0)
    assert_equal(section.add_lane(LaneId(-1)), 0)
    assert_equal(section.add_lane(LaneId(0)), 1)
    # Adding an id again finds the lane that is there.
    assert_equal(section.add_lane(LaneId(-1)), 0)
    assert_equal(len(section.lanes), 3)
    with assert_raises():
        _ = section.add_lane(LaneId(1 << 40))
    assert_equal(section.lane_index(LaneId(7)), -1)
    assert_true(section.contains_lane(LaneId(0)))
    assert_equal(section.lanes[2].distance, 5.0)
    section.lanes[0].type = LANE_DRIVING
    section.lanes[2].type = LANE_SIDEWALK
    var driving = section.lanes_of_type(LANE_DRIVING | LANE_SIDEWALK)
    assert_equal(len(driving), 2)
    assert_equal(driving[1], LaneId(1))
    with assert_raises():
        _ = section.lanes_of_type(LaneType(0))


def test_road_refuses_bad_ids() raises:
    with assert_raises():
        _ = Road(RoadId(-1), "", 1.0, NO_JUNCTION, RoadId(0), RoadId(0), True)
    with assert_raises():
        _ = Road(
            RoadId(1), "", 1.0, JuncId(1 << 40), RoadId(0), RoadId(0), True
        )
    with assert_raises():
        _ = Road(RoadId(1), "", 1.0, NO_JUNCTION, RoadId(-5), RoadId(0), True)
    with assert_raises():
        _ = Road(RoadId(1), "", 1.0, NO_JUNCTION, RoadId(0), RoadId(-5), True)


def test_road_sections() raises:
    var road = Road(
        RoadId(1), "r", 50.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    assert_equal(road.add_section(SectionId(0), 0.0), 0)
    assert_equal(road.add_section(SectionId(1), 20.0), 1)
    # A second section at the same s goes after the first, as in a
    # multimap.
    assert_equal(road.add_section(SectionId(2), 20.0), 2)
    assert_equal(road.add_section(SectionId(3), 10.0), 1)
    assert_equal(road.section_index(SectionId(2)), 3)
    with assert_raises():
        _ = road.section_index(SectionId(9))
    assert_equal(road.upper_bound(12.0), 20.0)
    assert_equal(road.upper_bound(25.0), 50.0)
    assert_equal(road.section_length(1), 10.0)
    assert_equal(len(road.sections_at(-1.0)), 0)
    var both = road.sections_at(25.0)
    assert_equal(len(both), 2)
    assert_equal(both[1], 3)
    _ = road.sections[2].add_lane(LaneId(-1))
    _ = road.sections[3].add_lane(LaneId(-1))
    _ = road.sections[3].add_lane(LaneId(2))
    _ = road.sections[0].add_lane(LaneId(2))
    var found = road.lane_by_distance(22.0, LaneId(2))
    assert_equal(found[0], 3)
    with assert_raises():
        _ = road.lane_by_distance(22.0, LaneId(5))
    assert_equal(len(road.lanes_by_distance(22.0)), 3)
    # The later section wins an id both have.
    var by_id = road.lanes_at(22.0)
    assert_equal(len(by_id), 2)
    assert_equal(by_id[0][0], 3)
    assert_equal(road.next_lane(0.0, LaneId(-1)).value()[0], 2)
    assert_false(road.next_lane(0.0, LaneId(7)))
    assert_equal(road.prev_lane(20.0, LaneId(2)).value()[0], 0)
    assert_false(road.prev_lane(20.0, LaneId(7)))
    assert_equal(road.start_section(LaneId(-1)), 2)
    assert_equal(road.end_section(LaneId(2)), 3)
    assert_equal(road.start_section(LaneId(9)), -1)
    assert_equal(road.end_section(LaneId(9)), -1)
    assert_equal(road.lane_length(0), 10.0)


def test_road_records_are_needed() raises:
    var road = Road(
        RoadId(1), "r", 10.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    with assert_raises():
        _ = road.elevation_on(1.0)
    with assert_raises():
        _ = road.directed_point(1.0)
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial(1.0, 0.1, 0, 0, 0))
    )
    with assert_raises():
        _ = road.directed_point(1.0)
    with assert_raises():
        _ = road.lane_is_straight(0)
    road.info.geometries.append(
        RoadInfoGeometry(0.0, RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 10.0))
    )
    # No lane offset record: CARLA keeps the line where it is.
    var p = road.directed_point(4.0)
    assert_almost_equal(p.x, 4.0)
    assert_almost_equal(p.z, 1.4, atol=1e-6)
    assert_almost_equal(p.pitch, 0.1)
    # The width of a lane with no record is zero.
    assert_equal(road.lane_width(0, 0, 5.0), 0.0)
    with assert_raises():
        _ = road.lane_width(0, 0, 11.0)
    # A transform needs a width record and a lane offset record.
    with assert_raises():
        _ = road.lane_transform(0, 0, 5.0)
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(0.0, CubicPolynomial.constant(3.0))
    )
    with assert_raises():
        _ = road.lane_transform(0, 0, 5.0)
    with assert_raises():
        _ = road.lane_transform(0, 0, 11.0)
    with assert_raises():
        _ = road.lane_transform(0, 0, -1.0)
    with assert_raises():
        _ = road.lane_transform(1, 0, 5.0)
    with assert_raises():
        _ = road.lane_transform(-1, 0, 5.0)
    with assert_raises():
        _ = road.lane_transform(0, 3, 5.0)
    with assert_raises():
        _ = road.lane_transform(0, -1, 5.0)
    with assert_raises():
        _ = road.nearest_lane(5.0, Vector3(0, 0, 0), LaneType(0))


def test_road_edges() raises:
    # A section with no lanes has no lanes of any type.
    assert_equal(len(LaneSection(SectionId(0), 0.0).lanes_of_type(LANE_ANY)), 0)
    # A road with no sections finds nothing.
    var road = Road(
        RoadId(1), "r", 10.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    with assert_raises():
        _ = road.section_index(SectionId(0))
    assert_equal(road.upper_bound(2.5), 10.0)
    assert_equal(len(road.sections_at(2.5)), 0)
    assert_false(road.next_lane(2.5, LaneId(-1)))
    assert_false(road.prev_lane(2.5, LaneId(-1)))
    assert_equal(road.start_section(LaneId(-1)), -1)
    assert_equal(road.end_section(LaneId(-1)), -1)
    # Before the first section there are no lanes.
    _ = road.add_section(SectionId(0), 5.0)
    _ = road.sections[0].add_lane(LaneId(1))
    with assert_raises():
        _ = road.lane_by_distance(2.5, LaneId(1))
    assert_equal(len(road.lanes_by_distance(2.5)), 0)
    assert_equal(len(road.lanes_at(2.5)), 0)
    # A second section at the same s puts its lower id first.
    _ = road.add_section(SectionId(1), 5.0)
    _ = road.sections[1].add_lane(LaneId(-1))
    var by_id = road.lanes_at(7.5)
    assert_equal(len(by_id), 2)
    assert_equal(by_id[0][0], 1)
    assert_equal(by_id[1][0], 0)
    # A section with no lanes adds none.
    var bare = Road(
        RoadId(2), "r", 10.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = bare.add_section(SectionId(0), 0.0)
    assert_equal(len(bare.lanes_by_distance(2.5)), 0)
    assert_equal(len(bare.lanes_at(2.5)), 0)
    bare.info.geometries.append(
        RoadInfoGeometry(0.0, RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 10.0))
    )
    # With no elevation record a line section is straight.
    assert_true(bare.lane_is_straight(0))
    bare.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial(0, 0, 0, 0, 0))
    )
    var nearest = bare.nearest_lane(2.5, Vector3(2.5, 1, 0))
    assert_false(nearest[0])
    assert_equal(nearest[1], 1.7976931348623157e308)


def test_straight_lanes() raises:
    var map = load_opendrive_file(TOWN)
    assert_true(map.road(RoadId(1)).lane_is_straight(0))
    # An arc is not straight, nor is a section that outruns its line, nor
    # a road whose elevation curves.
    assert_false(map.road(RoadId(11)).lane_is_straight(0))
    assert_false(map.road(RoadId(5)).lane_is_straight(0))
    var road = Road(
        RoadId(1), "r", 20.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = road.add_section(SectionId(0), 0.0)
    road.info.geometries.append(
        RoadInfoGeometry(0.0, RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 10.0))
    )
    assert_false(road.lane_is_straight(0))
    road.length = 10.0
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial(0, 0, 0, 0.001, 0))
    )
    assert_false(road.lane_is_straight(0))
    road.info.elevations[0] = RoadInfoElevation(
        0.0, CubicPolynomial(0, 0.1, 0, 0, 0)
    )
    assert_true(road.lane_is_straight(0))


def test_lane_transforms() raises:
    var map = load_opendrive_file(TOWN)
    # Values from the Python copy of `Lane::ComputeTransform`.
    var t = map.compute_transform(_w(1, 0, -1, 10.0))
    _near(t.location, 10.0, 1.75, 0.0)
    assert_almost_equal(t.rotation.yaw, 0.0, atol=1e-5)
    t = map.compute_transform(_w(1, 1, -1, 50.0))
    _near(t.location, 50.0, 2.0, 0.0)
    assert_almost_equal(t.rotation.yaw, 1.4323944878270582, atol=1e-4)
    t = map.compute_transform(_w(1, 0, 1, 10.0))
    _near(t.location, 10.0, -1.75, 0.0)
    assert_almost_equal(t.rotation.yaw, 180.0, atol=1e-4)
    assert_almost_equal(t.rotation.pitch, 360.0, atol=1e-4)
    t = map.compute_transform(_w(11, 0, -1, 10.0))
    _near(t.location, 68.74951607952671, 3.9841182455007007, 0.0)
    assert_almost_equal(t.rotation.yaw, 28.64788975654116, atol=1e-4)
    t = map.compute_transform(_w(5, 0, -1, 10.0))
    _near(t.location, 10.140229715463569, -99.17595478399882, 1.2, 1e-3)
    assert_almost_equal(t.rotation.pitch, -1.1457628381751033, atol=1e-4)
    assert_almost_equal(t.rotation.yaw, -7.16197243913529, atol=1e-3)
    t = map.compute_transform(_w(5, 0, 1, 40.0))
    _near(t.location, 37.0165078846415, -116.97860369629684, 1.7, 1e-3)
    assert_almost_equal(t.rotation.pitch, 361.1457628381751, atol=1e-4)
    assert_almost_equal(t.rotation.yaw, 133.52474222667973, atol=1e-3)
    t = map.compute_transform(_w(5, 0, -2, 50.0))
    _near(t.location, 50.69409544732411, -117.7093508614975, 2.0, 1e-3)
    assert_almost_equal(t.rotation.yaw, -47.50675315890087, atol=1e-3)
    # A left-hand road's left lanes run with s.
    t = map.compute_transform(_w(6, 0, 1, 5.0))
    _near(t.location, 5.0, -201.75, 0.0)
    assert_almost_equal(t.rotation.yaw, 0.0, atol=1e-5)
    t = map.compute_transform(_w(6, 0, -1, 5.0))
    assert_almost_equal(t.rotation.yaw, 180.0, atol=1e-5)
    # Lane 0 sits on the lane offset's line.
    t = map.compute_transform(_w(5, 0, 0, 0.0))
    _near(t.location, 0.0, -100.5, 1.0, 1e-3)


def test_lane_pitch_follows_grade_and_traffic_direction() raises:
    # A geometric invariant, independent of CARLA's old pitch scalar.
    for grade in [-0.2, 0.0, 0.2]:
        for rht in [True, False]:
            var builder = MapBuilder()
            var r = _flat_road(
                builder,
                1,
                0,
                0,
                0,
                100,
                -1,
                0,
                0,
                rht,
                [(-1, LANE_DRIVING, 0, 0), (1, LANE_DRIVING, 0, 0)],
            )
            builder.roads[r].info.elevations[0] = RoadInfoElevation(
                0.0, CubicPolynomial(0, grade, 0, 0, 0)
            )
            var map = builder.build()
            for lane in [-1, 1]:
                var here = _w(1, 0, lane, 40.0)
                var next = map.next(here, 1.0)[0]
                var pose = map.compute_transform(here)
                var along = map.compute_transform(next).location - pose.location
                along.normalize()
                assert_almost_equal(
                    Float64(pose.rotation.forward_vector().dot(along)),
                    1.0,
                    atol=1e-5,
                )


def test_lane_corners() raises:
    var map = load_opendrive_file(TOWN)
    var c = map.road(RoadId(1)).lane_corners(0, 1, 10.0)
    _near(c[0], 10.0, 3.5, 0.0)
    _near(c[1], 10.0, 0.0, 0.0)
    # A sidewalk rises six inches.
    c = map.road(RoadId(1)).lane_corners(0, 0, 10.0)
    _near(c[0], 10.0, 5.5, 0.1524)
    _near(c[1], 10.0, 3.5, 0.1524)
    # A junction's driving lane widens; others do not.
    c = map.road(RoadId(10)).lane_corners(0, 0, 5.0, 0.5)
    _near(c[0], 65.0, 4.0, 0.0)
    _near(c[1], 65.0, -0.5, 0.0)
    c = map.road(RoadId(1)).lane_corners(0, 1, 5.0, 0.5)
    _near(c[0], 5.0, 3.5, 0.0)
    c = map.road(RoadId(11)).lane_corners(0, 0, 0.0, 0.5)
    _near(c[0], 60.0, 5.5, 0.1524)
    # Past the road's end the corners clamp.
    c = map.road(RoadId(1)).lane_corners(1, 1, 99.0)
    _near(c[0], 60.0, 4.5, 0.0)
    var o = map.road(RoadId(1)).lane_edge_offsets(1, 1, 50.0)
    assert_almost_equal(o[0], 4.0, atol=1e-6)
    assert_almost_equal(o[1], 0.0, atol=1e-6)


def test_nearest_point_and_lane() raises:
    var map = load_opendrive_file(TOWN)
    var p = map.road(RoadId(1)).nearest_point(Vector3(20, 3, 0))
    assert_almost_equal(p[0], 20.0, atol=1e-5)
    assert_almost_equal(p[1], 3.0, atol=1e-5)
    # Road 5: the spiral's distance is the offset from its start, the
    # nearest here; the lengths before it are none.
    var q = map.road(RoadId(5)).nearest_point(Vector3(1, 101, 0))
    assert_almost_equal(q[0], 1.0, atol=1e-5)
    assert_almost_equal(q[1], 1.0, atol=1e-5)
    # The poly3's answer is its start, so a point there picks it and adds
    # the spiral's 20 m.
    var r = map.road(RoadId(5)).nearest_point(Vector3(1000, 1000, 0))
    assert_almost_equal(r[0], 20.0 + 20.0, atol=1e-5)
    var empty = Road(
        RoadId(9), "", 1.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    assert_equal(
        empty.nearest_point(Vector3(0, 0, 0))[1], 1.7976931348623157e308
    )
    # `GetNearestLane` measures in OpenDRIVE's frame: lane -1's center is
    # at y = -1.75 there.
    var n = map.road(RoadId(1)).nearest_lane(10.0, Vector3(10, -1.75, 0))
    assert_equal(n[0].value(), LaneKey(RoadId(1), SectionId(0), LaneId(-1)))
    assert_almost_equal(n[1], 0.0, atol=1e-5)
    n = map.road(RoadId(1)).nearest_lane(10.0, Vector3(10, 4.5, 0))
    assert_equal(n[0].value().lane_id, LaneId(2))
    n = map.road(RoadId(1)).nearest_lane(
        10.0, Vector3(10, 4.5, 0), LANE_DRIVING
    )
    assert_equal(n[0].value().lane_id, LaneId(1))
    n = map.road(RoadId(1)).nearest_lane(10.0, Vector3(10, 4.5, 0), LANE_TRAM)
    assert_false(n[0])
    var bare = Road(
        RoadId(1), "r", 10.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = bare.add_section(SectionId(0), 0.0)
    _ = bare.sections[0].add_lane(LaneId(-1))
    bare.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial.constant(0))
    )
    bare.info.geometries.append(
        RoadInfoGeometry(0.0, RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 10.0))
    )
    with assert_raises():
        _ = bare.nearest_lane(5.0, Vector3(0, 0, 0))


# --- the map's lookups ----------------------------------------------------


def test_waypoint_equality() raises:
    var a = _w(1, 0, -1, 10.0)
    assert_true(a == _w(1, 0, -1, 10.004))
    assert_false(a == _w(1, 0, -1, 10.006))
    assert_false(a == _w(2, 0, -1, 10.0))
    assert_false(a == _w(1, 1, -1, 10.0))
    assert_false(a == _w(1, 0, 1, 10.0))
    assert_equal(hash(a), hash(_w(1, 0, -1, 10.001)))
    assert_equal(
        String(a), "Waypoint(road_id=1, section_id=0, lane_id=-1, s=10.0)"
    )


def test_lookups() raises:
    var map = load_opendrive_file(TOWN)
    assert_true(map.contains_road(RoadId(5)))
    assert_false(map.contains_road(RoadId(4)))
    with assert_raises():
        _ = map.road_index(RoadId(-1))
    with assert_raises():
        _ = map.road_index(RoadId(4))
    with assert_raises():
        _ = map.lane(_w(1, 5, -1, 0.0))
    with assert_raises():
        _ = map.lane(_w(1, 0, -7, 0.0))
    assert_equal(map.lane(_w(1, 0, -2, 0.0)).type, LANE_SIDEWALK)
    assert_equal(map.junction_index(JuncId(5)), -1)
    with assert_raises():
        _ = map.junction(JuncId(1 << 40))
    with assert_raises():
        _ = map.junction(JuncId(5))
    with assert_raises():
        _ = map.signal(SignalId(""))
    with assert_raises():
        _ = map.signal(SignalId("nope"))
    with assert_raises():
        _ = map.controller(ControllerId(""))
    with assert_raises():
        _ = map.controller(ControllerId("nope"))
    assert_equal(map.lane_type(_w(1, 0, -1, 1.0)), LANE_DRIVING)
    assert_almost_equal(map.lane_width(_w(1, 1, -1, 50.0)).value, 4.0)
    assert_almost_equal(map.lane_width_meters(_w(1, 1, -1, 50.0)), 4.0)
    with assert_raises():
        _ = map.lane_width(_w(1, 1, -1, 61.0))
    with assert_raises():
        _ = map.lane_width_meters(_w(1, 1, -1, 61.0))
    assert_equal(map.junction_id(RoadId(11)), JuncId(100))
    assert_true(map.is_junction(RoadId(11)))
    assert_false(map.is_junction(RoadId(1)))
    assert_true(map.is_positive_direction(_w(1, 0, -1, 1.0)))
    assert_false(map.is_positive_direction(_w(1, 0, 1, 1.0)))
    # Before the first width record there is none.
    with assert_raises():
        _ = map.lane_width(_w(1, 0, -1, -1.0))
    with assert_raises():
        _ = map.lane_width_meters(_w(1, 0, -1, -1.0))


def test_mark_records() raises:
    var map = load_opendrive_file(TOWN)
    var zero = map.mark_record(_w(1, 0, 0, 5.0))
    assert_false(zero[0])
    assert_false(zero[1])
    var right = map.mark_record(_w(1, 0, -1, 5.0))
    assert_equal(right[0].value().type, "broken")
    assert_equal(right[1].value().color, "yellow")
    var left = map.mark_record(_w(1, 0, 1, 5.0))
    assert_equal(left[0].value().lane_change, MARK_CHANGE_BOTH)
    with assert_raises():
        _ = map.mark_record(_w(1, 0, -1, 61.0))
    # Road 7's lane -1 has no lane 0 inside it? It does; road 5's lane -3
    # sits outside -2, which has no mark.
    var outer = map.mark_record(_w(5, 0, -3, 5.0))
    assert_false(outer[0])
    assert_false(outer[1])
    var b = MapBuilder()
    _ = _flat_road(
        b, 1, 0, 0, 0, 10, -1, 0, 0, True, [(-2, LANE_DRIVING, 0, 0)]
    )
    var gap = b.build()
    with assert_raises():
        _ = gap.mark_record(_w(1, 0, -2, 1.0))


def test_lane_markings_and_change() raises:
    var map = load_opendrive_file(TOWN)
    var right = map.right_lane_marking(_w(1, 0, -1, 5.0)).value()
    assert_equal(right.type, BROKEN)
    assert_equal(right.color, MARKING_STANDARD)
    assert_equal(right.lane_change, CHANGE_RIGHT)
    var left = map.left_lane_marking(_w(1, 0, -1, 5.0)).value()
    assert_equal(left.type, SOLID)
    assert_equal(left.color, MARKING_YELLOW)
    assert_almost_equal(left.width, 0.3)
    # On a left-hand road the inner mark is on the right.
    var lh_right = map.right_lane_marking(_w(6, 0, 1, 5.0)).value()
    assert_equal(lh_right.color, MARKING_YELLOW)
    var lh_left = map.left_lane_marking(_w(6, 0, 1, 5.0)).value()
    assert_equal(lh_left.type, BROKEN)
    assert_false(map.right_lane_marking(_w(10, 0, -1, 5.0)))
    assert_false(map.left_lane_marking(_w(10, 0, -1, 5.0)))
    # `Waypoint::GetLaneChange`, worked from the marks by hand.
    assert_equal(map.lane_change(_w(1, 0, -1, 5.0)), CHANGE_RIGHT)
    assert_equal(map.lane_change(_w(1, 0, 1, 5.0)), CHANGE_RIGHT)
    assert_equal(map.lane_change(_w(1, 1, -1, 35.0)), CHANGE_NONE)
    assert_equal(map.lane_change(_w(1, 0, -2, 5.0)), CHANGE_BOTH)
    assert_equal(map.lane_change(_w(1, 1, -2, 35.0)), CHANGE_RIGHT)
    assert_equal(map.lane_change(_w(6, 0, 1, 5.0)), CHANGE_NONE)
    assert_equal(map.lane_change(_w(6, 0, -1, 5.0)), CHANGE_LEFT)
    assert_equal(map.lane_change(_w(6, 0, 2, 5.0)), CHANGE_BOTH)
    var green = map.left_lane_marking(_w(6, 0, -1, 5.0)).value()
    assert_equal(green.type, BOTTS_DOTS)
    assert_equal(green.color, MARKING_GREEN)
    var red = map.left_lane_marking(_w(6, 0, -2, 5.0)).value()
    assert_equal(red.type, GRASS)
    assert_equal(red.color, MARKING_RED)
    var blue = map.left_lane_marking(_w(6, 0, 2, 5.0)).value()
    assert_equal(blue.color, MARKING_BLUE)
    var curb = map.right_lane_marking(_w(1, 0, -2, 5.0)).value()
    assert_equal(curb.type, CURB)


# --- nearest waypoints ------------------------------------------------------


def test_closest_waypoints() raises:
    var map = load_opendrive_file(TOWN)
    assert_equal(map.segment_count(), 227)
    # Values from the Python copy of `GetClosestWaypointOnRoad`.
    _same(
        map.closest_waypoint_on_road(Vector3(20, 1, 0)).value(), 1, 0, -1, 20.0
    )
    _same(
        map.closest_waypoint_on_road(Vector3(70, 10, 0)).value(),
        11,
        0,
        -1,
        15.603252062536761,
    )
    _same(
        map.closest_waypoint_on_road(
            Vector3(10, 4.5, 0), LANE_SIDEWALK
        ).value(),
        1,
        0,
        -2,
        10.0,
    )
    _same(
        map.closest_waypoint_on_road(Vector3(-50, 1.75, 0)).value(),
        1,
        0,
        -1,
        0.0,
    )
    _same(
        map.closest_waypoint_on_road(Vector3(200, 1.75, 0)).value(),
        2,
        0,
        -1,
        39.999998999999995,
    )
    _same(
        map.closest_waypoint_on_road(Vector3(20, -1.75, 0)).value(),
        1,
        0,
        1,
        20.0,
    )
    _same(
        map.closest_waypoint_on_road(Vector3(-30, -1.75, 0)).value(),
        1,
        0,
        1,
        1.0e-6,
    )
    _same(
        map.closest_waypoint_on_road(
            Vector3(10, 105, 0), LANE_SHOULDER
        ).value(),
        5,
        0,
        -2,
        6.0,
    )
    assert_false(map.closest_waypoint_on_road(Vector3(0, 0, 0), LANE_TRAM))
    with assert_raises():
        _ = map.closest_waypoint_on_road(Vector3(0, 0, 0), LaneType(0))
    _same(map.waypoint(Vector3(20, 1, 0)).value(), 1, 0, -1, 20.0)
    assert_false(map.waypoint(Vector3(20, 4, 0)))
    assert_false(map.waypoint(Vector3(0, 0, 0), LANE_TRAM))
    # The first segment is road 1's sidewalk, whose center is not lifted.
    var seg = map.segment(0)
    _near(seg[0], 0.0, 4.5, 0.0)
    _near(seg[1], 30.0, 4.5, 0.0)
    _same(seg[2], 1, 0, -2, 0.0)
    with assert_raises():
        _ = map.segment(-1)
    with assert_raises():
        _ = map.segment(1000)


def test_waypoint_xodr() raises:
    var map = load_opendrive_file(TOWN)
    _same(
        map.waypoint_xodr(RoadId(1), LaneId(-1), _m(35)).value(), 1, 1, -1, 35.0
    )
    _same(
        map.waypoint_xodr(RoadId(1), LaneId(-1), _m(0)).value(), 1, 0, -1, 0.0
    )
    assert_false(map.waypoint_xodr(RoadId(4), LaneId(-1), _m(1)))
    assert_false(map.waypoint_xodr(RoadId(1), LaneId(-1), _m(-1)))
    assert_false(map.waypoint_xodr(RoadId(1), LaneId(-1), _m(60)))
    assert_false(map.waypoint_xodr(RoadId(1), LaneId(-9), _m(1)))
    with assert_raises():
        _ = map.waypoint_xodr(RoadId(-1), LaneId(-1), _m(1))
    with assert_raises():
        _ = map.waypoint_xodr(RoadId(1), LaneId(1 << 40), _m(1))


# --- walking --------------------------------------------------------------------


def test_successors_and_next() raises:
    var map = load_opendrive_file(TOWN)
    var s = map.successors(_w(1, 1, -1, 40.0))
    assert_equal(len(s), 3)
    _same(s[0], 10, 0, -1, 0.0)
    _same(s[1], 11, 0, -1, 0.0)
    # Two connections name road 10, so road 1 leads there twice.
    var p = map.predecessors(_w(10, 0, -1, 5.0))
    assert_equal(len(p), 2)
    _same(p[0], 1, 1, -1, 60.0)
    # Lane 0 is left out of both.
    assert_equal(len(map.successors(_w(1, 0, 0, 5.0))), 0)
    assert_equal(len(map.predecessors(_w(1, 1, 0, 35.0))), 0)
    var n = map.next(_w(1, 1, -1, 40.0), 35.0)
    assert_equal(len(n), 3)
    _same(n[0], 10, 0, -1, 15.0)
    _same(n[1], 11, 0, -1, 15.0)
    var within = map.next(_w(1, 0, -1, 5.0), 2.0)
    _same(within[0], 1, 0, -1, 7.0)
    var back = map.previous(_w(2, 0, -1, 5.0), 10.0)
    assert_equal(len(back), 1)
    _same(back[0], 10, 0, -1, 25.0)
    # A lane that runs against s steps the other way.
    _same(map.next(_w(1, 1, 1, 50.0), 5.0)[0], 1, 1, 1, 45.0)
    _same(map.previous(_w(1, 1, 1, 50.0), 5.0)[0], 1, 1, 1, 55.0)
    # A step no longer than EPSILON gives the waypoint back.
    _same(map.next(_w(1, 0, -1, 5.0), 1e-16)[0], 1, 0, -1, 5.0)
    with assert_raises():
        _ = map.next(_w(1, 0, -1, 5.0), 0.0)
    with assert_raises():
        _ = map.next(_w(1, 0, -1, -5.0), 1.0)
    # A dead end gives nothing.
    assert_equal(len(map.next(_w(2, 0, -1, 30.0), 20.0)), 0)


def test_next_skips_loops() raises:
    # Road 1's lane -1 leads to road 2's lane 1, which leads back to it:
    # CARLA's `is_broken` guard drops that successor.
    var b = MapBuilder()
    _ = _flat_road(
        b, 1, 0, 0, 0, 10, -1, 0, 2, True, [(-1, LANE_DRIVING, 0, 1)]
    )
    _ = _flat_road(
        b, 2, 10, 0, 0, 10, -1, 1, 0, True, [(1, LANE_DRIVING, -1, 0)]
    )
    var map = b.build()
    assert_equal(len(map.successors(_w(1, 0, -1, 5.0))), 1)
    assert_equal(len(map.next(_w(1, 0, -1, 5.0), 20.0)), 0)
    assert_equal(len(map.previous(_w(2, 0, 1, 5.0), 20.0)), 0)


def test_right_and_left() raises:
    var map = load_opendrive_file(TOWN)
    _same(map.right(_w(1, 0, -1, 5.0)).value(), 1, 0, -2, 5.0)
    _same(map.right(_w(1, 0, 1, 5.0)).value(), 1, 0, 2, 5.0)
    _same(map.left(_w(1, 0, -1, 5.0)).value(), 1, 0, 1, 5.0)
    _same(map.left(_w(1, 0, 2, 5.0)).value(), 1, 0, 1, 5.0)
    _same(map.left(_w(1, 0, -2, 5.0)).value(), 1, 0, -1, 5.0)
    assert_false(map.right(_w(1, 0, -2, 5.0)))
    # Left-hand: right is inward.
    _same(map.right(_w(6, 0, 1, 5.0)).value(), 6, 0, -1, 5.0)
    _same(map.right(_w(6, 0, 2, 5.0)).value(), 6, 0, 1, 5.0)
    _same(map.right(_w(6, 0, -2, 5.0)).value(), 6, 0, -1, 5.0)
    _same(map.left(_w(6, 0, 1, 5.0)).value(), 6, 0, 2, 5.0)
    _same(map.left(_w(6, 0, -1, 5.0)).value(), 6, 0, -2, 5.0)
    assert_false(map.left(_w(6, 0, 2, 5.0)))
    with assert_raises():
        _ = map.right(_w(1, 0, 0, 5.0))
    with assert_raises():
        _ = map.left(_w(1, 0, 0, 5.0))


def test_until_lane_end() raises:
    var map = load_opendrive_file(TOWN)
    var ahead = map.next_until_lane_end(_w(1, 0, -1, 1.0), 7.0)
    assert_equal(len(ahead), 9)
    _same(ahead[3], 1, 0, -1, 29.0)
    _same(ahead[4], 1, 1, -1, 36.0)
    _same(ahead[8], 1, 1, -1, 60.0)
    var expected = [8.0, 15.0, 22.0, 29.0, 36.0, 43.0, 50.0, 57.0, 60.0]
    for i in range(len(expected)):
        _same(ahead[i], 1, 0 if i < 4 else 1, -1, expected[i])
    var back = map.next_until_lane_end(_w(2, 0, 1, 39.0), 15.0)
    assert_equal(len(back), 3)
    _same(back[2], 2, 0, 1, 0.0)
    var prev = map.previous_until_lane_start(_w(10, 0, -1, 20.0), 5.0)
    assert_equal(len(prev), 4)
    _same(prev[3], 10, 0, -1, 0.0)
    # The remainder follows the backward direction on an isolated end.
    var isolated = map.previous_until_lane_start(_w(1, 1, -1, 50.0), 4.0)
    assert_equal(len(isolated), 13)
    _same(isolated[12], 1, 0, -1, 0.0)


def test_generation() raises:
    var map = load_opendrive_file(TOWN)
    var all = map.generate_waypoints(10.0)
    assert_equal(len(all), 50)
    _same(all[0], 1, 0, -1, 0.0)
    _same(all[49], 11, 0, -1, 30.0)
    with assert_raises():
        _ = map.generate_waypoints(0.0)
    var entries = map.generate_waypoints_on_road_entries()
    assert_equal(len(entries), 13)
    _same(entries[1], 1, 1, 1, 60.0)
    _same(entries[7], 6, 0, 1, 0.0)
    with assert_raises():
        _ = map.generate_waypoints_on_road_entries(LaneType(0))
    var one = map.generate_waypoints_in_road(RoadId(1))
    assert_equal(len(one), 2)
    var walks = map.generate_waypoints_in_road(RoadId(1), LANE_SIDEWALK)
    assert_equal(len(walks), 2)
    _same(walks[0], 1, 0, -2, 0.0)
    _same(walks[1], 1, 1, 2, 60.0)
    assert_equal(len(map.generate_waypoints_in_road(RoadId(4))), 0)
    with assert_raises():
        _ = map.generate_waypoints_in_road(RoadId(-4))
    with assert_raises():
        _ = map.generate_waypoints_in_road(RoadId(1), LaneType(0))


def test_topology() raises:
    var map = load_opendrive_file(TOWN)
    var topology = map.generate_topology()
    assert_equal(len(topology), 18)
    # The five previously dropped increasing-s dead ends are road 2/-1,
    # 3/-1, 5/-1, 6/+1 (LHT) and 7/-1. Their XML lengths give each end.
    # The 13 existing pairs retain their relative order.
    _same(topology[6][0], 2, 0, -1, 0.0)
    _same(topology[6][1], 2, 0, -1, 40.0)
    _same(topology[9][0], 3, 0, -1, 0.0)
    _same(topology[9][1], 3, 0, -1, 30.0)
    _same(topology[10][0], 5, 0, -1, 0.0)
    _same(topology[10][1], 5, 0, -1, 57.0)
    _same(topology[13][0], 6, 0, 1, 0.0)
    _same(topology[13][1], 6, 0, 1, 20.0)
    _same(topology[14][0], 7, 0, -1, 0.0)
    _same(topology[14][1], 7, 0, -1, 10.0)
    _same(topology[0][0], 1, 0, -1, 0.0)
    _same(topology[0][1], 1, 1, -1, 30.0)
    _same(topology[1][0], 1, 0, 1, 30.0)
    _same(topology[1][1], 1, 0, 1, 0.0)
    _same(topology[11][0], 5, 0, 1, 57.0)
    _same(topology[11][1], 5, 0, 1, 0.0)
    _same(topology[17][1], 3, 0, -1, 0.0)


def test_junctions() raises:
    var map = load_opendrive_file(TOWN)
    var pairs = map.junction_waypoints(JuncId(100), LANE_ANY)
    assert_equal(len(pairs), 6)
    _same(pairs[2][0], 11, 0, -2, 0.0)
    _same(pairs[2][1], 11, 0, -2, 31.415926535898)
    _same(pairs[1][1], 10, 0, 1, 0.0)
    assert_equal(len(map.junction_waypoints(JuncId(100), LANE_DRIVING)), 5)
    with assert_raises():
        _ = map.junction_waypoints(JuncId(100), LaneType(0))
    with assert_raises():
        _ = map.junction_waypoints(JuncId(3), LANE_ANY)
    ref junction = map.junction(JuncId(100))
    # From the Python copy of `CreateJunctionBoundingBoxes`.
    _near(junction.bounding_box.min, 60.0, -1.75, 0.0)
    _near(junction.bounding_box.max, 90.0, 20.0, 0.0)
    _near(junction.location(), 75.0, 9.125, 0.0)
    _near(junction.extent(), 15.0, 10.875, 0.0)
    assert_true(junction.road_has_conflicts(RoadId(10)))
    assert_false(junction.road_has_conflicts(RoadId(1)))
    var conflicts = junction.conflicts_of_road(RoadId(11))
    assert_equal(len(conflicts), 1)
    assert_equal(conflicts[0], RoadId(10))
    with assert_raises():
        _ = junction.conflicts_of_road(RoadId(1))
    assert_equal(junction.connection_index(ConId(2)), 2)
    assert_equal(junction.connection_index(ConId(9)), -1)
    with assert_raises():
        _ = Junction(JuncId(1 << 40), "")
    with assert_raises():
        _ = Connection(ConId(-1), RoadId(1), RoadId(2))
    with assert_raises():
        _ = Connection(ConId(1), RoadId(-1), RoadId(2))
    with assert_raises():
        _ = Connection(ConId(1), RoadId(1), RoadId(-2))


def test_segment_distance() raises:
    var o = Vector3(0, 0, 0)
    assert_equal(
        segment_distance_2d(
            o, Vector3(2, 2, 0), Vector3(0, 2, 0), Vector3(2, 0, 0)
        ),
        0.0,
    )
    assert_almost_equal(
        segment_distance_2d(
            o, Vector3(2, 0, 0), Vector3(1, 3, 0), Vector3(1, 1, 0)
        ),
        1.0,
    )
    assert_almost_equal(
        segment_distance_2d(
            o, Vector3(2, 0, 0), Vector3(5, 0, 0), Vector3(6, 0, 0)
        ),
        3.0,
    )
    # Parallel: one crossing test fails and the ends decide.
    assert_almost_equal(
        segment_distance_2d(
            o, Vector3(2, 0, 0), Vector3(0, 1, 0), Vector3(2, 1, 0)
        ),
        1.0,
    )
    # One segment crosses the other's line but not the segment.
    assert_almost_equal(
        segment_distance_2d(
            o, Vector3(1, 0, 0), Vector3(2, -1, 0), Vector3(2, 1, 0)
        ),
        1.0,
    )
    # A segment of no length.
    assert_almost_equal(
        segment_distance_2d(o, o, Vector3(3, 4, 0), Vector3(3, 4, 0)), 5.0
    )


# --- signals ------------------------------------------------------------------


def test_signal_transforms() raises:
    var map = load_opendrive_file(TOWN)
    # A light stands a quarter meter ahead of its place.
    _near(map.signal(SignalId("1001")).transform.location, 55.25, 8.0, 3.0)
    ref stop = map.signal(SignalId("1002")).transform
    _near(stop.location, 50.0, 9.0, 1.5)
    assert_almost_equal(stop.rotation.yaw, -5.729577951308232, atol=1e-4)
    ref inertial = map.signal(SignalId("1003")).transform
    _near(inertial.location, 100.0, -6.0, 2.0)
    assert_almost_equal(inertial.rotation.yaw, -180.0, atol=1e-4)
    # The limit sign stood on lane -1, 2 m up: it moved right three steps
    # of 0.7 m, to 2.1 m right of the lane's center, and turned with the
    # lane.
    _near(map.signal(SignalId("1004")).transform.location, 25.0, 3.85, 2.0)
    # The stencil stays where it is.
    _near(map.signal(SignalId("2003")).transform.location, 45.0, 1.75, 0.0)
    assert_true(is_traffic_light("F"))
    assert_true(is_traffic_light("1000012"))
    assert_false(is_traffic_light(SIGNAL_STOP))
    assert_equal(SIGNAL_MAXIMUM_SPEED, "274")
    with assert_raises():
        _ = Signal(
            RoadId(-1),
            SignalId("a"),
            0,
            0,
            "",
            "",
            "",
            0,
            "",
            "",
            "",
            0,
            "",
            0,
            0,
            "",
            0,
            0,
            0,
        )
    with assert_raises():
        _ = Signal(
            RoadId(1),
            SignalId(""),
            0,
            0,
            "",
            "",
            "",
            0,
            "",
            "",
            "",
            0,
            "",
            0,
            0,
            "",
            0,
            0,
            0,
        )
    with assert_raises():
        _ = Controller(ControllerId(""), "", 0)
    var obj = RoadObject()
    assert_equal(obj.id, 0)
    assert_equal(obj.name, "")
    assert_equal(obj.length, 0.0)
    assert_equal(
        map.signal(SignalId("1002")).orientation(), ORIENTATION_NEGATIVE
    )


def test_signals_in_distance() raises:
    var map = load_opendrive_file(TOWN)
    # From the Python copy of `GetSignalsInDistance`: the longer list of
    # the successor comes first.
    # Road 2's yield sign comes twice: two connections lead there.
    var found = map.signals_in_distance(_w(1, 0, -1, 1.0), 100.0)
    assert_equal(len(found), 6)
    assert_equal(found[0].signal.signal_id, SignalId("1002"))
    _same(found[0].waypoint, 1, 1, -1, 50.0)
    assert_almost_equal(found[0].accumulated_s, 49.0, atol=1e-9)
    assert_equal(found[3].signal.signal_id, SignalId("1003"))
    _same(found[3].waypoint, 2, 0, -1, 10.0)
    assert_almost_equal(found[3].accumulated_s, 99.0, atol=1e-9)
    assert_equal(found[5].signal.signal_id, SignalId("1004"))
    assert_almost_equal(found[5].accumulated_s, 24.0, atol=1e-9)
    var back = map.signals_in_distance(_w(1, 1, 1, 59.0), 100.0)
    assert_equal(len(back), 4)
    assert_equal(back[1].signal.signal_id, SignalId("2003"))
    assert_almost_equal(back[3].accumulated_s, 54.0, atol=1e-9)
    var stop = map.signals_in_distance(_w(1, 1, -1, 40.0), 100.0, True)
    assert_equal(len(stop), 3)
    var into = map.signals_in_distance(_w(1, 1, -1, 40.0), 100.0)
    assert_equal(len(into), 5)
    # A signal right at the start comes with the start waypoint.
    var here = map.signals_in_distance(_w(1, 1, -1, 50.0), 1.0)
    assert_equal(len(here), 1)
    assert_equal(here[0].accumulated_s, 0.0)
    assert_equal(len(map.all_signal_references()), 8)


def test_landmarks() raises:
    var map = load_opendrive_file(TOWN)
    var marks = map.landmarks_in_distance(_w(1, 0, -1, 1.0), 100.0)
    # 1002 has two references, at 50 and 58; 1003's one reference is
    # found twice and kept once.
    assert_equal(len(marks), 5)
    var typed = map.landmarks_of_type_in_distance(
        _w(1, 0, -1, 1.0), 100.0, "206"
    )
    assert_equal(len(typed), 2)
    var all = map.all_landmarks()
    assert_equal(len(all), 8)
    assert_false(all[0].waypoint)
    assert_equal(len(map.landmarks_from_id(SignalId("1002"))), 2)
    with assert_raises():
        _ = map.landmarks_from_id(SignalId(""))
    assert_equal(len(map.all_landmarks_of_type("274")), 3)
    var group = map.landmark_group(all[5])
    assert_equal(len(group), 1)
    assert_equal(group[0].reference.signal_id, SignalId("1001"))
    assert_equal(len(map.landmark_group(all[0])), 0)
    # A controller that names a missing signal fails the group.
    var b = MapBuilder()
    var r = _flat_road(
        b, 1, 0, 0, 0, 10, -1, 0, 0, True, [(-1, LANE_DRIVING, 0, 0)]
    )
    _ = b.add_signal(
        r,
        SignalId("s"),
        1,
        -5,
        "",
        "",
        "+",
        0,
        "",
        "",
        "",
        0,
        "",
        0,
        0,
        "",
        0,
        0,
        0,
    )
    b.add_junction(JuncId(1), "j")
    b.add_junction_controller(JuncId(1), [ControllerId("c")])
    b.create_controller(
        ControllerId("c"), "c", 0, [SignalId("s"), SignalId("x")]
    )
    var small = b.build()
    var lone = small.all_landmarks()
    assert_equal(len(small.signal(SignalId("s")).controllers), 1)
    with assert_raises():
        _ = small.landmark_group(lone[0])


def test_crossed_lanes() raises:
    var map = load_opendrive_file(TOWN)
    # Worked from the file: lane -1 to lane 1 crosses lane 0's yellow.
    var across = map.calculate_crossed_lanes(
        Vector3(10, 1.75, 0), Vector3(10, -1.75, 0)
    )
    assert_equal(len(across), 1)
    assert_equal(across[0].color, MARKING_YELLOW)
    # Off the road to the right, over lane -1's own broken mark.
    var out = map.calculate_crossed_lanes(
        Vector3(10, 1.75, 0), Vector3(10, 4.5, 0)
    )
    assert_equal(out[0].type, BROKEN)
    # From off the road back onto it: the destination's outer mark.
    var back = map.calculate_crossed_lanes(
        Vector3(10, 4.5, 0), Vector3(10, 1.75, 0)
    )
    assert_equal(back[0].type, BROKEN)
    # From off a left-hand road, to the right, onto its lane 1.
    var lh = map.calculate_crossed_lanes(
        Vector3(10, -208, 0), Vector3(10, -201.75, 0)
    )
    assert_equal(lh[0].color, MARKING_YELLOW)
    # Within one lane, off the road at both ends, across sections, on a
    # junction, and between roads: nothing.
    assert_equal(
        len(map.calculate_crossed_lanes(Vector3(10, 1, 0), Vector3(12, 2, 0))),
        0,
    )
    assert_equal(
        len(map.calculate_crossed_lanes(Vector3(10, 8, 0), Vector3(10, 9, 0))),
        0,
    )
    assert_equal(
        len(
            map.calculate_crossed_lanes(
                Vector3(10, 1.75, 0), Vector3(40, 1.75, 0)
            )
        ),
        0,
    )
    assert_equal(
        len(
            map.calculate_crossed_lanes(
                Vector3(70, 1.75, 0), Vector3(70, -1.75, 0)
            )
        ),
        0,
    )
    assert_equal(
        len(
            map.calculate_crossed_lanes(
                Vector3(10, 1.75, 0), Vector3(100, 1.75, 0)
            )
        ),
        0,
    )
    # A mark that is not there crosses nothing.
    assert_equal(
        len(
            map.calculate_crossed_lanes(
                Vector3(100, 1.75, 0), Vector3(100, -1.75, 0)
            )
        ),
        0,
    )
    var b = MapBuilder()
    _ = _flat_road(
        b, 1, 0, 0, 0, 10, -1, 0, 0, True, [(-1, LANE_SIDEWALK, 0, 0)]
    )
    var walk = b.build()
    assert_equal(
        len(walk.calculate_crossed_lanes(Vector3(1, 1, 0), Vector3(2, 1, 0))), 0
    )


def test_crosswalk_zones() raises:
    var map = load_opendrive_file(TOWN)
    var zones = map.all_crosswalk_zones()
    assert_equal(len(zones), 10)
    # Worked by hand: the pivot faces -90 degrees at x = 10, and each u is
    # widened by a meter.
    _near(zones[0], 8.5, 6.0, 0.0)
    _near(zones[1], 8.5, -6.0, 0.0)
    _near(zones[2], 11.5, -6.0, 0.0)
    _near(zones[4], 8.5, 6.0, 0.0)
    _near(zones[5], 38.5, 6.0, 0.0)


def test_deformation() raises:
    # CARLA's float formulas, evaluated in Python in single precision.
    assert_almost_equal(
        z_pos_in_deformation(_m(10), _m(20)).value,
        0.11939060688018799,
        atol=1e-5,
    )
    # A bump near its grid point, and none far from it.
    assert_almost_equal(
        bump_deformation(_m(16.5), _m(12.3)).value,
        0.05506104230880737,
        atol=1e-6,
    )
    assert_almost_equal(bump_deformation(_m(40.2), _m(30.1)).value, 0.0)
    assert_almost_equal(
        map_deformation(_m(16.5), _m(12.3)).value,
        0.864414632320404 + 0.05506104230880737,
        atol=1e-5,
    )


# --- the builder ------------------------------------------------------------


def _bare_road(
    mut b: MapBuilder,
    id: Int,
    y: Float64,
    length: Float64,
    junction: Int,
    predecessor: Int,
    successor: Int,
) raises -> Int:
    # A flat, straight road along x with its records and no sections.
    var r = b.add_road(
        RoadId(id),
        "bare",
        length,
        JuncId(junction),
        RoadId(predecessor),
        RoadId(successor),
        True,
    )
    b.create_section_offset(r, 0.0, 0, 0, 0, 0)
    b.add_road_elevation_profile(r, 0.0, 0, 0, 0, 0)
    b.add_road_geometry_line(r, 0.0, 0.0, y, 0.0, length)
    return r


def _sign(
    mut b: MapBuilder, road: Int, id: String, s: Float64, t: Float64
) raises:
    _ = b.add_signal(
        road,
        SignalId(id),
        s,
        t,
        "",
        "",
        "+",
        0,
        "",
        "274",
        "",
        0,
        "",
        0,
        0,
        "",
        0,
        0,
        0,
    )


def test_empty_map() raises:
    var b = MapBuilder()
    var empty = b.build()
    assert_equal(empty.junction_index(JuncId(1)), -1)
    with assert_raises():
        _ = empty.signal(SignalId("s"))
    with assert_raises():
        _ = empty.controller(ControllerId("c"))
    assert_equal(len(empty.generate_waypoints(1.0)), 0)
    assert_equal(len(empty.generate_waypoints_on_road_entries()), 0)
    assert_equal(len(empty.generate_topology()), 0)
    assert_equal(len(empty.all_crosswalk_zones()), 0)
    assert_equal(len(empty.all_signal_references()), 0)
    assert_equal(len(empty.all_landmarks()), 0)
    assert_equal(len(empty.landmarks_from_id(SignalId("s"))), 0)
    assert_equal(len(empty.all_landmarks_of_type("274")), 0)
    with assert_raises():
        _ = MapBuilder().road_index(RoadId(1))
    with assert_raises():
        b.add_junction_controller(JuncId(1), List[ControllerId]())
    assert_equal(len(default_validities(ORIENTATION_BOTH, List[LaneId]())), 0)


def test_map_of_odd_roads() raises:
    var b = MapBuilder()
    # Road 1 has one section, from s = 5, and leads into junction 7.
    var r1 = _bare_road(b, 1, 0.0, 10.0, -1, 0, 7)
    var sec = b.add_road_section(r1, SectionId(0), 5.0)
    for id in [-1, 0]:
        _ = b.add_road_section_lane(
            r1,
            sec,
            LaneId(id),
            LANE_NONE if id == 0 else LANE_DRIVING,
            False,
            LaneId(0),
            LaneId(id),
        )
        b.create_lane_width(
            b.lane(RoadId(1), LaneId(id), 5.0),
            5.0,
            0.0 if id == 0 else 3.5,
            0,
            0,
            0,
        )
    # A sign and a crosswalk before the first section.
    _sign(b, r1, "s", 1.0, 5.0)
    b.add_road_object_crosswalk(
        r1,
        "cw",
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        "+",
        2.0,
        4.0,
        [CrosswalkPoint(-1.5, 1.0, 0.0), CrosswalkPoint(1.5, 1.0, 0.0)],
    )
    # Junction 7 holds road 2, with no sections, and road 3, with a
    # section that has no lanes.
    _ = _bare_road(b, 2, 50.0, 10.0, 7, 1, 0)
    var r3 = _bare_road(b, 3, 60.0, 10.0, 7, 0, 1)
    _ = b.add_road_section(r3, SectionId(0), 0.0)
    b.add_road_object_crosswalk(
        r3,
        "bare",
        2.5,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        "+",
        2.0,
        4.0,
        List[CrosswalkPoint](),
    )
    b.add_junction(JuncId(7), "j")
    b.add_connection(JuncId(7), ConId(0), RoadId(1), RoadId(2))
    b.add_connection(JuncId(7), ConId(1), RoadId(1), RoadId(3))
    b.add_junction_controller(JuncId(7), [ControllerId("c")])
    # Road 4 leads into junction 8, which connects nothing.
    _ = _flat_road(
        b, 4, 0, 90, 0, 10, -1, 0, 8, True, [(-1, LANE_DRIVING, 0, -1)]
    )
    b.add_junction(JuncId(8), "k")
    var map = b.build()
    # The reference before the first section faces no lane.
    assert_equal(len(map.road(RoadId(1)).info.signals[0].validities), 0)
    assert_equal(len(map.successors(_w(1, 0, -1, 7.5))), 0)
    assert_equal(len(map.successors(_w(4, 0, -1, 7.5))), 0)
    # Waypoints start where the section does.
    var all = map.generate_waypoints(2.0)
    assert_equal(len(all), 7)
    _same(all[0], 1, 0, -1, 6.0)
    _same(all[2], 4, 0, -1, 0.0)
    var entries = map.generate_waypoints_on_road_entries()
    assert_equal(len(entries), 1)
    assert_equal(entries[0].road_id, RoadId(4))
    # Both dead-end lanes retain their own full-precision endpoint.
    var topology = map.generate_topology()
    assert_equal(len(topology), 2)
    _same(topology[0][0], 1, 0, -1, 5.0)
    _same(topology[0][1], 1, 0, -1, 10.0)
    _same(topology[1][0], 4, 0, -1, 0.0)
    _same(topology[1][1], 4, 0, -1, 10.0)
    assert_false(map.waypoint_xodr(RoadId(2), LaneId(-1), _m(2.5)))
    assert_equal(len(map.junction_waypoints(JuncId(7), LANE_ANY)), 0)
    # The crosswalk before the section stands at the origin, each corner
    # a meter wider; the one with no outline adds no corners.
    var zones = map.all_crosswalk_zones()
    assert_equal(len(zones), 2)
    _near(zones[0], -2.5, 1.0, 0.0, 1e-5)
    _near(zones[1], 2.5, 1.0, 0.0, 1e-5)


def test_controllers_out_of_order() raises:
    var b = MapBuilder()
    b.add_junction(JuncId(200), "b")
    b.add_junction(JuncId(100), "a")
    b.add_junction_controller(JuncId(200), List[ControllerId]())
    b.add_junction_controller(
        JuncId(100), [ControllerId("b"), ControllerId("a")]
    )
    b.create_controller(
        ControllerId("b"), "b", 0, [SignalId("z"), SignalId("y")]
    )
    b.create_controller(ControllerId("a"), "a", 0, List[SignalId]())
    var map = b.build()
    assert_equal(map.junctions[0].id, JuncId(100))
    assert_equal(map.controllers[0].id, ControllerId("a"))
    ref second = map.controller(ControllerId("b"))
    assert_equal(second.signals[0], SignalId("y"))
    assert_equal(second.signals[1], SignalId("z"))
    assert_equal(len(second.junctions), 1)
    assert_equal(map.junction(JuncId(100)).controllers[0], ControllerId("a"))
    # A junction with no roads has no conflicts.
    assert_false(map.junction(JuncId(200)).road_has_conflicts(RoadId(1)))
    with assert_raises():
        _ = map.junction(JuncId(200)).conflicts_of_road(RoadId(1))


def test_signal_on_a_missing_road() raises:
    var b = MapBuilder()
    var r = _flat_road(
        b, 1, 0, 0, 0, 10, -1, 0, 0, True, [(-1, LANE_DRIVING, 0, 0)]
    )
    _sign(b, r, "s", 5.0, 0.0)
    b.add_signal_position_road(SignalId("s"), RoadId(9), 5, 0, 0, 0, 0, 0)
    with assert_raises():
        _ = b.build()


def test_sign_with_no_right_lane() raises:
    # The sign stands on lane -1, the right lane of the road. There is no
    # lane to its right, so it steps right until it is 0.7 lane widths
    # off: four steps of 0.7 meters.
    var b = MapBuilder()
    var r = _flat_road(
        b,
        1,
        0,
        0,
        0,
        30,
        -1,
        0,
        0,
        True,
        [
            (-1, LANE_DRIVING, 0, 0),
            (0, LANE_NONE, 0, 0),
            (1, LANE_SIDEWALK, 0, 0),
        ],
    )
    _sign(b, r, "s", 10.0, -1.75)
    var map = b.build()
    _near(map.signal(SignalId("s")).transform.location, 10.0, 4.55, 0.0)


def test_three_roads_cross() raises:
    # Three junction roads cross at (10, 0): each conflicts with the
    # other two.
    var b = MapBuilder()
    var lanes: List[Tuple[Int, LaneType, Int, Int]] = [(-1, LANE_DRIVING, 0, 0)]
    _ = _flat_road(b, 10, 0, 0, 0, 20, 100, 0, 0, True, lanes)
    _ = _flat_road(
        b, 11, 10, -10, 1.5707963267948966, 20, 100, 0, 0, True, lanes
    )
    _ = _flat_road(
        b,
        12,
        0,
        -10,
        0.7853981633974483,
        28.284271247461902,
        100,
        0,
        0,
        True,
        lanes,
    )
    # A fourth road crosses the same box but is not in this junction.
    # It must not enter either side of a reported conflict pair.
    _ = _flat_road(b, 13, 0, 0, 0, 20, -1, 0, 0, True, lanes)
    b.add_junction(JuncId(100), "x")
    for i in range(3):
        b.add_connection(JuncId(100), ConId(i), RoadId(0), RoadId(10 + i))
    var map = b.build()
    var found = map.compute_junction_conflicts(JuncId(100))
    assert_equal(len(found[0]), 3)
    for i in range(3):
        assert_equal(len(found[1][i]), 2)


def test_tiny_straight_section() raises:
    # A straight section shorter than two micrometers gets no segment.
    var b = MapBuilder()
    var r = _flat_road(
        b, 1, 0, 0, 0, 20, -1, 0, 0, True, [(-1, LANE_DRIVING, 0, 0)]
    )
    var starts: List[Float64] = [10.0, 10.0000005]
    for i in range(2):
        var sec = b.add_road_section(r, SectionId(i + 1), starts[i])
        _ = b.add_road_section_lane(
            r, sec, LaneId(-1), LANE_DRIVING, False, LaneId(0), LaneId(0)
        )
        b.create_lane_width(
            b.lane(RoadId(1), LaneId(-1), starts[i]), starts[i], 3.5, 0, 0, 0
        )
    var map = b.build()
    assert_equal(map.segment_count(), 2)


def test_junction_box_of_a_long_road() raises:
    # On a road this long the tenth step of the box overshoots the lane's
    # end by rounding and finds no waypoint; the box keeps the ninth.
    var b = MapBuilder()
    _ = _flat_road(
        b, 20, 0, 0, 0, 733.3, 9, 0, 0, True, [(-1, LANE_DRIVING, 0, 0)]
    )
    b.add_junction(JuncId(9), "long")
    b.add_connection(JuncId(9), ConId(0), RoadId(0), RoadId(20))
    var map = b.build()
    var box = map.junction(JuncId(9)).bounding_box
    _near(box.min, 0.0, 1.75, 0.0, 1e-3)
    _near(box.max, 733.3, 1.75, 0.0, 1e-3)


def test_town_edges() raises:
    var map = load_opendrive_file(TOWN)
    # The first step leaves road 10, so the walk to the lane's end is one
    # step to it.
    var ends = map.next_until_lane_end(_w(10, 0, -1, 29.0), 5.0)
    assert_equal(len(ends), 1)
    _same(ends[0], 10, 0, -1, 30.0)
    # Road 10 has no marks, so a vehicle may change either way.
    assert_equal(map.lane_change(_w(10, 0, -1, 5.0)), CHANGE_BOTH)
    # Road 3 has no signals.
    assert_equal(len(map.landmarks_in_distance(_w(3, 0, -1, 5.0), 5.0)), 0)
    assert_equal(
        len(map.landmarks_of_type_in_distance(_w(3, 0, -1, 5.0), 5.0, "274")),
        0,
    )
    # A reference that faces no lane is never found.
    var r = map.road_index(RoadId(1))
    for k in range(len(map.roads[r].info.signals)):
        map.roads[r].info.signals[k].validities = List[LaneValidity]()
    assert_equal(len(map.signals_in_distance(_w(1, 0, -1, 15.0), 8.0)), 0)


def test_default_validities() raises:
    var lanes: List[LaneId] = [LaneId(-2), LaneId(-1), LaneId(0), LaneId(1)]
    var plus = default_validities(ORIENTATION_POSITIVE, lanes)
    assert_equal(len(plus), 1)
    assert_equal(plus[0], LaneValidity(LaneId(1), LaneId(1)))
    var minus = default_validities(ORIENTATION_NEGATIVE, lanes)
    assert_equal(minus[0], LaneValidity(LaneId(-2), LaneId(-1)))
    assert_equal(len(default_validities(ORIENTATION_BOTH, lanes)), 2)
    var right_only: List[LaneId] = [LaneId(-1), LaneId(0)]
    assert_equal(len(default_validities(ORIENTATION_POSITIVE, right_only)), 0)
    var left_only: List[LaneId] = [LaneId(0), LaneId(2)]
    assert_equal(len(default_validities(ORIENTATION_NEGATIVE, left_only)), 0)
    with assert_raises():
        _ = default_validities(SignalOrientation(5), lanes)


def test_builder_edges() raises:
    var b = MapBuilder()
    var r = _flat_road(
        b, 1, 0, 0, 0, 10, -1, 0, 0, True, [(-1, LANE_DRIVING, 0, 0)]
    )
    # A second road with the same id resets the fields.
    assert_equal(
        b.add_road(
            RoadId(1), "again", 12.0, JuncId(3), RoadId(0), RoadId(0), False
        ),
        r,
    )
    assert_equal(b.roads[r].name, "again")
    assert_true(b.roads[r].is_junction)
    with assert_raises():
        _ = b.road_index(RoadId(8))
    with assert_raises():
        _ = b.add_road_section_lane(
            r, 0, LaneId(-2), LaneType(0), False, LaneId(0), LaneId(0)
        )
    with assert_raises():
        _ = b.add_road_section_lane(
            r, 0, LaneId(-2), LANE_DRIVING, False, LaneId(1 << 40), LaneId(0)
        )
    with assert_raises():
        _ = b.add_road_section_lane(
            r, 0, LaneId(-2), LANE_DRIVING, False, LaneId(0), LaneId(1 << 40)
        )
    var lane = b.lane(RoadId(1), LaneId(-1), 0.0)
    b.create_road_mark_type_line(lane, 5, 1, 1, 0, 0, "", 0.1)
    assert_equal(len(b.roads[r].sections[0].lanes[0].info.marks), 0)
    b.create_road_mark(
        lane, 0, 0.0, "solid", "", "white", "", 0.1, "", 0, "", 0, True
    )
    b.create_road_mark(
        lane, 1, 0.0, "solid", "", "white", "", 0.1, "", 0, "", 0, True
    )
    b.create_road_mark_type_line(lane, 1, 1, 1, 0, 0, "", 0.1)
    assert_equal(len(b.roads[r].sections[0].lanes[0].info.marks[1].lines), 1)
    assert_equal(len(b.roads[r].sections[0].lanes[0].info.marks[0].lines), 0)
    with assert_raises():
        _ = b.add_signal_reference(r, SignalId("x"), -1.0, 0.0, "+")
    with assert_raises():
        _ = b.add_signal_reference(r, SignalId(""), 1.0, 0.0, "+")
    var handle = b.add_signal_reference(r, SignalId("x"), 50.0, 0.0, "+")
    assert_almost_equal(b.roads[r].info.signals[0].s, 12.0 - 0.00001)
    with assert_raises():
        b.add_validity_to_signal_reference(handle, LaneId(1 << 40), LaneId(0))
    with assert_raises():
        b.add_validity_to_signal_reference(handle, LaneId(0), LaneId(1 << 40))
    with assert_raises():
        b.add_signal_position_inertial(SignalId("x"), 0, 0, 0, 0, 0, 0)
    with assert_raises():
        b.add_dependency_to_signal(SignalId("x"), "a", "b")
    with assert_raises():
        b.add_signal_position_road(SignalId("x"), RoadId(1), 0, 0, 0, 0, 0, 0)
    with assert_raises():
        b.add_signal_position_road(SignalId("x"), RoadId(-1), 0, 0, 0, 0, 0, 0)
    # The builder refuses to build a reference to no signal.
    with assert_raises():
        _ = b.build()


def test_builder_signals() raises:
    var b = MapBuilder()
    var r = _flat_road(
        b, 1, 0, 0, 0, 20, -1, 0, 0, True, [(-1, LANE_DRIVING, 0, 0)]
    )
    _ = b.add_signal(
        r,
        SignalId("a"),
        5,
        -10,
        "first",
        "",
        "+",
        0,
        "",
        "274",
        "",
        0,
        "",
        0,
        0,
        "",
        0,
        0,
        0,
    )
    # The same id replaces the signal and adds a second reference.
    _ = b.add_signal(
        r,
        SignalId("a"),
        6,
        -10,
        "second",
        "",
        "+",
        0,
        "",
        "274",
        "",
        0,
        "",
        0,
        0,
        "",
        0,
        0,
        0,
    )
    _ = b.add_signal(
        r,
        SignalId("b"),
        1,
        -10,
        "b",
        "",
        "+",
        0,
        "",
        "274",
        "",
        0,
        "",
        0,
        0,
        "",
        0,
        0,
        0,
    )
    b.add_signal_position_road(
        SignalId("b"), RoadId(1), 8.0, -12.0, 1.0, 0.0, 0.0, 0.0
    )
    # A junction whose road has only lane 0.
    _ = _flat_road(b, 2, 0, 50, 0, 10, 7, 0, 0, True, [(0, LANE_NONE, 0, 0)])
    b.add_junction(JuncId(7), "j")
    b.add_junction(JuncId(7), "again")
    b.add_connection(JuncId(7), ConId(1), RoadId(1), RoadId(2))
    b.add_connection(JuncId(7), ConId(0), RoadId(1), RoadId(2))
    b.add_connection(JuncId(7), ConId(1), RoadId(1), RoadId(2))
    with assert_raises():
        b.add_connection(JuncId(8), ConId(1), RoadId(1), RoadId(1))
    with assert_raises():
        b.add_lane_link(JuncId(7), ConId(5), LaneId(1), LaneId(1))
    b.add_junction_controller(
        JuncId(7), [ControllerId("z"), ControllerId("c"), ControllerId("z")]
    )
    b.create_controller(ControllerId("c"), "c", 3, [SignalId("b")])
    b.create_controller(
        ControllerId("c"), "later", 4, [SignalId("a"), SignalId("a")]
    )
    b.create_controller(ControllerId("d"), "d", 1, [SignalId("a")])
    var map = b.build()
    assert_equal(len(map.signals), 2)
    assert_equal(map.signal(SignalId("a")).name, "second")
    _near(map.signal(SignalId("b")).transform.location, 8.0, 12.0, 1.0)
    assert_equal(len(map.road(RoadId(1)).info.signals), 3)
    assert_equal(len(map.junctions), 1)
    assert_equal(map.junctions[0].name, "j")
    assert_equal(map.junctions[0].connections[0].id, ConId(0))
    assert_equal(len(map.junctions[0].connections), 2)
    assert_equal(len(map.junctions[0].controllers), 2)
    assert_equal(map.junctions[0].controllers[0], ControllerId("c"))
    ref c = map.controller(ControllerId("c"))
    assert_equal(c.name, "c")
    assert_equal(len(c.signals), 1)
    assert_equal(c.signals[0], SignalId("a"))
    assert_equal(len(c.junctions), 1)
    assert_equal(map.controllers[1].id, ControllerId("d"))
    assert_equal(len(map.signal(SignalId("a")).controllers), 1)
    # A junction whose connecting road holds no lanes has CARLA's empty
    # box.
    var box = junction_box(map, JuncId(7))
    assert_true(box.min.x > box.max.x)


def test_builder_links() raises:
    var b = MapBuilder()
    # Road 1 ends into road 2 (which lacks the lane), and its lane -2
    # leads into road 9, which is not there.
    _ = _flat_road(
        b,
        1,
        0,
        0,
        0,
        10,
        -1,
        0,
        2,
        True,
        [
            (-2, LANE_DRIVING, 0, -2),
            (-1, LANE_DRIVING, 0, -1),
            (0, LANE_NONE, 0, 0),
        ],
    )
    _ = _flat_road(
        b, 2, 10, 0, 0, 10, -1, 1, 0, True, [(-1, LANE_DRIVING, -1, 0)]
    )
    # A two-section road whose lane -1 has no link across the sections.
    var r3 = _flat_road(
        b, 3, 0, 50, 0, 20, -1, 0, 0, True, [(-1, LANE_DRIVING, 0, 0)]
    )
    var sec = b.add_road_section(r3, SectionId(1), 10.0)
    _ = b.add_road_section_lane(
        r3, sec, LaneId(-1), LANE_DRIVING, False, LaneId(0), LaneId(0)
    )
    _ = b.add_road_section_lane(
        r3, sec, LaneId(1), LANE_DRIVING, False, LaneId(7), LaneId(0)
    )
    b.create_lane_width(b.lane(RoadId(3), LaneId(-1), 10.0), 10.0, 3.5, 0, 0, 0)
    b.create_lane_width(b.lane(RoadId(3), LaneId(1), 10.0), 10.0, 3.5, 0, 0, 0)
    # A road into a junction id that is not a junction.
    _ = _flat_road(
        b, 4, 0, 90, 0, 10, -1, 0, 50, True, [(-1, LANE_DRIVING, 0, -1)]
    )
    var map = b.build()
    assert_equal(len(map.successors(_w(1, 0, -1, 5.0))), 1)
    assert_equal(len(map.successors(_w(1, 0, -2, 5.0))), 0)
    assert_equal(len(map.successors(_w(3, 0, -1, 5.0))), 0)
    assert_equal(len(map.successors(_w(3, 1, 1, 15.0))), 0)
    assert_equal(len(map.successors(_w(4, 0, -1, 5.0))), 0)
    assert_equal(len(map.road(RoadId(1)).nexts), 1)
    assert_equal(len(map.road(RoadId(2)).prevs), 1)
    # A topology lane that ends before the road does gets its end.
    var topology = map.generate_topology()
    var found = False
    for pair in topology:
        if pair[0].road_id == RoadId(3) and pair[0].section_id == SectionId(0):
            found = True
            _same(pair[1], 3, 0, -1, 10.0)
    assert_true(found)


def test_builder_junction_needs_its_roads() raises:
    var b = MapBuilder()
    _ = _flat_road(
        b, 1, 0, 0, 0, 10, -1, 0, 5, True, [(-1, LANE_DRIVING, 0, -1)]
    )
    b.add_junction(JuncId(5), "j")
    b.add_connection(JuncId(5), ConId(0), RoadId(1), RoadId(9))
    with assert_raises():
        _ = b.build()


def test_signals_move_off_lanes() raises:
    # A right-hand road with driving lanes on both sides of lane -1: the
    # sign has nowhere to go and stays after one try, facing the lane.
    var b = MapBuilder()
    var r = _flat_road(
        b,
        1,
        0,
        0,
        0,
        30,
        -1,
        0,
        0,
        True,
        [
            (-2, LANE_DRIVING, 0, 0),
            (-1, LANE_DRIVING, 0, 0),
            (0, LANE_NONE, 0, 0),
            (1, LANE_DRIVING, 0, 0),
        ],
    )
    _ = b.add_signal(
        r,
        SignalId("s"),
        10,
        -1.75,
        "",
        "",
        "+",
        0,
        "",
        "274",
        "",
        0,
        "",
        0,
        0,
        "",
        0,
        0,
        0,
    )
    var both = b.build()
    _near(both.signal(SignalId("s")).transform.location, 10.0, 1.75, 0.0)
    # Driving to the right only: it moves left, 0.7 m at a time.
    b = MapBuilder()
    r = _flat_road(
        b,
        1,
        0,
        0,
        0,
        30,
        -1,
        0,
        0,
        True,
        [
            (-2, LANE_DRIVING, 0, 0),
            (-1, LANE_DRIVING, 0, 0),
            (0, LANE_NONE, 0, 0),
            (1, LANE_SIDEWALK, 0, 0),
        ],
    )
    _ = b.add_signal(
        r,
        SignalId("s"),
        10,
        -1.75,
        "",
        "",
        "+",
        0,
        "",
        "274",
        "",
        0,
        "",
        0,
        0,
        "",
        0,
        0,
        0,
    )
    var left = b.build()
    _near(left.signal(SignalId("s")).transform.location, 10.0, -1.05, 0.0)
    # A left-hand road moves left first.
    b = MapBuilder()
    r = _flat_road(
        b,
        1,
        0,
        0,
        0,
        30,
        -1,
        0,
        0,
        False,
        [
            (-1, LANE_DRIVING, 0, 0),
            (0, LANE_NONE, 0, 0),
            (1, LANE_DRIVING, 0, 0),
        ],
    )
    _ = b.add_signal(
        r,
        SignalId("s"),
        10,
        1.75,
        "",
        "",
        "+",
        0,
        "",
        "274",
        "",
        0,
        "",
        0,
        0,
        "",
        0,
        0,
        0,
    )
    var lh = b.build()
    _near(lh.signal(SignalId("s")).transform.location, 10.0, -4.55, 0.0)
    # A left-hand road with driving on the left moves right.
    b = MapBuilder()
    r = _flat_road(
        b,
        1,
        0,
        0,
        0,
        30,
        -1,
        0,
        0,
        False,
        [
            (-1, LANE_SIDEWALK, 0, 0),
            (0, LANE_NONE, 0, 0),
            (1, LANE_DRIVING, 0, 0),
            (2, LANE_DRIVING, 0, 0),
        ],
    )
    _ = b.add_signal(
        r,
        SignalId("s"),
        10,
        1.75,
        "",
        "",
        "+",
        0,
        "",
        "274",
        "",
        0,
        "",
        0,
        0,
        "",
        0,
        0,
        0,
    )
    var lh_right = b.build()
    _near(lh_right.signal(SignalId("s")).transform.location, 10.0, 1.05, 0.0)
    # Shoulders all the way: ten steps find no place, so it stays.
    b = MapBuilder()
    var lanes = List[Tuple[Int, LaneType, Int, Int]]()
    lanes.append((-1, LANE_DRIVING, 0, 0))
    for i in range(2, 16):
        lanes.append((-i, LANE_SHOULDER, 0, 0))
    r = _flat_road(b, 1, 0, 0, 0, 30, -1, 0, 0, True, lanes)
    _ = b.add_signal(
        r,
        SignalId("s"),
        10,
        -1.75,
        "",
        "",
        "+",
        0,
        "",
        "274",
        "",
        0,
        "",
        0,
        0,
        "",
        0,
        0,
        0,
    )
    var stuck = b.build()
    _near(stuck.signal(SignalId("s")).transform.location, 10.0, 1.75, 0.0)
    # A map with no driving lane leaves every sign alone.
    b = MapBuilder()
    r = _flat_road(
        b, 1, 0, 0, 0, 30, -1, 0, 0, True, [(-1, LANE_SIDEWALK, 0, 0)]
    )
    _ = b.add_signal(
        r,
        SignalId("s"),
        10,
        -1.75,
        "",
        "",
        "+",
        0,
        "",
        "274",
        "",
        0,
        "",
        0,
        0,
        "",
        0,
        0,
        0,
    )
    var alone = b.build()
    check_signals_on_roads(alone)
    _near(alone.signal(SignalId("s")).transform.location, 10.0, 1.75, 0.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
