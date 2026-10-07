# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Controls for local rounding bounds and equivalent ideal sample blends."""

from extensions.carla.curve_bounds import (
    _sample_blend_jet,
    _intersect_ideal_bounds,
)
from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _roundoff,
    _stored_blend_error,
)
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.road_info import RoadId, LaneId
from math.vector3 import Vector3
from std.math import fma, inf
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true
from tests.test_carla_stored_arithmetic import _product, _sum, _complement


def test_half_spacing_at_binade_and_subnormal_boundaries() raises:
    var cases: List[Array[UInt64, 2]] = [
        [0, 1],
        [1, 1],
        [UInt64(0x000FFFFFFFFFFFFF), 1],
        [UInt64(0x0010000000000000), 1],
        [UInt64(0x001FFFFFFFFFFFFF), 1],
        [UInt64(0x0020000000000000), 1],
        [UInt64(0x0030000000000000), 2],
        [UInt64(0x0350000000000000), UInt64(0x0008000000000000)],
        [UInt64(0x0360000000000000), UInt64(0x0010000000000000)],
        [UInt64(0x3FEFFFFFFFFFFFFF), UInt64(0x3C90000000000000)],
        [UInt64(0x3FF0000000000000), UInt64(0x3CA0000000000000)],
        [UInt64(0x7FEFFFFFFFFFFFFF), UInt64(0x7C90000000000000)],
    ]
    for i in range(len(cases)):
        assert_equal(
            bitcast[DType.uint64](
                _roundoff(bitcast[DType.float64](cases[i][0]))
            ),
            cases[i][1] + UInt64(1),
        )
    assert_equal(_roundoff(-1.0), inf[DType.float64]())
    assert_equal(_roundoff(inf[DType.float64]()), inf[DType.float64]())
    assert_equal(
        _roundoff(bitcast[DType.float64](UInt64(0x7FF8000000000001))),
        inf[DType.float64](),
    )


def test_blend_ideal_rewrite_keeps_the_reviewed_scalar_error() raises:
    var samples: List[Array[Float64, 3]] = [
        [0.25, 100.0, 101.0],
        [0.1, 10000000000000000.0, 10000000000000002.0],
        [0.9999999999999999, -5.1, -5.2],
        [-2.0, 1.0, 3.0],
        [3.0, -1.0, 2.0],
        [0.5, 1e308, -1e308],
        [0.3, 1e-308, -1e-308],
    ]
    # Exact words derived by test_sample_blend_migration.py. The coupled
    # candidate is wider for row 3 and two ULPs tighter only for row 4.
    # Rows 5 and 6 retain the original unsupported-range fallback.
    var coupled_error_words: List[UInt64] = [
        UInt64(0x3D18500000000005),
        UInt64(0x4000F0DE4DF82003),
        UInt64(0x3CD0000000000003),
        UInt64(0x3CE8000000000005),
        UInt64(0x3CDC000000000005),
        UInt64(0x7FF0000000000000),
        UInt64(0x7FF0000000000000),
    ]
    var expected_error_words: List[UInt64] = [
        UInt64(0x3D18500000000005),
        UInt64(0x4000F0DE4DF82003),
        UInt64(0x3CD0000000000003),
        UInt64(0x3CE2000000000004),
        UInt64(0x3CDC000000000005),
        UInt64(0x7C98E679C2F5E457),
        UInt64(0x000000000000000B),
    ]
    var required_error_words: List[UInt64] = [
        UInt64(0x0000000000000000),
        UInt64(0x3FC999999999999A),
        UInt64(0x3C699999999999C0),
        UInt64(0x0000000000000000),
        UInt64(0x0000000000000000),
        UInt64(0x0000000000000000),
        UInt64(0x0000000000000001),
    ]
    # Separate, left-FMA, and right-FMA graphs share these words for the
    # seven original rows. Other contraction-sensitive rows stay in the
    # existing stored-arithmetic suite.
    var graph_words: List[UInt64] = [
        UInt64(0x4059300000000000),
        UInt64(0x4341C37937E08001),
        UInt64(0xC014666666666666),
        UInt64(0x401C000000000000),
        UInt64(0xC01C000000000000),
        UInt64(0x0000000000000000),
        UInt64(0x8002E055C9A3F6BA),
    ]
    for i in range(len(samples)):
        var r = samples[i][0]
        var one = samples[i][1]
        var two = samples[i][2]
        var rate = _Jet.variable(r, r)
        var original = rate * _Jet.constant(one) + (
            _Jet.constant(1.0) - rate
        ) * _Jet.constant(two)
        var result = _sample_blend_jet(rate, one, two)
        var coupled = _stored_blend_error(rate, one, two)
        assert_equal(bitcast[DType.uint64](coupled), coupled_error_words[i])
        assert_equal(
            bitcast[DType.uint64](result.error), expected_error_words[i]
        )
        if i == 4:
            assert_equal(
                bitcast[DType.uint64](original.error),
                UInt64(0x3CDC000000000007),
            )
        else:
            # Includes exact original equality on both unsupported rows,
            # and row 3 where the coupled candidate must not widen error.
            assert_equal(result.error, original.error)
        assert_equal(
            result.error,
            min(original.error, bitcast[DType.float64](coupled_error_words[i])),
        )
        assert_true(
            result.error >= bitcast[DType.float64](required_error_words[i])
        )
        var executed = r * one + (1.0 - r) * two
        assert_true(result.rounded_value().contains(executed))
        var complement = _complement(r)
        var first = _product(r, one)
        var second = _product(complement, two)
        for actual in [
            _sum(first, second),
            fma(r, one, second),
            fma(complement, two, first),
        ]:
            assert_equal(bitcast[DType.uint64](actual), graph_words[i])
            assert_true(result.rounded_value().contains(actual))
    var simple = _sample_blend_jet(_Jet.variable(0.25, 0.25), 100.0, 101.0)
    assert_true(simple.value.contains(100.75))
    assert_true(simple.first.contains(-1.0))
    assert_true(simple.second.contains(0.0))
    var rate = _Jet.variable(0.1, 0.2)
    var curved = _sample_blend_jet(rate * rate, 1.0, 3.0)
    assert_true(curved.first.contains(-0.4))
    assert_true(curved.first.contains(-0.8))
    assert_true(curved.second.contains(-4.0))


def test_ideal_intersection_retains_finite_original_on_rewrite_overflow() raises:
    var limit = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    var result = _sample_blend_jet(_Jet.variable(0.5, 0.5), -limit, limit)
    assert_true(result.value.is_finite())
    assert_true(result.rounded_value().contains(0.0))
    var overlap = _intersect_ideal_bounds(_Interval(-2, 1), _Interval(0, 3))
    assert_equal(overlap.low, 0.0)
    assert_equal(overlap.high, 1.0)
    var unknown = _intersect_ideal_bounds(_Interval(0, 1), _Interval(2, 3))
    assert_true(unknown.contains(-inf[DType.float64]()))
    assert_true(unknown.contains(inf[DType.float64]()))


def test_sampled_town_query_resolves_without_larger_work_or_accuracy_limits() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    var query = Vector3(
        bitcast[DType.float32](UInt32(1105004517)),
        bitcast[DType.float32](UInt32(3268476412)),
        bitcast[DType.float32](UInt32(1069720068)),
    )
    var result = map.closest_waypoint_on_road(query).value()
    assert_equal(result.road_id, RoadId(5))
    assert_equal(result.lane_id, LaneId(-1))
    assert_true(result.s > 25.70937704009046)
    assert_true(result.s < 26.010769545919583)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
