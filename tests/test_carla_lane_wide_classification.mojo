# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Required control for retaining wide center precision in on-road lookup."""

from extensions.carla.map import Controller, Junction, Map, Signal
from extensions.carla.opendrive import load_opendrive
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import LaneId
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def test_narrow_lane_at_wide_origin_is_not_a_rounded_on_road_hit() raises:
    var parsed = load_opendrive(
        '<OpenDRIVE><road id="1" length="1" junction="-1" rule="RHT">'
        '<planView><geometry s="0" x="0" y="0" hdg="0" length="1">'
        '<line/></geometry></planView><lanes><laneOffset s="0" a="0"'
        ' b="0" c="0" d="0"/><laneSection s="0">'
        '<center><lane id="0" type="none"/></center><right><lane id="-1"'
        ' type="driving"><width sOffset="0" a="0.0002" b="0" c="0" d="0"/>'
        "</lane></right></laneSection></lanes></road></OpenDRIVE>"
    )
    var roads = parsed.roads.copy()
    # Bypass MapBuilder's separate Float32 input storage. RoadGeometry.x can
    # hold the exact Float64 origin and lane queries must retain that precision.
    roads[0].info.geometries[0].geometry.x = 1000000001.0
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    var point = Vector3(Float32(1000000000.0), Float32(0.0001), 0)
    var nearest = map.certified_closest_waypoint_on_road(point)
    assert_true(Bool(nearest))
    var w = nearest.value()
    assert_equal(w.lane_id, LaneId(-1))
    var lane = map.roads[0].sections[0].lane_index(LaneId(-1))
    var center = map.roads[0]._lane_point(0, lane, w.s)
    assert_true(center.x - Float64(point.x) >= 1.0)
    # The public transform cannot represent the one-meter x gap here.
    assert_equal(map.compute_transform(w).location.x, point.x)
    # The wide center is a full meter away, far outside the 0.1 mm half-width.
    assert_false(Bool(map.certified_waypoint(point)))


def test_zero_squared_score_does_not_certify_coincident_center() raises:
    var parsed = load_opendrive(
        '<OpenDRIVE><road id="1" length="1" junction="-1" rule="RHT">'
        '<planView><geometry s="0" x="-0.5" y="0" hdg="0" length="1">'
        '<line/></geometry></planView><lanes><laneOffset s="0" a="0"'
        ' b="0" c="0" d="0"/><laneSection s="0">'
        '<left><lane id="1" type="driving"><width sOffset="0" a="1"'
        ' b="0" c="0" d="0"/></lane></left>'
        '<center><lane id="0" type="none"/></center><right><lane id="-1"'
        ' type="driving"><width sOffset="0" a="1" b="0" c="0" d="0"/>'
        "</lane></right></laneSection></lanes></road></OpenDRIVE>"
    )
    var roads = parsed.roads.copy()
    var tiny = Float64(1e-200)
    roads[0].info.lane_offsets[0].polynomial = CubicPolynomial.constant(-tiny)
    var right = roads[0].sections[0].lane_index(LaneId(-1))
    var left = roads[0].sections[0].lane_index(LaneId(1))
    roads[0].sections[0].lanes[right].info.widths[
        0
    ].polynomial = CubicPolynomial.constant(2.0 * tiny)
    roads[0].sections[0].lanes[left].info.widths[
        0
    ].polynomial = CubicPolynomial.constant(2.0 * tiny)
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    var point = Vector3(0, 0, 0)
    var right_center = map.roads[0]._lane_point(0, right, 0.5)
    var left_center = map.roads[0]._lane_point(0, left, 0.5)
    assert_equal(right_center.x, 0.0)
    assert_true(abs(right_center.y) > 0.0)
    assert_equal(left_center.x, 0.0)
    assert_equal(left_center.y, 0.0)
    assert_equal(left_center.z, 0.0)
    # Both raw squared scores underflow to zero. Only the left center is
    # actually coincident, so the earlier inserted right lane must not win.
    assert_equal(map.roads[0]._lane_distance_squared(0, right, 0.5, point), 0.0)
    assert_equal(map.roads[0]._lane_distance_squared(0, left, 0.5, point), 0.0)
    var nearest = map.certified_closest_waypoint_on_road(point).value()
    print(
        "ZERO_SQUARE_CENTERS",
        right_center.y,
        left_center.y,
        nearest.lane_id.value,
    )
    assert_equal(nearest.lane_id, LaneId(1))
    var under = map.certified_waypoint(point)
    assert_true(Bool(under))
    assert_equal(under.value().lane_id, LaneId(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
