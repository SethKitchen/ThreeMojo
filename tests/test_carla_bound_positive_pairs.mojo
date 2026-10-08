# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Positive and adjacent-boundary pairs from unchanged valid arithmetic graphs."""

from extensions.carla.curve_bounds import (
    _sample_jet,
    _geometry_distance,
    _lane_jet,
    _spiral_counts,
)
from extensions.carla.curve_interval import (
    _Jet,
    _ValueJet,
    _next_down,
    _next_up,
)
from extensions.carla.curve_trig import _curve_atan2
from extensions.carla.geometry import (
    RoadGeometry,
    PARAM_POLY3,
    POLY3,
    LINE,
    SPIRAL,
    NORMALIZED,
    with_param_poly3,
    with_poly3,
    with_spiral,
)
from extensions.carla.junction_bounds import (
    _certify_junction_span,
    _centered_elevation_enclosure,
)
from extensions.carla.lane_value_bounds import (
    _lane_value_bound,
    _sample_value,
    _atan2_value,
    _reference_sampled_value,
)
from extensions.carla.road_info import RoadInfoGeometry
from extensions.carla.spiral_grouped_lane import _try_grouped_lane_jet
from extensions.carla.spiral_grouped_roundoff_proof import (
    _try_spiral_grouped_roundoff_envelope,
)
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.polynomial import CubicPolynomial
from math.bounds import Box3
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from std.memory import bitcast
from tests._spiral_domain_controls import _road
from tests.test_carla_junction_arithmetic_states import _line, _valid, _point


def test_junction_lower_face_and_monotone_success_are_complete_pairs() raises:
    var road = _line()
    road.info.elevations[0].polynomial = CubicPolynomial(
        0.0, 1.0, 0.0, 0.0, 0.0
    )
    _valid(road)
    var low = _next_down(1.0)
    var box = Box3(Vector3(-100, -100, 1), Vector3(100, 100, 2))
    var work = _MapBuildWork(MapBuildBudget())
    _certify_junction_span(road, 0, 0, low, 1.0, box, work)
    assert_true(box.contains_point(_point(road, 0, low)))
    assert_true(box.contains_point(_point(road, 0, 1.0)))
    # Exact quadratic extrema are [65/64,5/4] on this decreasing span.
    # Horner's broad interval crosses the proposal; monotone endpoints fit.
    road.info.elevations[0].polynomial = CubicPolynomial(
        2.0, -2.0, 1.0, 0.0, 0.0
    )
    _valid(road)
    box = Box3(Vector3(-100, -100, 0.99), Vector3(100, 100, 1.26))
    var expected = box
    work = _MapBuildWork(MapBuildBudget())
    _certify_junction_span(road, 0, 0, 0.5, 0.875, box, work)
    assert_true(box.min == expected.min)
    assert_true(box.max == expected.max)
    assert_equal(work.terms, 4)
    for station in [0.5, 0.625, 0.75, 0.875]:
        assert_true(box.contains_point(_point(road, 0, station)))


def test_large_finite_gradient_requests_a_centered_enclosure() raises:
    var road = _line()
    road.info.elevations[0].polynomial = CubicPolynomial(
        0.0, 1e18, 0.0, 0.0, 0.0
    )
    _valid(road)
    var low = 1.0
    var high = _next_up(low)
    var point = _point(road, 0, low)
    assert_equal(point.z, _point(road, 0, high).z)
    var box = Box3(Vector3(-100, -100, point.z), Vector3(100, 100, point.z))
    var work = _MapBuildWork(MapBuildBudget())
    _certify_junction_span(road, 0, 0, low, high, box, work)
    assert_true(box.contains_point(point))
    assert_true(box.contains_point(_point(road, 0, high)))
    assert_true(work.terms >= 128)
    assert_false(work.exhausted)


def test_centered_polynomial_success_preserves_true_values() raises:
    var road = _line()
    road.info.elevations[0].polynomial = CubicPolynomial(
        2.0, -2.0, 1.0, 0.0, 0.0
    )
    _valid(road)
    var point = _lane_value_bound(road, 0, 0, 0.5, 0.875)
    var original = point[2].rounded_value()
    var work = _MapBuildWork(MapBuildBudget())
    var result = _centered_elevation_enclosure(
        road, 0.5, 0.875, original, point[2].error, work
    )
    assert_true(result.is_finite())
    assert_true(result.low >= original.low)
    assert_true(result.high <= original.high)
    assert_true(result.contains(1.015625))
    assert_true(result.contains(1.25))
    assert_equal(work.terms, 128)


def test_public_builders_produce_zero_and_mixed_tangent_pairs() raises:
    for kind in range(4):
        var u = CubicPolynomial(0.0, 0.0, -0.1875, 1.0, 0.0)
        var index = 0
        if kind == 1:
            u = CubicPolynomial(0.0, 0.0, 1.0, 0.0, 0.0)
        elif kind == 2:
            u = CubicPolynomial(0.0, -1.0, 0.0, 0.0, 0.0)
            index = 1
        elif kind == 3:
            u = CubicPolynomial(0.0, -0.4, 1.0, 0.0, 0.0)
            index = 1
        var geometry = with_param_poly3(
            RoadGeometry(PARAM_POLY3, 0.0, 0.0, 0.0, 0.0, 4.0),
            u,
            CubicPolynomial.constant(0.0),
            NORMALIZED,
        )
        var road = _road(geometry.copy())
        _valid(road)
        var one = geometry.samples[index]
        var two = geometry.samples[index + 1]
        if kind == 0:
            assert_equal(one.tu, 0.0)
            assert_equal(two.tu, 0.0)
        elif kind == 1:
            assert_equal(one.tu, 0.0)
            assert_true(two.tu > 0.0)
        elif kind == 2:
            assert_true(one.tu < 0.0 and two.tu < 0.0)
        else:
            assert_true(one.tu < 0.0 and two.tu > 0.0)
        var station = one.s + 0.125 * (two.s - one.s)
        var rate = (two.s - station) / (two.s - one.s)
        var expected = _curve_atan2(0.0, rate * one.tu + (1.0 - rate) * two.tu)
        var point = _sample_jet(
            geometry, _Jet.variable(station, station), index, Vector3(0, 0, 0)
        )
        assert_true(point[2].rounded_value().contains(expected))
        var value = _sample_value(
            geometry,
            _ValueJet.variable(station, station),
            index,
            Vector3(0, 0, 0),
        )
        assert_true(value[2].rounded_value().contains(expected))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
