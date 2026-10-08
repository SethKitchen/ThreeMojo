# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Retained producer singleton contract and original frozen-context parity."""

from extensions.carla.curve_frozen_arc import _frozen_arc_context
from extensions.carla.curve_rounded_arc import (
    _RoundedArc,
    _RoundedBox,
    _rounded_arc_context,
)
from extensions.carla.road import Road
from std.math import inf, nan
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from tests.test_carla_proof_guard_controls import _proof_road


def _reference_frozen_arc_context(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
) raises -> Optional[_RoundedArc]:
    # Its caller MUST reserve the optional validation work before entry.
    # These are structural record checks, never a zero-derivative inference.
    var found = _rounded_arc_context(road, section, lane, low, high)
    if not found:
        return None
    var model = found.value()
    for coefficient in [
        model.start,
        model.curvature,
        model.speed,
        model.x,
        model.y,
        model.z,
    ]:
        if not coefficient.known or coefficient.low != coefficient.high:
            return None
    var distance = _RoundedBox.bounds(low, high) - model.start
    # Keep one smooth interior clamp branch throughout the original domain.
    if (
        not distance.known
        or distance.low <= 0.0
        or distance.high >= model.length
    ):
        return None
    return model


def _same_context(road: Road, low: Float64, high: Float64) raises:
    var expected = _reference_frozen_arc_context(road, 0, 0, low, high)
    var actual = _frozen_arc_context(road, 0, 0, low, high)
    assert_equal(Bool(expected), Bool(actual))
    if actual:
        var before = expected.value()
        var after = actual.value()
        assert_equal(before.length, after.length)
        var old_fields = [
            before.start,
            before.curvature,
            before.speed,
            before.x,
            before.y,
            before.z,
        ]
        var new_fields = [
            after.start,
            after.curvature,
            after.speed,
            after.x,
            after.y,
            after.z,
        ]
        for i in range(6):
            assert_true(new_fields[i].known)
            assert_equal(new_fields[i].low, new_fields[i].high)
            assert_equal(old_fields[i].known, new_fields[i].known)
            assert_equal(old_fields[i].low, new_fields[i].low)
            assert_equal(old_fields[i].high, new_fields[i].high)


def test_producer_contract_and_frozen_context_match_original() raises:
    var small = bitcast[DType.float64](UInt64(623) << 52)
    var large = bitcast[DType.float64](UInt64(1423) << 52)
    for curvature in [small, Float64(0.125), -0.125, 1.0, large]:
        for width in [
            Float64(0),
            2.0,
            -2.0,
            large,
            inf[DType.float64](),
            nan[DType.float64](),
        ]:
            var road = _proof_road()
            road.info.geometries[0].geometry.curvature_start = curvature
            road.sections[0].lanes[0].info.widths[0].polynomial.a = width
            for low in [Float64(0), 1.0, 9.0, 10.0]:
                _same_context(road, low, low + 1.0)
            _same_context(road, 1.0, 1.0)


def test_interior_clamp_and_late_distance_guards_remain() raises:
    var road = _proof_road()
    assert_true(Bool(_frozen_arc_context(road, 0, 0, 1.0, 2.0)))
    for low in [Float64(0), 9.0, 10.0]:
        _same_context(road, low, low + 1.0)
        assert_false(Bool(_frozen_arc_context(road, 0, 0, low, low + 1.0)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
