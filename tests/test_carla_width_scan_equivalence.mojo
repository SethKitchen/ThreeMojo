# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Stored-word and refusal correspondence for the allocation-free lane scan."""

from extensions.carla.road import Road
from extensions.carla.road_info import (
    LaneId,
    RoadId,
    SectionId,
    NO_JUNCTION,
    RoadInfoLaneWidth,
    info_at,
)
from extensions.carla.polynomial import CubicPolynomial
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_raises


def _legacy_total_width(
    road: Road, section: Int, s: Float64, lane_id: LaneId
) raises -> Tuple[Float64, Float64]:
    # `ComputeTotalLaneWidth`: the offset of the lane's center from
    # lane 0 and its rate of change. Plus is to the right.
    ref lanes = road.sections[section].lanes
    var negative = lane_id.value < 0
    var order = List[Int]()
    if negative:
        # The section holds the lane, so it has lanes.
        for i in range(len(lanes) - 1, -1, -1):  # pragma: no branch
            if lanes[i].id.value < 0:
                order.append(i)
    else:
        # The section holds the lane, so it has lanes.
        for i in range(len(lanes)):  # pragma: no branch
            if lanes[i].id.value >= 1:
                order.append(i)
    var dist = 0.0
    var tangent = 0.0
    var sign = 1.0 if negative else -1.0
    # The order holds the lane itself, so the loop breaks.
    for i in order:  # pragma: no branch
        var width = info_at(lanes[i].info.widths, s)
        if not Bool(width):
            raise Error("A lane has no width record at s")
        var w = width.value().polynomial.evaluate(s)
        var t = width.value().polynomial.tangent(s)
        if lanes[i].id != lane_id:
            dist += sign * w
            tangent += sign * t
        else:
            dist += sign * w * 0.5
            tangent += sign * t * 0.5
            break
    return (dist, tangent)


def _width_road() raises -> Road:
    var road = Road(
        RoadId(1), "width", 10.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = road.add_section(SectionId(0), 0.0)
    for id in [3, -1, 0, -3, 1, -2, 2]:
        _ = road.sections[0].add_lane(LaneId(id))
    for i in range(len(road.sections[0].lanes)):
        road.sections[0].lanes[i].info.widths.append(
            RoadInfoLaneWidth(
                0.0,
                CubicPolynomial(
                    Float64(i) * 0.1,
                    Float64(i) * -0.2,
                    0.00001,
                    -0.00000001,
                    0.0,
                ),
            )
        )
    return road^


def test_all_lane_orders_match_legacy_stored_words() raises:
    var road = _width_road()
    for station in [0.0, 0.125, 1.0, 8.0, 10.0]:
        for id in [-4, -3, -2, -1, 0, 1, 2, 3, 4]:
            var before = _legacy_total_width(road, 0, station, LaneId(id))
            var after = road._total_width(0, station, LaneId(id))
            assert_equal(
                bitcast[DType.uint64](before[0]),
                bitcast[DType.uint64](after[0]),
            )
            assert_equal(
                bitcast[DType.uint64](before[1]),
                bitcast[DType.uint64](after[1]),
            )


def test_cancellation_and_signed_zero_match_legacy_words() raises:
    var road = _width_road()
    for scale in [0.0, -0.0, 1e-200, 1e20]:
        for i in range(len(road.sections[0].lanes)):
            road.sections[0].lanes[i].info.widths[
                0
            ].polynomial = CubicPolynomial.constant(
                scale * (-1.0 if i % 2 else 1.0)
            )
        for id in [-3, -2, -1, 0, 1, 2, 3]:
            var before = _legacy_total_width(road, 0, 1.0, LaneId(id))
            var after = road._total_width(0, 1.0, LaneId(id))
            assert_equal(
                bitcast[DType.uint64](before[0]),
                bitcast[DType.uint64](after[0]),
            )
            assert_equal(
                bitcast[DType.uint64](before[1]),
                bitcast[DType.uint64](after[1]),
            )


def test_missing_inner_width_preserves_refusal_and_early_break() raises:
    var road = _width_road()
    var inner = road.sections[0].lane_index(LaneId(-1))
    _ = road.sections[0].lanes[inner].info.widths.pop()
    for id in [-3, -2, -1]:
        with assert_raises(contains="A lane has no width record at s"):
            _ = _legacy_total_width(road, 0, 1.0, LaneId(id))
        with assert_raises(contains="A lane has no width record at s"):
            _ = road._total_width(0, 1.0, LaneId(id))
    # A missing outer lane must not be evaluated after an inner target.
    road = _width_road()
    var outer = road.sections[0].lane_index(LaneId(-3))
    _ = road.sections[0].lanes[outer].info.widths.pop()
    var before = _legacy_total_width(road, 0, 1.0, LaneId(-1))
    var after = road._total_width(0, 1.0, LaneId(-1))
    assert_equal(
        bitcast[DType.uint64](before[0]), bitcast[DType.uint64](after[0])
    )
    assert_equal(
        bitcast[DType.uint64](before[1]), bitcast[DType.uint64](after[1])
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
