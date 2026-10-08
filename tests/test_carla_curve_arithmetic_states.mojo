# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Fresh selector, builder, and arithmetic controls with valid road state."""

from extensions.carla.curve_bounds import (
    _distance_jet,
    _geometry_distance,
    _lane_jet_model,
    _lane_jet_model_proof,
    _reference_jet,
    _reference_work,
    _sample_jet,
    _spiral_counts,
    _try_proof_expansion_jet,
)
from extensions.carla.curve_interval import _Jet
from extensions.carla.curve_trig import _curve_atan2
from extensions.carla.geometry import (
    RoadGeometry,
    LINE,
    SPIRAL,
    PARAM_POLY3,
    NORMALIZED,
    with_arc,
    with_param_poly3,
    with_spiral,
)
from extensions.carla.lane_geometry import _lane_geometry_pos_at
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.map_validation import _preflight_road_records
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import RoadInfoGeometry
from extensions.carla.spiral_domain_proof import _SpiralRootCapture
from extensions.carla.spiral_roundoff_proof import _try_spiral_roundoff_envelope
from extensions.carla.spiral_moment_proof import (
    _try_build_spiral_moments,
    _try_spiral_moment_expansion,
)
from math.vector3 import Vector3
from std.math import isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from tests._spiral_domain_controls import _geometry, _road, _proof, _point_bits


def _valid(road: Road) raises:
    var work = _MapBuildWork(MapBuildBudget())
    _preflight_road_records(road, work)
    assert_false(work.exhausted)


def test_unscaled_distance_bound_encloses_its_scalar_lane_center() raises:
    var road = _road(RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 20.0))
    _valid(road)
    var location = Vector3(1, -2, 0)
    var bound = _distance_jet(road, 0, 0, 2.0, 2.25, location).rounded_value()
    assert_true(bound.is_finite())
    for s in [2.0, 2.125, 2.25]:
        var point = road._lane_center(0, 0, s)
        var x = point[0] - Float64(location.x)
        var y = point[1] - Float64(location.y)
        var z = point[2] - Float64(location.z)
        assert_true(bound.contains(x * x + y * y + z * z))


def test_arc_reference_and_broad_spiral_requests_keep_conservative_bounds() raises:
    var arc = with_arc(RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 20.0), 0.1)
    var arc_road = _road(arc.copy())
    _valid(arc_road)
    var reference = _reference_jet(
        arc, _Jet.variable(2.0, 2.25), Vector3(0, 0, 0)
    )
    assert_true(reference[0].rounded_value().is_finite())
    assert_true(reference[1].rounded_value().is_finite())
    for s in [2.0, 2.125, 2.25]:
        var canonical = _lane_geometry_pos_at(arc, s)
        assert_true(reference[0].rounded_value().contains(canonical.x))
        assert_true(reference[1].rounded_value().contains(canonical.y))
    var spiral = _geometry()
    var road = _road(spiral.copy())
    _valid(road)
    var d = _geometry_distance(spiral, _Jet.variable(1.0, 5.0))
    var counts = _spiral_counts(spiral, d)
    assert_true(counts[1] - counts[0] > 1)
    var unknown = _reference_jet(
        spiral, _Jet.variable(1.0, 5.0), Vector3(0, 0, 0)
    )
    assert_false(unknown[0].rounded_value().is_finite())
    assert_equal(_reference_work(road, 1.0, 5.0), -1)


def test_reference_work_declines_a_valid_geometry_record_join() raises:
    var road = _road(RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 20.0))
    road.info.geometries[0].geometry.length = 10.0
    road.info.geometries.append(
        RoadInfoGeometry(10.0, RoadGeometry(LINE, 10.0, 10.0, 0.0, 0.0, 10.0))
    )
    _valid(road)
    assert_equal(_reference_work(road, 9.0, 9.5), 1)
    assert_equal(_reference_work(road, 9.5, 10.5), -1)


