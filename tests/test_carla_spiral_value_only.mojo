# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bitwise full-jet controls for the isolated value-only SPIRAL prototype.

These source tests require a native run. They are not a proof of compiled
parity or a replacement for paired certificate and budget controls.
"""

from extensions.carla.curve_bounds import (
    _geometry_distance,
    _reference_jet,
    _spiral_counts,
    _spiral_expression,
    _spiral_jet,
)
from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _ValueJet,
    _next_down,
    _next_up,
    _without_derivatives,
)
from extensions.carla.curve_trig import (
    _COS_COEFFICIENTS,
    _SIN_COEFFICIENTS,
    _expression_polynomial,
    _sincos_branch_expression,
    _sincos_expression,
)
from extensions.carla.geometry import SPIRAL, RoadGeometry, with_spiral
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from tests._spiral_full_jet_reference import (
    _FullJet,
    _full_polynomial,
    _full_sincos_branch,
    _full_sincos_jet,
    _full_spiral_jet,
    _full_uncertain,
    _full_union_points,
)


def _full(source: _Jet) -> _FullJet:
    return _FullJet(source.value, source.first, source.second, source.error)


def _bits(actual: Float64, expected: Float64) raises:
    assert_equal(bitcast[DType.uint64](actual), bitcast[DType.uint64](expected))


def _interval_bits(actual: _Interval, expected: _Interval) raises:
    _bits(actual.low, expected.low)
    _bits(actual.high, expected.high)


def _fields(actual: _ValueJet, expected: _FullJet) raises:
    _interval_bits(actual.value, expected.value)
    _bits(actual.error, expected.error)
    _interval_bits(actual.rounded_value(), expected.rounded_value())
    _interval_bits(actual.first, _Interval.whole())
    _interval_bits(actual.second, _Interval.whole())


def _jet_bits(actual: _Jet, expected: _FullJet) raises:
    _interval_bits(actual.value, expected.value)
    _bits(actual.error, expected.error)
    _interval_bits(actual.rounded_value(), expected.rounded_value())
    _interval_bits(actual.first, expected.first)
    _interval_bits(actual.second, expected.second)


def _point_bits(
    actual: Tuple[_Jet, _Jet, _Jet],
    expected: Tuple[_FullJet, _FullJet, _FullJet],
) raises:
    _jet_bits(actual[0], expected[0])
    _jet_bits(actual[1], expected[1])
    _jet_bits(actual[2], expected[2])


def _full_reference(
    geometry: RoadGeometry, distance: _Jet, translation: Vector3
) -> Tuple[_FullJet, _FullJet, _FullJet]:
    # The original SPIRAL dispatch, including its first traversal before
    # checking whether a second traversal and rounded union are required.
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    if counts[0] < 1 or counts[1] - counts[0] > 1:
        var unknown = _full_uncertain(_Interval.whole())
        return (unknown, unknown, unknown)
    var first = _full_spiral_jet(geometry, _full(d), counts[0], translation)
    if counts[0] == counts[1]:
        return first
    return _full_union_points(
        first, _full_spiral_jet(geometry, _full(d), counts[1], translation)
    )


def _arithmetic(one: _Jet, two: _Jet) raises:
    var a = _without_derivatives(one)
    var b = _without_derivatives(two)
    var full_one = _full(one)
    var full_two = _full(two)
    _fields(a, full_one)
    _fields(b, full_two)
    _fields(-a, -full_one)
    _fields(a + b, full_one + full_two)
    _fields(a - b, full_one - full_two)
    _fields(a * b, full_one * full_two)
    _fields(a / b, full_one / full_two)
    _jet_bits(-one, -full_one)
    _jet_bits(one + two, full_one + full_two)
    _jet_bits(one - two, full_one - full_two)
    _jet_bits(one * two, full_one * full_two)
    _jet_bits(one / two, full_one / full_two)


def test_value_error_operations_keep_every_bit_and_shortcut() raises:
    var tiny = bitcast[DType.float64](UInt64(1))
    var largest = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    var quiet_nan = bitcast[DType.float64](UInt64(0x7FF8000000000000))
    for value in [-0.0, 0.0, tiny, -tiny, 0.25, 1.0, -1.0, 3.0, largest]:
        _fields(_ValueJet.constant(value), _FullJet.constant(value))
        _fields(
            _ValueJet.variable(min(-value, value), max(-value, value)),
            _FullJet.variable(min(-value, value), max(-value, value)),
        )
        var source = _Jet.variable(value, value)
        source.error = tiny
        for other in [-0.0, 0.0, 1.0, -1.0, 2.0, tiny]:
            _arithmetic(source, _Jet.constant(other))
            _arithmetic(_Jet.constant(other), source)
    for value in [quiet_nan, inf[DType.float64](), -inf[DType.float64]()]:
        _fields(_ValueJet.constant(value), _FullJet.constant(value))
        _arithmetic(_Jet.constant(value), _Jet.constant(0.0))
        _arithmetic(_Jet.constant(1.0), _Jet.constant(value))
    _arithmetic(_Jet.constant(-0.0), _Jet.constant(0.0))
    _arithmetic(_Jet.constant(0.0), _Jet.constant(-0.0))
    _arithmetic(_Jet.constant(1.0), _Jet.constant(1.0))
    var domain = _Jet.variable(-2.0, 3.0)
    domain.error = 0.125
    _arithmetic(domain, _Jet.variable(-1.0, 1.0))
    var denominator = _Jet.variable(0.125, 0.25)
    for error in [0.0, _next_down(0.125), 0.125, _next_up(0.125)]:
        denominator.error = error
        _arithmetic(domain, denominator)
    domain.error = inf[DType.float64]()
    _arithmetic(domain, _Jet.constant(1.0))
    # Conversion must retain the separate inherited error before any graph.
    var source = _Jet.variable(0.99, 1.01)
    source.error = 1e-9
    var copied = _without_derivatives(source)
    _interval_bits(copied.value, source.value)
    _bits(copied.error, source.error)
    assert_true(copied.value.low != source.rounded_value().low)


def _trig(source: _Jet) raises:
    var light = _without_derivatives(source)
    var actual = _sincos_expression(light)
    var expected = _full_sincos_jet(_full(source))
    _fields(actual[0], expected[0])
    _fields(actual[1], expected[1])
    _fields(
        _expression_polynomial(materialize[_SIN_COEFFICIENTS](), light),
        _full_polynomial(materialize[_SIN_COEFFICIENTS](), _full(source)),
    )
    _fields(
        _expression_polynomial(materialize[_COS_COEFFICIENTS](), light),
        _full_polynomial(materialize[_COS_COEFFICIENTS](), _full(source)),
    )


def test_trig_modes_quadrant_joins_phase_guards_and_whole_fallback() raises:
    var tiny = bitcast[DType.float64](UInt64(1))
    for angle in [-6.0, -4.0, -2.0, -0.0, 0.0, tiny, 0.2, 2.0, 4.0, 6.0]:
        var source = _Jet.variable(angle, angle)
        _trig(source)
        source.error = tiny
        _trig(source)
        for quadrant in [-4, -3, -2, -1, 0, 1, 2, 3, 4]:
            var actual = _sincos_branch_expression(
                _without_derivatives(source), quadrant
            )
            var expected = _full_sincos_branch(_full(source), quadrant)
            _fields(actual[0], expected[0])
            _fields(actual[1], expected[1])
    for join in [
        -3.9269908169872414,
        -0.7853981633974483,
        0.7853981633974483,
        2.356194490192345,
        3.9269908169872414,
    ]:
        _trig(_Jet.variable(_next_down(join), _next_up(join)))
        var source = _Jet.variable(join - 1e-8, join + 1e-8)
        source.error = 1e-10
        _trig(source)
    for edge in [-1048576.0, 1048576.0]:
        _trig(_Jet.variable(_next_down(edge), _next_up(edge)))
        _trig(_Jet.variable(edge, edge))
    _trig(_Jet.variable(1048577.0, 1048578.0))
    _trig(_Jet.variable(-1048578.0, -1048577.0))
    _trig(_Jet.variable(-20.0, 20.0))
    _trig(_Jet.variable(-inf[DType.float64](), inf[DType.float64]()))
    var uncertain = _Jet.variable(0.1, 0.2)
    uncertain.error = inf[DType.float64]()
    _trig(uncertain)


def _fixed_count(
    geometry: RoadGeometry, source: _Jet, pieces: Int, translation: Vector3
) raises:
    var actual = _spiral_expression(
        geometry, _without_derivatives(source), pieces, translation
    )
    var expected = _full_spiral_jet(
        geometry, _full(source), pieces, translation
    )
    _point_bits(_spiral_jet(geometry, source, pieces, translation), expected)
    _fields(actual[0], expected[0])
    _fields(actual[1], expected[1])
    _fields(actual[2], expected[2])


def test_both_gauss_counts_keep_all_fields_before_the_final_hull() raises:
    var geometry = with_spiral(
        RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, 8.0), 0.01, 0.2
    )
    for interval in [
        _Interval(-0.0, 0.0),
        _Interval(0.1, 0.2),
        _Interval(1.9, 2.1),
        _Interval(4.9, 5.1),
    ]:
        var source = _Jet.variable(interval.low, interval.high)
        source.error = 1e-12
        for count in [1, 2, 3, 6, 7]:
            _fixed_count(geometry, source, count, Vector3(0, 0, 0))
    var inherited = _Jet.variable(0.99, 1.01)
    inherited.error = 1e-9
    for heading in [
        0.0,
        0.7853981633974483,
        1048576.0,
        1048577.0,
        inf[DType.float64](),
    ]:
        geometry.heading = heading
        _fixed_count(geometry, inherited, 2, Vector3(0, 0, 0))
        _fixed_count(geometry, inherited, 3, Vector3(0, 0, 0))
    geometry.heading = 0.0
    geometry.x = 1e30
    geometry.y = -1e30
    _fixed_count(geometry, inherited, 2, Vector3(1e30, 1e30, 0.0))
    _fixed_count(geometry, inherited, 3, Vector3(1e30, 1e30, 0.0))
    geometry.x = 1e308
    geometry.y = -1e308
    _fixed_count(geometry, inherited, 2, Vector3(0, 0, 0))
    geometry.curvature_start = 1e308
    geometry.curvature_end = -1e308
    _fixed_count(geometry, inherited, 3, Vector3(0, 0, 0))
    var tiny = bitcast[DType.float64](UInt64(1))
    geometry = with_spiral(
        RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, -0.0, 8.0), tiny, tiny
    )
    _fixed_count(geometry, _Jet.variable(tiny, 2.0 * tiny), 2, Vector3(0, 0, 0))


def test_count_selection_clamping_and_union_match_full_jet_reference() raises:
    var geometry = with_spiral(
        RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, 4.0), 0.01, 0.01
    )
    var threshold = 1.0 / 1.01
    var crossing = _Jet.variable(threshold - 1e-8, threshold + 1e-8)
    crossing.error = 1e-12
    var counts = _spiral_counts(geometry, crossing)
    assert_equal(counts[0], 2)
    assert_equal(counts[1], 3)
    for heading in [0.0, 0.7853981633974483, 1048577.0]:
        geometry.heading = heading
        var d = _geometry_distance(geometry, crossing)
        _fixed_count(geometry, d, counts[0], Vector3(0, 0, 0))
        _fixed_count(geometry, d, counts[1], Vector3(0, 0, 0))
        var actual = _reference_jet(geometry, crossing, Vector3(0, 0, 0))
        _point_bits(
            actual, _full_reference(geometry, crossing, Vector3(0, 0, 0))
        )
        assert_false(actual[0].first.is_finite())
        assert_false(actual[0].second.is_finite())
        _bits(actual[0].error, 0.0)
    geometry.heading = 0.0
    for station in [_next_down(threshold), threshold, _next_up(threshold)]:
        var point = _Jet.variable(station, station)
        _point_bits(
            _reference_jet(geometry, point, Vector3(0, 0, 0)),
            _full_reference(geometry, point, Vector3(0, 0, 0)),
        )
    for interval in [
        _Interval(-2.0, -1.0),
        _Interval(-1e-8, 1e-8),
        _Interval(0.1, 0.2),
        _Interval(3.99999999, 4.00000001),
        _Interval(5.0, 6.0),
        _Interval(0.0, 4.0),
    ]:
        var source = _Jet.variable(interval.low, interval.high)
        _point_bits(
            _reference_jet(geometry, source, Vector3(0, 0, 0)),
            _full_reference(geometry, source, Vector3(0, 0, 0)),
        )
    var smooth = _reference_jet(
        geometry, _Jet.variable(0.1, 0.2), Vector3(0, 0, 0)
    )
    assert_true(smooth[0].first.is_finite())
    var unresolved = _reference_jet(
        geometry, _Jet.variable(0.0, 4.0), Vector3(0, 0, 0)
    )
    assert_false(unresolved[0].value.is_finite())
    geometry.length = 1e12
    var unsupported = _Jet.variable(1e10, 1e10 + 1.0)
    assert_equal(_spiral_counts(geometry, unsupported)[0], -1)
    _point_bits(
        _reference_jet(geometry, unsupported, Vector3(0, 0, 0)),
        _full_reference(geometry, unsupported, Vector3(0, 0, 0)),
    )
    unsupported.error = inf[DType.float64]()
    _point_bits(
        _reference_jet(geometry, unsupported, Vector3(0, 0, 0)),
        _full_reference(geometry, unsupported, Vector3(0, 0, 0)),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
