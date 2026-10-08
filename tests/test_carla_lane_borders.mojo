# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Border-only OpenDRIVE lanes get their widths from their borders (#577).

ASAM OpenDRIVE 1.8.1, section 11.6.2: a `<border>` is a lane's outer limit,
measured from the reference line. Every expected value here comes from the
border cubics by hand, not from the code under test.
"""

from extensions.carla.map import Map, Waypoint
from extensions.carla.opendrive import _Cubic, _lowest, load_opendrive
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

comptime _ZERO_OFFSET = '<laneOffset s="0" a="0" b="0" c="0" d="0"/>'


def _road(
    sections: String, offset: String = _ZERO_OFFSET, rule: String = "RHT"
) -> String:
    # A straight 10 m road along +x from the origin.
    return (
        '<OpenDRIVE><road id="1" length="10" junction="-1" rule="'
        + rule
        + '"><planView><geometry s="0" x="0" y="0" hdg="0" length="10">'
        + "<line/></geometry></planView><lanes>"
        + offset
        + sections
        + "</lanes></road></OpenDRIVE>"
    )


def _section(s: Float64, left: String, right: String) -> String:
    var text = '<laneSection s="' + String(s) + '">'
    if left != "":
        text += "<left>" + left + "</left>"
    text += '<center><lane id="0" type="none" level="false"/></center>'
    if right != "":
        text += "<right>" + right + "</right>"
    return text + "</laneSection>"


def _lane(id: Int, records: String) -> String:
    return (
        '<lane id="'
        + String(id)
        + '" type="driving" level="false">'
        + records
        + "</lane>"
    )


def _record(
    tag: String,
    s_offset: Float64,
    a: Float64,
    b: Float64 = 0.0,
    c: Float64 = 0.0,
    d: Float64 = 0.0,
) -> String:
    return (
        "<"
        + tag
        + ' sOffset="'
        + String(s_offset)
        + '" a="'
        + String(a)
        + '" b="'
        + String(b)
        + '" c="'
        + String(c)
        + '" d="'
        + String(d)
        + '"/>'
    )


def _border(
    s_offset: Float64,
    a: Float64,
    b: Float64 = 0.0,
    c: Float64 = 0.0,
    d: Float64 = 0.0,
) -> String:
    return _record("border", s_offset, a, b, c, d)


def _width(s_offset: Float64, a: Float64) -> String:
    return _record("width", s_offset, a)


def _at(map: Map, section: Int, lane: Int, s: Float32) raises -> Waypoint:
    return map.waypoint_xodr(RoadId(1), LaneId(lane), Length(s, METER)).value()


def _width_at(map: Map, lane: Int, s: Float32) raises -> Float64:
    return map.lane_width_meters(_at(map, 0, lane, s))


def test_right_border_only_lane_has_its_width_and_center() raises:
    # The issue's road: lane -1's outer limit is 3.5 m right of the line.
    var map = load_opendrive(
        _road(_section(0, "", _lane(-1, _border(0, -3.5))))
    )
    var waypoint = _at(map, 0, -1, 5)
    assert_almost_equal(map.lane_width_meters(waypoint), 3.5)
    # The world frame reflects y, so the right lane's center is at +1.75.
    var center = map.compute_transform(waypoint).location
    assert_almost_equal(Float64(center.x), 5.0, atol=1e-5)
    assert_almost_equal(Float64(center.y), 1.75, atol=1e-5)
    var found = map.waypoint(Vector3(5, 1.75, 0))
    assert_true(Bool(found))
    assert_equal(found.value().lane_id.value, -1)


def test_left_lanes_with_cubic_borders_under_lht() raises:
    # Lane 2's border is 6 + 0.1 x + 0.01 x^2 + 0.001 x^3 and lane 1's is 3.
    # At s = 4: lane 2's width is 6.624 - 3 = 3.624, its center is
    # 3 + 1.812 = 4.812 left of the line, at y = -4.812 in the world.
    var left = _lane(1, _border(0, 3.0)) + _lane(
        2, _border(0, 6.0, 0.1, 0.01, 0.001)
    )
    var map = load_opendrive(_road(_section(0, left, ""), rule="LHT"))
    assert_almost_equal(_width_at(map, 1, 4), 3.0)
    assert_almost_equal(_width_at(map, 2, 4), 3.624, atol=1e-6)
    var center = map.compute_transform(_at(map, 0, 2, 4)).location
    assert_almost_equal(Float64(center.y), -4.812, atol=1e-5)
    var found = map.waypoint(Vector3(4, -4.812, 0))
    assert_true(Bool(found))
    assert_equal(found.value().lane_id.value, 2)


def test_border_records_and_sections_split_the_widths() raises:
    # Section 0, s in [0, 6): lane -1's border is -3, then from s = 4 it is
    # -3 - 0.25 (s - 4). Lane -2's border is -6, so its width follows lane
    # -1's change. The records are out of order in the file.
    var first = _lane(-1, _border(4, -3.0, -0.25) + _border(0, -3.0)) + _lane(
        -2, _border(0, -6.0)
    )
    # Section 1, s in [6, 10]: lane -1 is 2 m wide and lane -2 3 m wide.
    var second = _lane(-1, _border(0, -2.0)) + _lane(-2, _border(0, -5.0))
    var map = load_opendrive(
        _road(_section(0, "", first) + _section(6, "", second))
    )
    assert_almost_equal(_width_at(map, -1, 2), 3.0)
    assert_almost_equal(_width_at(map, -1, 5), 3.25)
    assert_almost_equal(_width_at(map, -2, 2), 3.0)
    assert_almost_equal(_width_at(map, -2, 5), 2.75)
    assert_almost_equal(_width_at(map, -1, 8), 2.0)
    assert_almost_equal(_width_at(map, -2, 8), 3.0)


def test_early_and_past_the_end_border_records() raises:
    # A record before the section's start holds at its start, and a record
    # past the road's end starts no width.
    var right = _lane(-1, _border(-1, -2.0, -1.0) + _border(20, -9.0)) + _lane(
        -2, _border(0, -20.0)
    )
    var map = load_opendrive(_road(_section(0, "", right)))
    # Lane -1's border is -2 - (s + 1): 3 m wide at s = 0, 8 m at s = 5.
    # Lane -2 then spans -8 to -20 at s = 5.
    assert_almost_equal(_width_at(map, -1, 0), 3.0)
    assert_almost_equal(_width_at(map, -1, 5), 8.0)
    assert_almost_equal(_width_at(map, -2, 5), 12.0)
    # Lane -2's border at -7 crosses lane -1's after s = 4.
    with assert_raises(contains="of lane -2 crosses its inner border"):
        _ = load_opendrive(
            _road(
                _section(
                    0,
                    "",
                    _lane(-1, _border(0, -3.0, -1.0))
                    + _lane(-2, _border(0, -7.0)),
                )
            )
        )


def test_widths_win_over_borders_in_the_same_lane() raises:
    var lane = _lane(-1, _width(0, 3.0) + _border(0, -5.0))
    var map = load_opendrive(_road(_section(0, "", lane)))
    assert_almost_equal(_width_at(map, -1, 5), 3.0)


def test_border_lanes_refuse_mixed_widths_and_offsets() raises:
    var mixed = _lane(-1, _width(0, 3.0)) + _lane(-2, _border(0, -6.0))
    with assert_raises(contains="mixes <border> lanes with <width> lanes"):
        _ = load_opendrive(_road(_section(0, "", mixed)))
    var offset = '<laneOffset s="0" a="0" b="0" c="0" d="0.5"/>'
    with assert_raises(contains="nonzero <laneOffset>"):
        _ = load_opendrive(
            _road(_section(0, "", _lane(-1, _border(0, -3.0))), offset)
        )


def test_border_lanes_refuse_missing_borders() raises:
    with assert_raises(contains="lane -1 has no border at its lane section"):
        _ = load_opendrive(_road(_section(0, "", _lane(-1, _border(2, -3.0)))))
    var gap = _lane(-1, "") + _lane(-2, _border(0, -6.0))
    with assert_raises(contains="lane -2 needs its inner lane's border"):
        _ = load_opendrive(_road(_section(0, "", gap)))
    # Section 0 ends where it starts.
    var right = _lane(-1, _border(0, -3.0))
    with assert_raises(contains="need a lane section of length"):
        _ = load_opendrive(
            _road(_section(0, "", right) + _section(0, "", right))
        )


def test_border_lanes_refuse_crossing_borders() raises:
    # Lane -1's width 3 - x is negative past s = 3.
    with assert_raises(contains="of lane -1 crosses its inner border"):
        _ = load_opendrive(
            _road(_section(0, "", _lane(-1, _border(0, -3.0, 1.0))))
        )
    # Width x^2 - 4 x + 3.9 is positive at both ends and -0.1 at s = 2.
    with assert_raises(contains="of lane -1 crosses its inner border"):
        _ = load_opendrive(
            _road(_section(0, "", _lane(-1, _border(0, -3.9, 4.0, -1.0))))
        )


def test_lowest_value_of_a_cubic_on_an_interval() raises:
    # Constant and linear cubics have no interior critical point.
    assert_equal(_lowest(_Cubic(0, 0.0, 2.0, 0.0, 0.0, 0.0), 1.0), 2.0)
    assert_equal(_lowest(_Cubic(0, 0.0, 2.0, -1.0, 0.0, 0.0), 1.0), 1.0)
    # (x - 1)^2 - 1 has its minimum -1 at x = 1, inside [0, 3] but past
    # [0, 0.5] and before [2, 3] in the shifted form below.
    assert_equal(_lowest(_Cubic(0, 0.0, 0.0, -2.0, 1.0, 0.0), 3.0), -1.0)
    assert_equal(_lowest(_Cubic(0, 0.0, 0.0, -2.0, 1.0, 0.0), 0.5), -0.75)
    assert_equal(_lowest(_Cubic(0, 0.0, 3.0, 4.0, 1.0, 0.0), 2.0), 3.0)
    # x^3 - 3 x has critical points at -1 and 1; on [0, 2] the least is -2.
    assert_equal(_lowest(_Cubic(0, 0.0, 0.0, -3.0, 0.0, 1.0), 2.0), -2.0)
    # x^3 + x is increasing: its derivative 3 x^2 + 1 has no real root.
    assert_equal(_lowest(_Cubic(0, 0.0, 0.0, 1.0, 0.0, 1.0), 2.0), 0.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