def test_builder_sample_tangent_crossings_keep_both_horizontal_signs() raises:
    for sign in [-1.0, 1.0]:
        var geometry = with_param_poly3(
            RoadGeometry(PARAM_POLY3, 0.0, 0.0, 0.0, 0.0, 1.0),
            CubicPolynomial(0.0, sign * 0.9, -sign, 0.0, 0.0),
            CubicPolynomial.constant(0.0),
            NORMALIZED,
        )
        var road = _road(geometry.copy())
        _valid(road)
        var one = geometry.samples[2]
        var two = geometry.samples[3]
        assert_true(one.tu * two.tu < 0.0)
        var at = one.s + 0.125 * (two.s - one.s)
        var sample = _sample_jet(
            geometry, _Jet.variable(at, at), 2, Vector3(0, 0, 0)
        )
        var rate = (two.s - at) / (two.s - one.s)
        var expected = _curve_atan2(
            rate * one.tv + (1.0 - rate) * two.tv,
            rate * one.tu + (1.0 - rate) * two.tu,
        )
        assert_true(sample[2].rounded_value().contains(expected))
        var broad = _reference_jet(
            geometry,
            _Jet.variable(0.0, geometry.samples[len(geometry.samples) - 1].s),
            Vector3(0, 0, 0),
        )
        assert_false(broad[0].rounded_value().is_finite())


def test_translated_queries_use_the_owned_proof_only_when_eligible() raises:
    var road = _road(_geometry())
    _valid(road)
    var proof = _proof(road, 2.125, 2.25)
    for translation in [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, 1),
    ]:
        var captured = _SpiralRootCapture()
        var actual = _lane_jet_model_proof[False](
            road, 0, 0, 2.125, 2.25, translation, proof, 2.125, 2.25, captured
        )
        if translation.x != 0.0 or translation.y != 0.0 or translation.z != 0.0:
            _point_bits(
                actual, _lane_jet_model(road, 0, 0, 2.125, 2.25, translation)
            )
        else:
            assert_true(actual[0].rounded_value().is_finite())
            assert_true(actual[1].rounded_value().is_finite())


def test_fresh_count_join_declines_single_branch_proof_expansion() raises:
    var geometry = _geometry()
    var road = _road(geometry.copy())
    _valid(road)
    var proof = _proof(road, 2.9, 3.0)
    var station = Float64(2.9778313018443896)
    var d = _geometry_distance(geometry, _Jet.variable(station, station))
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], 4)
    assert_equal(counts[1], 5)
    assert_true(
        Bool(
            _try_proof_expansion_jet(
                road, 0, 0, 2.95, Vector3(0, 0, 0), 1.0, 2.9, 3.0, proof
            )
        )
    )
    assert_false(
        Bool(
            _try_proof_expansion_jet(
                road, 0, 0, station, Vector3(0, 0, 0), 1.0, 2.9, 3.0, proof
            )
        )
    )


def test_moment_expansion_rejects_a_naturally_clamped_end_station() raises:
    var geometry = with_spiral(
        RoadGeometry(SPIRAL, 0.0, 0.0, 0.0, 0.0, 2.125), 0.0, 0.0
    )
    var road = _road(geometry.copy())
    _valid(road)
    var terms = 0
    var proof = _try_build_spiral_moments(4, terms, 10000)
    assert_true(Bool(proof))
    for s in [2.05, 2.125]:
        var d = _geometry_distance(geometry, _Jet.variable(s, s))
        var counts = _spiral_counts(geometry, d)
        assert_equal(counts[0], 4)
        assert_equal(counts[1], 4)
        var result = _try_spiral_moment_expansion(
            proof.value(), geometry, d, counts, Vector3(0, 0, 0)
        )
        assert_equal(Bool(result), s < 2.125)


def test_roundoff_envelope_refuses_finite_origin_addition_overflow() raises:
    var maximum = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    for axis in range(3):
        var geometry = with_spiral(
            RoadGeometry(
                SPIRAL,
                0.0,
                maximum if axis == 1 else 0.0,
                maximum if axis == 2 else 0.0,
                0.0,
                20.0,
            ),
            0.0,
            0.05,
        )
        var road = _road(geometry.copy())
        _valid(road)
        var d = _geometry_distance(geometry, _Jet.variable(2.125, 2.25))
        var counts = _spiral_counts(geometry, d)
        assert_equal(counts[0], 4)
        assert_equal(counts[1], 4)
        var result = _try_spiral_roundoff_envelope(geometry, d, counts[0])
        assert_equal(Bool(result), axis == 0)
        if result:
            assert_true(isfinite(result.value()[0]))
            assert_true(isfinite(result.value()[1]))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
