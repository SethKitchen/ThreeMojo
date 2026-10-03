# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Direct controls for a heuristic seed, never a nearest-point certificate."""
from extensions.carla.map import (
    _projected_seed,
    _has_uniform_plan_classification,
    _use_projected_spiral_seed,
)
from extensions.carla.curve_interval import _Interval
from extensions.carla.geometry import ARC, SPIRAL, RoadGeometry, with_spiral
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import RoadInfoLaneWidth
from tests.test_carla_curve_bounds import _road
from math.vector3 import Vector3
from std.math import inf, isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true, assert_false


def test_projection_uses_all_three_coordinates() raises:
    assert_equal(
        _projected_seed(
            Vector3(0, 0, 0), Vector3(8, 0, 0), 10, 18, Vector3(2, 9, 7)
        ),
        12.0,
    )
    assert_equal(
        _projected_seed(
            Vector3(0, 0, 0), Vector3(2, 4, 4), 10, 18, Vector3(1, 2, 2)
        ),
        14.0,
    )
    assert_equal(
        _projected_seed(
            Vector3(0, 0, 0), Vector3(0, 0, 8), 10, 18, Vector3(2, 9, 2)
        ),
        12.0,
    )


def test_reversed_parameter_and_chord_direction() raises:
    assert_equal(
        _projected_seed(
            Vector3(8, 0, 0), Vector3(0, 0, 0), 18, 10, Vector3(2, 9, 7)
        ),
        12.0,
    )
    assert_equal(
        _projected_seed(
            Vector3(0, 0, 0), Vector3(8, 0, 0), 18, 10, Vector3(2, 9, 7)
        ),
        16.0,
    )


def test_projection_clamps_both_ends() raises:
    assert_equal(
        _projected_seed(
            Vector3(0, 0, 0), Vector3(8, 0, 0), 10, 18, Vector3(-2, 3, 4)
        ),
        10.0,
    )
    assert_equal(
        _projected_seed(
            Vector3(0, 0, 0), Vector3(8, 0, 0), 10, 18, Vector3(10, 3, 4)
        ),
        18.0,
    )


def test_collapsed_chord_uses_midpoint_without_coincidence_assumption() raises:
    assert_equal(
        _projected_seed(
            Vector3(1, 2, 3), Vector3(1, 2, 3), 2, 10, Vector3(9, 8, 7)
        ),
        6.0,
    )
    assert_equal(
        _projected_seed(
            Vector3(1, 2, 3), Vector3(1, 2, 3), 10, 2, Vector3(1, 2, 3)
        ),
        6.0,
    )
    assert_equal(
        _projected_seed(
            Vector3(0, 0, 0), Vector3(8, 0, 0), 7, 7, Vector3(2, 9, 7)
        ),
        7.0,
    )


def test_finite_float32_extremes_and_subnormal_chords() raises:
    var largest = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    var tiny = bitcast[DType.float32](UInt32(1))
    assert_equal(
        _projected_seed(
            Vector3(-largest, 0, 0),
            Vector3(largest, 0, 0),
            0,
            1,
            Vector3(0, 0, 0),
        ),
        0.5,
    )
    assert_equal(
        _projected_seed(
            Vector3(0, 0, 0), Vector3(tiny, 0, 0), 2, 10, Vector3(tiny, 0, 0)
        ),
        10.0,
    )
    assert_equal(
        _projected_seed(
            Vector3(-tiny, 0, 0), Vector3(tiny, 0, 0), 2, 10, Vector3(0, 0, 0)
        ),
        6.0,
    )


def test_unsupported_chord_or_query_arithmetic_keeps_midpoint() raises:
    var infinity = inf[DType.float32]()
    var nan = bitcast[DType.float32](UInt32(0x7FC00001))
    assert_equal(
        _projected_seed(
            Vector3(0, 0, 0), Vector3(infinity, 0, 0), 2, 10, Vector3(1, 0, 0)
        ),
        6.0,
    )
    assert_equal(
        _projected_seed(
            Vector3(0, 0, 0), Vector3(nan, 0, 0), 2, 10, Vector3(1, 0, 0)
        ),
        6.0,
    )
    assert_equal(
        _projected_seed(
            Vector3(0, 0, 0), Vector3(8, 0, 0), 2, 10, Vector3(infinity, 0, 0)
        ),
        6.0,
    )
    assert_equal(
        _projected_seed(
            Vector3(0, 0, 0), Vector3(8, 0, 0), 2, 10, Vector3(nan, 0, 0)
        ),
        6.0,
    )


def test_parameter_overflow_uses_safe_midpoint() raises:
    var largest = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    var seed = _projected_seed(
        Vector3(0, 0, 0), Vector3(8, 0, 0), -largest, largest, Vector3(4, 0, 0)
    )
    assert_true(isfinite(seed))
    assert_equal(seed, 0.0)
    assert_equal(
        _projected_seed(
            Vector3(0, 0, 0),
            Vector3(8, 0, 0),
            largest,
            -largest,
            Vector3(4, 0, 0),
        ),
        0.0,
    )


