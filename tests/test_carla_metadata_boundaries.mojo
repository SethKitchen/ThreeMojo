# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Numeric metadata and conservative lane-distance boundary controls."""

from extensions.carla.lane_distance import (
    _normalized_square,
    _refinement_square,
)
from extensions.carla.opendrive import load_opendrive
from extensions.carla.road_info import RoadId, RoadInfoSpeed, SignalId
from extensions.carla.speed_limits import read_speed_number
from extensions.carla.traffic_sign import give_way_boxes
from std.math import isfinite
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_carla_cross_candidate_certificates import _road
from tests.test_carla_world_signals import _edge


def test_zero_speed_exponents_remain_numeric_zero() raises:
    # Exponent digits must not be mistaken for a nonzero mantissa.
    for token in ["0e3", "0E3", "+0.000e-1000", "-0.0E+1000", " 0.00 "]:
        assert_equal(read_speed_number(token), Float64(0))
    for token in ["1e-1000", "0.0001E-1000"]:
        with assert_raises(contains="underflows Float64"):
            _ = read_speed_number(token)


def test_missing_geometry_refuses_internal_canonical_center() raises:
    # Internal query callers use this Float64 helper before public narrowing.
    var road = _road()
    assert_equal(road._lane_center(0, 0, 1.0)[0], Float64(1))
    road.info.geometries[0].s = 2.0
    with assert_raises(contains="no geometry at that s"):
        _ = road._lane_center(0, 0, 1.0)
    road.info.geometries.clear()
    with assert_raises(contains="no geometry at that s"):
        _ = road._offset_lane_point(1.0, 0.0)


def test_unbounded_refinement_upper_keeps_original_distance_interval() raises:
    # All coordinates are finite. Their residual exceeds Float64 range, so
    # the optional residual calculation must preserve the original bound.
    var largest = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    var point: Array[Float64, 3] = [largest, 0.0, 0.0]
    var query: Array[Float64, 3] = [-largest, 0.0, 0.0]
    var original = _normalized_square[3](point, query, 1.0)
    var result = _refinement_square[3](point, query, 1.0)
    assert_false(isfinite(original.high))
    assert_false(isfinite(result.high))
    assert_equal(result.low, original.low)
    assert_equal(result.high, original.high)
    var same: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var finite = _refinement_square[3](same, same, 1.0)
    assert_true(finite.is_finite())
    assert_equal(finite.low, Float64(0))
    assert_equal(finite.high, Float64(0))


def test_zero_approach_speed_stops_anticipation_after_first_box() raises:
    # Extend the existing connected predecessor to leave room for several
    # anticipation steps, without changing either crossing junction lane.
    var xml = (
        _edge()
        .replace(
            '<road name="feeder" length="5" id="34"',
            '<road name="feeder" length="20" id="34"',
        )
        .replace(
            'x="-15" y="5" hdg="0" length="5"',
            'x="-30" y="5" hdg="0" length="20"',
        )
    )
    var map = load_opendrive(xml)
    var moving = give_way_boxes(map, SignalId("3101"))
    # At 40 m/s, each 1.575 m cube consumes 0.039375 s of the 0.1 s
    # horizon. Three predecessor cubes fit before that horizon is spent.
    assert_equal(len(moving.check), 17)
    var changed = False
    for i in range(len(map.roads)):
        if map.roads[i].id == RoadId(34):
            map.roads[i].info.speeds.clear()
            map.roads[i].info.speeds.append(
                RoadInfoSpeed.from_opendrive(0, "0", "town", "m/s", True)
            )
            changed = True
    assert_true(changed)
    var stopped = give_way_boxes(map, SignalId("3101"))
    # The seven cubes on each crossing road remain; only the first cube
    # on the zero-speed predecessor is needed, with no division by zero.
    assert_equal(len(stopped.check), 15)
    assert_equal(len(stopped.effect), len(moving.effect))
    for i in range(8):
        var one = stopped.check[i].transform.location
        var two = moving.check[i].transform.location
        assert_equal(one.x, two.x)
        assert_equal(one.y, two.y)
        assert_equal(one.z, two.z)
    for i in range(8, 15):
        var one = stopped.check[i].transform.location
        var two = moving.check[i + 2].transform.location
        assert_equal(one.x, two.x)
        assert_equal(one.y, two.y)
        assert_equal(one.z, two.z)
    assert_almost_equal(
        stopped.check[7].transform.location.x, Float32(-13.15), atol=1e-4
    )
    assert_almost_equal(
        stopped.check[7].transform.location.y, Float32(-3.25), atol=1e-4
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
