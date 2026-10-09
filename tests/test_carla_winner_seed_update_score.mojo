# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Numerical boundary controls for an optional winner-seed score update.

These stored-point cases do not establish admission through a SPIRAL lane.
The caller supplies the checked floating-point environment and a positive,
finite scale produced from the incumbent's actual point gap.
"""

from extensions.carla.map import _winner_seed_update_score
from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.curve_sum2 import _require_sum2_environment
from extensions.carla.lane_distance import _point_gap_scale, _refinement_square
from std.math import inf, isfinite
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _assert_finite_point(point: Array[Float64, 3]) raises:
    for axis in range(3):
        assert_true(isfinite(point[axis]))


def test_strict_improvement_returns_the_same_refinement_upper_bits() raises:
    _require_sum2_environment()
    var point: Array[Float64, 3] = [3.0, 1.0, -1.0]
    var incumbent: Array[Float64, 3] = [8.0, 6.0, 0.0]
    var query: Array[Float64, 3] = [1.0, -2.0, 3.0]
    var scale = _point_gap_scale(incumbent, query)
    assert_true(isfinite(scale))
    assert_true(scale > 0.0)
    assert_true(_refinement_square[3](incumbent, query, scale).is_finite())
    assert_true(_wide_point_order(point, incumbent, query) < 0)
    var expected = _refinement_square[3](point, query, scale)
    assert_true(expected.is_finite())
    var result = _winner_seed_update_score(point, incumbent, query, scale)
    assert_true(result[0])
    assert_equal(
        bitcast[DType.uint64](result[1]),
        bitcast[DType.uint64](expected.high),
    )


def test_identical_points_do_not_update_the_score() raises:
    _require_sum2_environment()
    var incumbent: Array[Float64, 3] = [4.0, 2.0, 3.0]
    var query: Array[Float64, 3] = [1.0, -2.0, 3.0]
    var scale = _point_gap_scale(incumbent, query)
    assert_true(isfinite(scale))
    assert_true(scale > 0.0)
    assert_equal(_wide_point_order(incumbent, incumbent, query), 0)
    var result = _winner_seed_update_score(incumbent, incumbent, query, scale)
    assert_false(result[0])


def test_distinct_equal_distance_points_do_not_update_the_score() raises:
    _require_sum2_environment()
    var point: Array[Float64, 3] = [1.0, -2.0, 8.0]
    var incumbent: Array[Float64, 3] = [4.0, 2.0, 3.0]
    var query: Array[Float64, 3] = [1.0, -2.0, 3.0]
    var scale = _point_gap_scale(incumbent, query)
    assert_true(isfinite(scale))
    assert_true(scale > 0.0)
    assert_true(point[0] != incumbent[0])
    assert_equal(_wide_point_order(point, incumbent, query), 0)
    var result = _winner_seed_update_score(point, incumbent, query, scale)
    assert_false(result[0])


def test_worse_point_does_not_update_the_score() raises:
    _require_sum2_environment()
    var point: Array[Float64, 3] = [4.0, 2.0, 4.0]
    var incumbent: Array[Float64, 3] = [4.0, 2.0, 3.0]
    var query: Array[Float64, 3] = [1.0, -2.0, 3.0]
    var scale = _point_gap_scale(incumbent, query)
    assert_true(isfinite(scale))
    assert_true(scale > 0.0)
    assert_true(_wide_point_order(point, incumbent, query) > 0)
    assert_true(_refinement_square[3](point, query, scale).is_finite())
    var result = _winner_seed_update_score(point, incumbent, query, scale)
    assert_false(result[0])


def test_finite_strict_improvement_with_nonfinite_score_is_refused() raises:
    _require_sum2_environment()
    var maximum = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    var a = bitcast[DType.float64](UInt64(0x7FE7FFFFFFFFFFFF))
    var point: Array[Float64, 3] = [maximum, 0.0, 0.0]
    var incumbent: Array[Float64, 3] = [a, a, 0.0]
    var query: Array[Float64, 3] = [-1.0, 0.0, 0.0]
    _assert_finite_point(point)
    _assert_finite_point(incumbent)
    _assert_finite_point(query)
    var scale = _point_gap_scale(incumbent, query)
    assert_true(isfinite(scale))
    assert_true(scale > 0.0)
    assert_equal(bitcast[DType.uint64](scale), UInt64(0x7FE0000000000000))
    assert_true(_refinement_square[3](incumbent, query, scale).is_finite())
    assert_true(_wide_point_order(point, incumbent, query) < 0)
    var score = _refinement_square[3](point, query, scale)
    assert_false(score.is_finite())
    var result = _winner_seed_update_score(point, incumbent, query, scale)
    assert_false(result[0])


def test_adjacent_finite_candidate_keeps_the_refinement_upper_bits() raises:
    _require_sum2_environment()
    # The immediate predecessor keeps the outward point-gap endpoint finite.
    var adjacent = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFE))
    var a = bitcast[DType.float64](UInt64(0x7FE7FFFFFFFFFFFF))
    var point: Array[Float64, 3] = [adjacent, 0.0, 0.0]
    var incumbent: Array[Float64, 3] = [a, a, 0.0]
    var query: Array[Float64, 3] = [-1.0, 0.0, 0.0]
    _assert_finite_point(point)
    _assert_finite_point(incumbent)
    _assert_finite_point(query)
    var scale = _point_gap_scale(incumbent, query)
    assert_true(isfinite(scale))
    assert_true(scale > 0.0)
    assert_equal(bitcast[DType.uint64](scale), UInt64(0x7FE0000000000000))
    assert_true(_refinement_square[3](incumbent, query, scale).is_finite())
    assert_true(_wide_point_order(point, incumbent, query) < 0)
    var expected = _refinement_square[3](point, query, scale)
    assert_true(expected.is_finite())
    var result = _winner_seed_update_score(point, incumbent, query, scale)
    assert_true(result[0])
    assert_equal(
        bitcast[DType.uint64](result[1]),
        bitcast[DType.uint64](expected.high),
    )


def test_nonfinite_input_errors_propagate_for_each_point_and_axis() raises:
    _require_sum2_environment()
    var point: Array[Float64, 3] = [3.0, 1.0, -1.0]
    var incumbent: Array[Float64, 3] = [8.0, 6.0, 0.0]
    var query: Array[Float64, 3] = [1.0, -2.0, 3.0]
    var scale = _point_gap_scale(incumbent, query)
    assert_true(isfinite(scale))
    assert_true(scale > 0.0)
    for invalid in [
        inf[DType.float64](),
        -inf[DType.float64](),
        bitcast[DType.float64](UInt64(0x7FF8000000000001)),
    ]:
        for axis in range(3):
            var invalid_point = point.copy()
            invalid_point[axis] = invalid
            with assert_raises(contains="finite coordinates"):
                _ = _winner_seed_update_score(
                    invalid_point, incumbent, query, scale
                )
            var invalid_incumbent = incumbent.copy()
            invalid_incumbent[axis] = invalid
            with assert_raises(contains="finite coordinates"):
                _ = _winner_seed_update_score(
                    point, invalid_incumbent, query, scale
                )
            var invalid_query = query.copy()
            invalid_query[axis] = invalid
            with assert_raises(contains="finite coordinates"):
                _ = _winner_seed_update_score(
                    point, incumbent, invalid_query, scale
                )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
