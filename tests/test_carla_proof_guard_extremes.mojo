# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Guarded arithmetic and malformed sample-selector refusal controls."""

from extensions.carla.curve_rounded_arc import (
    _RoundedBox,
    _rounded_arc_context,
)
from extensions.carla.curve_rounded_line import _rounded_line_axis_context
from extensions.carla.curve_sample_dispatch import _try_sample_dispatch_cuts
from extensions.carla.curve_interval import _next_up
from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.curve_minimizer_support import _minimizer_support
from extensions.carla.geometry import _Sample
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import LaneId, RoadInfoLaneWidth
from std.memory import bitcast
from std.math import inf
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from tests._sample_dispatch_controls import _dispatch_road
from tests.test_carla_proof_guard_controls import _proof_road


def test_inner_and_outer_width_sum_must_remain_guarded() raises:
    var largest = bitcast[DType.float64](UInt64(1423) << UInt64(52))
    for arc in [False, True]:
        var road = _proof_road(arc)
        var outer = road.sections[0].add_lane(LaneId(-2))
        road.sections[0].lanes[outer].info.widths.append(
            RoadInfoLaneWidth(0.0, CubicPolynomial.constant(largest))
        )
        var inner = road.sections[0].lane_index(LaneId(-1))
        road.sections[0].lanes[inner].info.widths[0].polynomial.a = largest
        # The first width is 2^400, and the selected half-width is 2^399.
        # Both inputs pass the operand guard; their sum must decline.
        if arc:
            assert_false(Bool(_rounded_arc_context(road, 0, outer, 1.0, 2.0)))
        else:
            assert_false(
                Bool(_rounded_line_axis_context(road, 0, outer, 1.0, 2.0))
            )


def test_radius_plus_offset_and_quadrant_crossing_decline() raises:
    var road = _proof_road()
    road.info.geometries[0].geometry.curvature_start = bitcast[DType.float64](
        UInt64(623) << UInt64(52)
    )
    var largest = bitcast[DType.float64](UInt64(1423) << UInt64(52))
    road.sections[0].lanes[0].info.widths[0].polynomial.a = largest
    assert_false(Bool(_rounded_arc_context(road, 0, 0, 1.0, 2.0)))
    road = _proof_road()
    var found = _rounded_arc_context(road, 0, 0, 1.0, 2.0)
    assert_true(Bool(found))
    var model = found.value()
    model.curvature = _RoundedBox.point(-1.0)
    # The half-angle range [-1,-0.5] crosses the quadrant selector's zero.
    assert_false(model.center(1.0, 2.0)[0].known)


def test_supported_arc_center_encloses_stored_lane_outputs() raises:
    var road = _proof_road()
    var found = _rounded_arc_context(road, 0, 0, 1.0, 2.0)
    assert_true(Bool(found))
    var bounds = found.value().center(1.0, 2.0)
    for station in [
        Float64(1.0),
        Float64(1.25),
        Float64(1.5),
        Float64(1.75),
        Float64(2.0),
    ]:
        var stored = road._lane_center(0, 0, station)
        for axis in range(3):
            assert_true(bounds[axis].known)
            assert_true(bounds[axis].low <= stored[axis])
            assert_true(stored[axis] <= bounds[axis].high)


def test_finite_decreasing_model_retains_worst_error_tie() raises:
    # F(s)=1-s and uniform stored-evaluator error 1/8. Relative to the
    # incumbent at s=1, an error tie remains possible at exactly s=3/4.
    var domain = _Jet(
        _Interval(0.0, 1.0),
        _Interval.point(-1.0),
        _Interval.point(0.0),
        0.125,
    )
    var center = _Jet(
        _Interval.point(0.5),
        _Interval.point(-1.0),
        _Interval.point(0.0),
        inf[DType.float64](),
    )
    var support = _minimizer_support(domain, center, 0.5, 1.0, 0.0, 1.0)
    assert_true(support.contains(0.75))
    assert_true(support.low > 0.74)
    assert_equal(support.high, 1.0)


def test_unordered_sample_thresholds_decline_after_reserved_attempt() raises:
    # Every fixture has a two-index endpoint jump. Malformed interior
    # thresholds must never authorize a cut outside its owner or a cut
    # whose predecessor and successor select the wrong sample segment.
    for values in [
        (Float64(3.0), Float64(0.25)),
        (Float64(1.5), Float64(0.25)),
        (Float64(1.0), Float64(0.25)),
    ]:
        var road = _dispatch_road()
        road.info.geometries[0].geometry.samples.clear()
        for s in [
            Float64(0.0),
            values[0],
            values[1],
            Float64(1.5),
            Float64(3.0),
        ]:
            road.info.geometries[0].geometry.samples.append(
                _Sample(s, 0.0, s, 1.0, 0.0)
            )
        var nodes = 7
        var terms = 11
        assert_false(
            Bool(
                _try_sample_dispatch_cuts(
                    road, 0.1, 1.1, nodes, terms, 100, 1000
                )
            )
        )
        assert_equal(nodes, 8)
        assert_equal(terms, 27)


def test_ordered_sample_thresholds_keep_two_exact_cuts() raises:
    var road = _dispatch_road()
    var nodes = 7
    var terms = 11
    var found = _try_sample_dispatch_cuts(
        road, 0.9, 2.1, nodes, terms, 100, 1000
    )
    assert_true(Bool(found))
    assert_equal(found.value()[0], _next_up(Float64(1.0)))
    assert_equal(found.value()[1], _next_up(Float64(2.0)))
    assert_equal(found.value()[2], 2)
    assert_equal(nodes, 8)
    assert_equal(terms, 27)


def test_more_than_two_sample_crossings_preserve_counters() raises:
    var road = _dispatch_road()
    road.info.geometries[0].geometry.samples.clear()
    for s in [
        Float64(0.0),
        Float64(0.5),
        Float64(1.0),
        Float64(1.5),
        Float64(2.0),
        Float64(3.0),
    ]:
        road.info.geometries[0].geometry.samples.append(
            _Sample(s, 0.0, s, 1.0, 0.0)
        )
    var nodes = 7
    var terms = 11
    assert_false(
        Bool(_try_sample_dispatch_cuts(road, 0.9, 2.1, nodes, terms, 100, 1000))
    )
    assert_equal(nodes, 7)
    assert_equal(terms, 11)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
