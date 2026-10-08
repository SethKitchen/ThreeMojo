# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Exact references for the bounded flat-axis stored-point minimum."""

from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.lane_refinement import _axis_lane_minimum
from extensions.carla.map import Controller, Junction, Map, Signal
from extensions.carla.opendrive import load_opendrive
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import LaneId
from math.vector3 import Vector3
from std.math import inf
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _flat_map(
    length: Float64 = 1.0,
    origin: Float64 = 0.0,
    record_s: Float64 = 0.0,
    reverse: Bool = False,
) raises -> Map:
    var side = "left" if reverse else "right"
    var id = 1 if reverse else -1
    var parsed = load_opendrive(
        String(
            (
                '<OpenDRIVE><road id="1" length="1" junction="-1" rule="RHT">'
                '<planView><geometry s="0" x="0" y="0" hdg="0" length="1">'
                '<line/></geometry></planView><lanes><laneOffset s="0" a="0"'
                ' b="0" c="0" d="0"/><laneSection s="0">'
                '<center><lane id="0" type="none"/></center><'
            ),
            side,
            '><lane id="',
            id,
            (
                '" type="driving"><width sOffset="0" a="0.0002" b="0" c="0"'
                ' d="0"/></lane></'
            ),
            side,
            "></laneSection></lanes></road></OpenDRIVE>",
        )
    )
    var roads = parsed.roads.copy()
    roads[0].length = record_s + length
    roads[0].sections[0].s = record_s
    roads[0].info.geometries[0].s = record_s
    roads[0].info.geometries[0].geometry.s = record_s
    roads[0].info.geometries[0].geometry.length = length
    roads[0].info.geometries[0].geometry.x = origin
    var lane = roads[0].sections[0].lane_index(LaneId(id))
    roads[0].sections[0].lanes[lane].distance = record_s
    roads[0].sections[0].lanes[lane].info.widths[
        0
    ].polynomial = CubicPolynomial.constant(0.0002)
    return Map(roads^, List[Junction](), List[Signal](), List[Controller]())


def test_axis_endpoints_are_exact_minima() raises:
    var map = _flat_map(length=10.0)
    var segment = map.segment(0)
    var low = min(segment[2].s, segment[3].s)
    var high = max(segment[2].s, segment[3].s)
    assert_equal(
        map.certified_closest_waypoint_on_road(Vector3(-1, 0.0001, 0))
        .value()
        .s,
        low,
    )
    assert_equal(
        map.certified_closest_waypoint_on_road(Vector3(11, 0.0001, 0))
        .value()
        .s,
        high,
    )


def test_reverse_lane_uses_same_exact_parameter_minimum() raises:
    var map = _flat_map(reverse=True)
    var segment = map.segment(0)
    assert_true(segment[2].s > segment[3].s)
    var location = Vector3(Float32(0.1), Float32(-0.0001), 0)
    var nearest = map.certified_closest_waypoint_on_road(location).value()
    assert_equal(nearest.lane_id, LaneId(1))
    assert_equal(nearest.s, Float64(location.x))
    assert_true(Bool(map.certified_waypoint(location)))


def test_translated_parameter_grid_rejects_unrepresentable_subdivision() raises:
    # Preserve the original five-ULP Map input. No contiguous partition
    # can meet the unchanged one-millimeter parameter-matched chord target.
    # The exact bracket and tie successes remain in the direct-Road suite.
    var base = Float64(1e20)
    with assert_raises(contains="Float64 road-s resolution"):
        _ = _flat_map(length=81920.0, record_s=base)


def test_wide_origin_search_reaches_adjacent_stored_parameters() raises:
    var map = _flat_map(length=2e20, origin=-1e20)
    var location = Vector3(10000, 0.0001, 0)
    var nearest = map.certified_closest_waypoint_on_road(location).value()
    assert_equal(nearest.s, Float64(1e20) + 16384.0)
    var lane = map.roads[0].sections[0].lane_index(LaneId(-1))
    var center = map.roads[0]._lane_center(0, lane, nearest.s)
    assert_equal(center[0], 16384.0)
    var lower = map.roads[0]._lane_center(0, lane, 1e20)
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        0.0,
    ]
    assert_equal(_wide_point_order(center, lower, query), -1)


def test_large_origin_plateau_is_an_exact_minimum() raises:
    var origin = Float64(73786976294838206464.0)  # 2^66, exact in Float32.
    var map = _flat_map(origin=origin)
    var location = Vector3(Float32(origin), 0.0001, 0)
    var nearest = map.certified_closest_waypoint_on_road(location).value()
    var segment = map.segment(0)
    var lane = map.roads[0].sections[0].lane_index(LaneId(-1))
    var first = map.roads[0]._lane_center(0, lane, segment[2].s)
    var last = map.roads[0]._lane_center(0, lane, segment[3].s)
    assert_equal(first[0], origin)
    assert_equal(last[0], origin)
    assert_true(nearest.s >= min(segment[2].s, segment[3].s))
    assert_true(nearest.s <= max(segment[2].s, segment[3].s))
    assert_true(Bool(map.certified_waypoint(location)))


def test_axis_search_charges_existing_work_limits() raises:
    var map = _flat_map(length=2e20, origin=-1e20)
    var lane = map.roads[0].sections[0].lane_index(LaneId(-1))
    var location = Vector3(10000, 0.0001, 0)
    var exact = _axis_lane_minimum(map.roads[0], 0, lane, 0.0, 2e20, location)
    ref certified = exact.value()
    assert_equal(certified[3], 64)
    assert_equal(certified[4], 66)
    with assert_raises(contains="interval work limit"):
        _ = _axis_lane_minimum(
            map.roads[0], 0, lane, 0.0, 2e20, location, max_nodes=1
        )
    with assert_raises(contains="quadrature work limit"):
        _ = _axis_lane_minimum(
            map.roads[0], 0, lane, 0.0, 2e20, location, max_terms=2
        )
    with assert_raises(contains="numerical accuracy limit"):
        _ = _axis_lane_minimum(
            map.roads[0], 0, lane, 0.0, 2e20, location, max_depth=0
        )


def test_axis_search_rejects_invalid_parameter_bounds() raises:
    var map = _flat_map()
    var lane = map.roads[0].sections[0].lane_index(LaneId(-1))
    for bounds in [(-1.0, 1.0), (1.0, 0.0), (0.0, inf[DType.float64]())]:
        with assert_raises(contains="finite nonnegative parameter bounds"):
            _ = _axis_lane_minimum(
                map.roads[0], 0, lane, bounds[0], bounds[1], Vector3(0, 0, 0)
            )


def test_other_affine_shapes_cannot_claim_axis_certificate() raises:
    var map = _flat_map()
    var road = map.roads[0].copy()
    var lane = road.sections[0].lane_index(LaneId(-1))
    road.info.geometries[0].geometry.heading = 0.7
    assert_false(
        Bool(_axis_lane_minimum(road, 0, lane, 0.0, 1.0, Vector3(0, 0, 0)))
    )
    road.info.geometries[0].geometry.heading = 0.0
    road.info.elevations[0].polynomial.b = 0.1
    assert_false(
        Bool(_axis_lane_minimum(road, 0, lane, 0.0, 1.0, Vector3(0, 0, 0)))
    )
    road.info.elevations[0].polynomial.b = 0.0
    road.sections[0].lanes[lane].info.widths[0].polynomial.b = 0.1
    assert_false(
        Bool(_axis_lane_minimum(road, 0, lane, 0.0, 1.0, Vector3(0, 0, 0)))
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
