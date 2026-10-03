# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Standalone desired-behavior repro for the uncertified affine shortcut.

Not executed by the author. Python binary64 reconstruction predicts that the
current shortcut returns target_s + 0.125 and classifies this query off-road.
Both separate multiply/add and libm fma give that prediction. The native graph
must establish the actual shipped result; this test does not assume bad bits.
"""

from extensions.carla.curve_distance import (
    _wide_plan_contains,
    _wide_point_order,
)
from extensions.carla.map import Controller, Junction, Map, Signal
from extensions.carla.opendrive import load_opendrive
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import LaneId
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


def test_affine_projection_preserves_reachable_center() raises:
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
    # Set existing Float64 storage directly, as in wide-classification controls.
    # The rebuilt Map takes its index and certificates from this same snapshot.
    roads[0].length = 1e20
    roads[0].info.geometries[0].geometry.length = 1e20
    var lane = roads[0].sections[0].lane_index(LaneId(-1))
    roads[0].sections[0].lanes[lane].info.widths[
        0
    ].polynomial = CubicPolynomial.constant(0.0002)
    var map = Map(roads^, List[Junction](), List[Signal](), List[Controller]())
    assert_true(map.roads[0].lane_is_straight(0))
    assert_equal(map.segment_count(), 1)
    var segment = map.segment(0)
    # Exact existing segment construction: start = 10 * EPSILON. The tiny
    # end inset rounds away at 1e20; no representable interior end is assumed.
    assert_equal(
        bitcast[DType.uint64](segment[2].s), UInt64(0x3D19000000000000)
    )
    assert_equal(
        bitcast[DType.uint64](segment[3].s), UInt64(0x4415AF1D78B58C40)
    )

    var location = Vector3(Float32(1e15), Float32(0.0001), 0)
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        0.0,
    ]
    var target_s = query[0]
    assert_equal(bitcast[DType.uint64](target_s), UInt64(0x430C6BF520000000))
    assert_equal(bitcast[DType.uint64](query[1]), UInt64(0x3F1A36E2E0000000))
    # C(s) = (s, Float64(0.0001), 0), with a representable exact x minimum.
    var target_center = map.roads[0]._lane_center(0, lane, target_s)
    assert_equal(target_center[0], target_s)
    assert_equal(
        bitcast[DType.uint64](target_center[1]), UInt64(0x3F1A36E2EB1C432D)
    )
    assert_equal(target_center[2], 0.0)
    assert_true(_wide_plan_contains(target_center, query, 0.0002))

    var nearest = map.closest_waypoint_on_road(location).value()
    var selected = map.roads[0]._lane_center(0, lane, nearest.s)
    var under = map.waypoint(location)
    print("AFFINE_PROJECT_START_BITS", bitcast[DType.uint64](segment[2].s))
    print("AFFINE_PROJECT_END_BITS", bitcast[DType.uint64](segment[3].s))
    print("AFFINE_PROJECT_TARGET_BITS", bitcast[DType.uint64](target_s))
    print("AFFINE_PROJECT_SELECTED_BITS", bitcast[DType.uint64](nearest.s))
    print("AFFINE_PROJECT_X_GAP", selected[0] - query[0])
    print(
        "AFFINE_PROJECT_REFERENCE_ORDER",
        _wide_point_order(target_center, selected, query),
    )
    print("AFFINE_PROJECT_ON_ROAD", Bool(under))
    # Desired behavior. Python predicts selected bits 0x430c6bf520000001,
    # x gap 0.125, reference order -1, and on-road False on current sources.
    assert_equal(nearest.s, target_s)
    assert_true(Bool(under))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
