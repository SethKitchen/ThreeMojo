# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Required known blocker: translated-grid full-Map construction.

This is the unchanged failing case from the focused 7/8 native result.
The current partition raises its spatial subdivision limit before querying.
The axis helper patch does not fix this separate representation limit.
"""

from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.lane_refinement import _axis_lane_minimum
from extensions.carla.map import Controller, Junction, Map, Signal
from extensions.carla.opendrive import load_opendrive
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import LaneId
from math.vector3 import Vector3
from std.math import inf
from std.testing import TestSuite, assert_equal, assert_false, assert_raises, assert_true


def _flat_map(
    length: Float64 = 1.0, origin: Float64 = 0.0,
    record_s: Float64 = 0.0, reverse: Bool = False,
) raises -> Map:
    var side = "left" if reverse else "right"
    var id = 1 if reverse else -1
    var parsed = load_opendrive(String(
        '<OpenDRIVE><road id="1" length="1" junction="-1" rule="RHT">'
        '<planView><geometry s="0" x="0" y="0" hdg="0" length="1">'
        '<line/></geometry></planView><lanes><laneOffset s="0" a="0"'
        ' b="0" c="0" d="0"/><laneSection s="0">'
        '<center><lane id="0" type="none"/></center><', side, '><lane id="', id,
        '" type="driving"><width sOffset="0" a="0.0002" b="0" c="0" d="0"/>'
        '</lane></', side, '></laneSection></lanes></road></OpenDRIVE>',
    ))
    var roads = parsed.roads.copy()
    roads[0].length = record_s + length
    roads[0].sections[0].s = record_s
    roads[0].info.geometries[0].s = record_s
    roads[0].info.geometries[0].geometry.s = record_s
    roads[0].info.geometries[0].geometry.length = length
    roads[0].info.geometries[0].geometry.x = origin
    var lane = roads[0].sections[0].lane_index(LaneId(id))
    roads[0].sections[0].lanes[lane].distance = record_s
    roads[0].sections[0].lanes[lane].info.widths[0].polynomial = CubicPolynomial.constant(0.0002)
    return Map(roads^, List[Junction](), List[Signal](), List[Controller]())


def test_translated_parameter_grid_keeps_exact_bracket_order() raises:
    # Near 1e20 the representable parameter spacing is exactly 16384.
    # C_x(s)=s-1e20, so 10000 is nearer 16384 than zero. A query of
    # 8192 is an exact distance tie; the helper keeps the lower parameter.
    var base = Float64(1e20)
    var map = _flat_map(length=81920.0, record_s=base)
    assert_equal(map.closest_waypoint_on_road(Vector3(10000, 0.0001, 0)).value().s, base + 16384.0)
    assert_equal(map.closest_waypoint_on_road(Vector3(8192, 0.0001, 0)).value().s, base)
    assert_equal(map.closest_waypoint_on_road(Vector3(5000, 0.0001, 0)).value().s, base)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