def test_translated_parameter_rounding_stays_in_closed_span() raises:
    var first = bitcast[DType.float64](UInt64(0x4415AF1D78B58C40))
    var second = bitcast[DType.float64](UInt64(0x4415AF1D78B58C41))
    var seed = _projected_seed(
        Vector3(0, 0, 0), Vector3(8, 0, 0), first, second, Vector3(4, 0, 0)
    )
    assert_true(isfinite(seed))
    assert_true(seed >= first and seed <= second)
    assert_equal(bitcast[DType.uint64](seed), UInt64(0x4415AF1D78B58C40))


def test_uniform_plan_gate_keeps_strict_ambiguous_boundaries() raises:
    var zero = _Interval.point(0.0)
    var query = Vector3(0, 0, 0)
    assert_true(
        _has_uniform_plan_classification(
            (_Interval(-0.125, 0.125), _Interval(-0.125, 0.125), zero),
            1.0,
            query,
        )
    )
    assert_true(
        _has_uniform_plan_classification(
            (_Interval(2.0, 3.0), zero, zero), 1.0, query
        )
    )
    assert_false(
        _has_uniform_plan_classification(
            (_Interval(0.0, 0.5), zero, zero), 1.0, query
        )
    )
    assert_false(
        _has_uniform_plan_classification(
            (_Interval.point(0.5), zero, zero), 1.0, query
        )
    )
    assert_false(
        _has_uniform_plan_classification((zero, zero, zero), 0.0, query)
    )
    assert_false(
        _has_uniform_plan_classification((zero, zero, zero), -1.0, query)
    )
    var tiny = bitcast[DType.float64](UInt64(1))
    assert_true(
        _has_uniform_plan_classification((zero, zero, zero), tiny, query)
    )


def test_unknown_full_boxes_and_widths_keep_midpoint_eligibility() raises:
    var zero = _Interval.point(0.0)
    var whole = _Interval.whole()
    var query = Vector3(0, 0, 0)
    assert_false(
        _has_uniform_plan_classification((whole, zero, zero), 1.0, query)
    )
    assert_false(
        _has_uniform_plan_classification((zero, whole, zero), 1.0, query)
    )
    assert_false(
        _has_uniform_plan_classification((zero, zero, whole), 1.0, query)
    )
    assert_false(
        _has_uniform_plan_classification(
            (zero, zero, zero), inf[DType.float64](), query
        )
    )
    var largest = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    var maximum = _Interval.point(largest)
    var far = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    assert_false(
        _has_uniform_plan_classification(
            (maximum, zero, zero), 1.0, Vector3(-far, 0, 0)
        )
    )
    assert_false(
        _has_uniform_plan_classification(
            (zero, maximum, zero), 1.0, Vector3(0, -far, 0)
        )
    )


def test_seed_eligibility_preserves_arc_and_variable_width_paths() raises:
    var geometry = with_spiral(
        RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, 4.0), 0.01, 0.02
    )
    var road = _road(geometry^, width=4.0)
    var bounds = (
        _Interval(-0.1, 1.1),
        _Interval(1.9, 2.1),
        _Interval.point(0.0),
    )
    var query = Vector3(0.5, 2, 0)
    assert_true(_use_projected_spiral_seed(road, 0, 0, 0.1, 0.9, bounds, query))
    road.info.geometries[0].geometry.kind = ARC
    assert_false(
        _use_projected_spiral_seed(road, 0, 0, 0.1, 0.9, bounds, query)
    )
    road.info.geometries[0].geometry.kind = SPIRAL
    road.sections[0].lanes[0].info.widths[0].polynomial.b = 1e-100
    assert_false(
        _use_projected_spiral_seed(road, 0, 0, 0.1, 0.9, bounds, query)
    )
    road.sections[0].lanes[0].info.widths[0].polynomial.b = 0.0
    road.sections[0].lanes[0].info.widths[0].polynomial.c = 1e-100
    assert_false(
        _use_projected_spiral_seed(road, 0, 0, 0.1, 0.9, bounds, query)
    )
    road.sections[0].lanes[0].info.widths[0].polynomial.c = 0.0
    road.sections[0].lanes[0].info.widths[0].polynomial.d = 1e-100
    assert_false(
        _use_projected_spiral_seed(road, 0, 0, 0.1, 0.9, bounds, query)
    )
    road.sections[0].lanes[0].info.widths[0].polynomial.d = 0.0
    assert_false(
        _use_projected_spiral_seed(
            road, 0, 0, 0.1, 0.9, bounds, Vector3(0, 0, 0)
        )
    )
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(0.5, CubicPolynomial.constant(4.0))
    )
    assert_false(
        _use_projected_spiral_seed(road, 0, 0, 0.1, 0.9, bounds, query)
    )
    _ = road.sections[0].lanes[0].info.widths.pop()
    road.sections[0].lanes[0].info.widths[0].s = 0.5
    assert_false(
        _use_projected_spiral_seed(road, 0, 0, 0.1, 0.9, bounds, query)
    )
    road.sections[0].lanes[0].info.widths[0].s = 0.0
    var extra = road.info.geometries[0].copy()
    extra.s = 0.5
    road.info.geometries.append(extra^)
    assert_false(
        _use_projected_spiral_seed(road, 0, 0, 0.1, 0.9, bounds, query)
    )
    _ = road.info.geometries.pop()
    road.info.geometries[0].s = 0.5
    assert_false(
        _use_projected_spiral_seed(road, 0, 0, 0.1, 0.9, bounds, query)
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
