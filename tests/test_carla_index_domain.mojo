# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Required finite storage boundary for the segment-index key proof."""

from extensions.carla.geometry import LINE, RoadGeometry
from extensions.carla.map import Controller, Junction, Map, Signal
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    LANE_DRIVING,
    LaneId,
    NO_JUNCTION,
    RoadId,
    RoadInfoElevation,
    RoadInfoGeometry,
    RoadInfoLaneOffset,
    RoadInfoLaneWidth,
    SectionId,
)
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_raises


def _road_at_x(x: Float64) raises -> Road:
    var road = Road(
        RoadId(1), "finite index", 1.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(0.0, CubicPolynomial.constant(2.0))
    )
    road.info.geometries.append(
        RoadInfoGeometry(0.0, RoadGeometry(LINE, 0.0, x, 0.0, 0.0, 1.0))
    )
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial.constant(0.0))
    )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(0.0, CubicPolynomial.constant(0.0))
    )
    return road^


def test_nonfinite_query_is_rejected_before_even_an_empty_index() raises:
    var map = Map(
        List[Road](), List[Junction](), List[Signal](), List[Controller]()
    )
    assert_false(Bool(map.certified_closest_waypoint_on_road(Vector3(0, 0, 0))))
    with assert_raises(contains="finite coordinates"):
        _ = map.certified_closest_waypoint_on_road(
            Vector3(inf[DType.float32](), 0, 0)
        )
    with assert_raises(contains="finite coordinates"):
        _ = map.certified_closest_waypoint_on_road(
            Vector3(0, bitcast[DType.float32](UInt32(0x7FC00001)), 0)
        )


def test_unrepresentable_index_endpoint_is_explicit_error_not_clamping() raises:
    var roads = List[Road]()
    roads.append(_road_at_x(1e39))
    # The checked public transform rejects this before index insertion.
    with assert_raises(contains="not representable in its transform"):
        _ = Map(roads^, List[Junction](), List[Signal](), List[Controller]())


def test_nonfinite_stored_endpoints_are_refused_before_index_insertion() raises:
    for endpoint in range(2):
        var roads = List[Road]()
        roads.append(_road_at_x(0.0))
        var map = Map(
            roads^, List[Junction](), List[Signal](), List[Controller]()
        )
        var first = map.segment(0)[2]
        var second = map.segment(0)[3]
        var a = map.compute_transform(first)
        var b = map.compute_transform(second)
        if endpoint == 0:
            a.location.x = inf[DType.float32]()
        else:
            b.location.x = inf[DType.float32]()
        var count = map.segment_count()
        var admitted = map._construction_work.segments
        # Exercise both original finite-storage guards with the shared ledger.
        with assert_raises(contains="finite coordinates"):
            map._subdivide_segment(a, b, first, second, 0)
        assert_equal(map.segment_count(), count)
        assert_equal(map._construction_work.segments, admitted)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
