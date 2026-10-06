# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Constant ARC provenance and returned-pose controls for the review grid."""

from extensions.carla.map import Map
from extensions.carla.opendrive import load_opendrive, load_opendrive_file
from extensions.carla.curve_bounds import _lane_jet
from extensions.carla.curve_interval import _Interval
from extensions.carla.curve_frozen_arc import (
    _frozen_arc_context,
    _frozen_arc_center,
    _frozen_arc_expansion,
)
from std.math import isfinite
from extensions.carla.curve_rounded_arc import _rounded_arc_context
from extensions.carla.road_info import LaneId, RoadId
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)


def _map(
    heading: Float64 = 0.0,
    width: String = 'a="3.5" b="0" c="0" d="0"',
    grade: Float64 = 0.0,
    extra_width: String = "",
) raises -> Map:
    return load_opendrive(
        String(
            (
                '<OpenDRIVE><road id="1" length="30" junction="-1">'
                '<planView><geometry s="0" x="60" y="0" hdg="'
            ),
            heading,
            (
                '" length="30"><arc curvature="-0.05"/></geometry></planView>'
                '<elevationProfile><elevation s="0" a="0" b="'
            ),
            grade,
            (
                '" c="0" d="0"/></elevationProfile><lanes>'
                '<laneOffset s="0" a="0" b="0" c="0" d="0"/>'
                '<laneSection s="0"><center><lane id="0" type="none"/></center>'
                '<right><lane id="-1" type="driving"><width sOffset="0" '
            ),
            width,
            "/>",
            extra_width,
            "</lane></right></laneSection></lanes></road></OpenDRIVE>",
        )
    )


def _contains(map: Map, low: Float64, high: Float64) raises:
    ref road = map.roads[0]
    var lane = road.sections[0].lane_index(LaneId(-1))
    var bounds = _lane_jet(road, 0, lane, low, high)
    for station in [
        low,
        low + (high - low) * 0.25,
        low + (high - low) * 0.5,
        low + (high - low) * 0.75,
        high,
    ]:
        var center = road._lane_center(0, lane, station)
        assert_true(bounds[0].rounded_value().contains(center[0]))
        assert_true(bounds[1].rounded_value().contains(-center[1]))
        assert_true(bounds[2].rounded_value().contains(center[2]))


def test_constant_arc_snapshot_has_actual_stored_coefficient() raises:
    var map = _map()
    ref road = map.roads[0]
    var lane = road.sections[0].lane_index(LaneId(-1))
    var proof = _rounded_arc_context(road, 0, lane, 24.75, 25.0)
    assert_true(Bool(proof))
    var context = proof.value()
    # RN((RN(1/stored(-0.05)) + 1.75) * stored(-0.05)).
    # Fraction arithmetic gives this unique stored coefficient, not 0.9125.
    assert_equal(
        bitcast[DType.uint64](context.speed.low), UInt64(0x3FED333333333334)
    )
    assert_equal(context.speed.low, context.speed.high)
    assert_equal(context.x.low, 60.0)
    assert_equal(context.y.low, -1.75)
    assert_equal(context.z.low, 0.0)
    for low, high in [(0.01, 0.1), (5.0, 15.0), (24.75, 25.0), (29.9, 29.99)]:
        _contains(map, low, high)


def test_arc_snapshot_requires_structural_constant_records() raises:
    for map in [
        _map(heading=0.25),
        _map(width='a="3.5" b="0" c="0.01" d="0"'),
        _map(grade=0.02),
        _map(extra_width='<width sOffset="5" a="3.5" b="0" c="0" d="0"/>'),
    ]:
        ref road = map.roads[0]
        var lane = road.sections[0].lane_index(LaneId(-1))
        assert_false(Bool(_rounded_arc_context(road, 0, lane, 0.01, 0.02)))
        _contains(map, 0.01, 0.02)
    # In particular, a quadratic width has derivative zero at s=0.
    # That isolated fact must never authorize a constant-geometry proof.
    var varying = _map(width='a="3.5" b="0" c="0.01" d="0"')
    var lane = varying.roads[0].sections[0].lane_index(LaneId(-1))
    assert_false(
        Bool(_rounded_arc_context(varying.roads[0], 0, lane, 0.0, 0.0))
    )


def test_review_arc_offroad_query_and_nearest_station() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    var query = Vector3(80.0, bitcast[DType.float32](UInt32(0x415599A0)), 0.0)
    assert_false(Bool(map.waypoint(query)))
    var nearest = map.closest_waypoint_on_road(query).value()
    assert_equal(nearest.road_id, RoadId(11))
    assert_equal(nearest.lane_id, LaneId(-1))
    # Independent circle: atan2(q.x-60, 20-q.y) / stored(0.05).
    assert_almost_equal(nearest.s, 24.995924691997295, atol=1e-4)
    var pose = map.compute_transform(nearest)
    assert_almost_equal(Float64(pose.location.x), 77.31779634858378, atol=1e-4)
    assert_almost_equal(Float64(pose.location.y), 14.24183799906792, atol=1e-4)


def test_query_local_frozen_model_keeps_matching_expansion() raises:
    var map = _map()
    ref road = map.roads[0]
    var lane = road.sections[0].lane_index(LaneId(-1))
    var proof = _frozen_arc_context(road, 0, lane, 24.75, 25.0)
    assert_true(Bool(proof))
    var model = proof.value()
    var station = 24.995924691997295
    var query = Vector3(80.0, bitcast[DType.float32](UInt32(0x415599A0)), 0.0)
    var world = _frozen_arc_center(model, station, station, Vector3(0, 0, 0))
    var relative = _frozen_arc_center(model, station, station, query)
    var actual = road._lane_center(0, lane, station)
    var observed: Array[Float64, 3] = [
        actual[0] - Float64(query.x),
        -actual[1] + Float64(query.y),
        actual[2] - Float64(query.z),
    ]
    var enclosure_0 = relative[0].value + _Interval(
        -world[0].error, world[0].error
    )
    assert_true(enclosure_0.contains(observed[0]))
    var enclosure_1 = relative[1].value + _Interval(
        -world[1].error, world[1].error
    )
    assert_true(enclosure_1.contains(observed[1]))
    var enclosure_2 = relative[2].value + _Interval(
        -world[2].error, world[2].error
    )
    assert_true(enclosure_2.contains(observed[2]))
    var expansion = _frozen_arc_expansion(model, station, query, 2.0)
    assert_true(expansion.value.is_finite())
    assert_true(expansion.first.is_finite())
    assert_true(expansion.second.is_finite())
    assert_false(isfinite(expansion.error))
    assert_false(Bool(_frozen_arc_context(road, 0, lane, 0.0, 0.0)))
    assert_false(Bool(_frozen_arc_context(road, 0, lane, 29.0, 30.0)))
    var unknown = _frozen_arc_center(model, 0.0, 0.0, Vector3(0, 0, 0))
    assert_false(isfinite(unknown[0].error))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
