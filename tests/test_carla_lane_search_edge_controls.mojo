# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Exact finite boundary cells and optional-proof headroom controls."""

from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _next_down,
    _next_up,
)
from extensions.carla.geometry import ARC
from extensions.carla.lane_refinement import (
    _ClosedInterval,
    _ClosedIntervals,
    _global_lower,
    _refine_lane_certificate,
    _run_lane_search,
)
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from tests._lazy_taylor_controls import _whole_certificate
from tests.test_carla_cross_candidate_certificates import _road


def test_valid_center_derivative_keeps_matching_natural_bound() raises:
    var domain = _Jet(
        _Interval(1.0, 2.0), _Interval.point(0.0), _Interval.point(0.0), 0.0
    )
    var center = _Jet.constant(1.0)
    assert_equal(_global_lower(domain, center, _Interval(-1.0, 1.0)), 1.0)


def test_declined_optional_axis_proof_cannot_reset_seed_or_singleton_node_budget() raises:
    for seed_only in [False, True]:
        var road = _road()
        road.info.geometries[0].geometry.heading = 0.7
        # A finite scalar coordinate outside the optional rounded-box guard
        # makes the singleton proof decline, while its scalar remains valid.
        road.info.geometries[0].geometry.x = 1e-200
        var high = 2.0 if seed_only else 1.0
        with assert_raises(contains="interval work limit"):
            _ = _refine_lane_certificate(
                road,
                0,
                0,
                1.0,
                high,
                Vector3(0, 0, 0),
                1.0,
                0.0,
                max_nodes=1,
                seed_only=seed_only,
            )


def test_tiny_positive_cell_returns_exact_zero_distance_witness() raises:
    var road = _road()
    var high = _next_up(Float64(1.0))
    var certificate = _whole_certificate(
        road, Vector3(1, 0, 0), 1.0, high, high
    )
    var pending: List[Tuple[Float64, Float64, Int]] = [(1.0, high, 0)]
    _run_lane_search(
        road,
        0,
        0,
        1.0,
        high,
        Vector3(1, 0, 0),
        certificate,
        pending^,
        _ClosedIntervals(),
        List[_ClosedInterval](),
        None,
        100,
        100,
        96,
    )
    assert_true(certificate.exact_witness)
    assert_equal(certificate.s, 1.0)
    assert_equal(certificate.point[0], 1.0)
    assert_equal(certificate.nodes, 1)


def test_adjacent_binade_boundary_uses_original_terminal_point_path() raises:
    var road = _road()
    var low = _next_down(Float64(1.0))
    for query_x in [Float32(1.0), Float32(2.0)]:
        var query = Vector3(query_x, 0, 0)
        var certificate = _whole_certificate(road, query, low, 1.0, low)
        var pending: List[Tuple[Float64, Float64, Int]] = [(low, 1.0, 0)]
        _run_lane_search(
            road,
            0,
            0,
            low,
            1.0,
            query,
            certificate,
            pending^,
            _ClosedIntervals(),
            List[_ClosedInterval](),
            None,
            100,
            100,
            96,
        )
        assert_true(certificate.exact_witness)
        assert_equal(certificate.s, 1.0)
        assert_equal(certificate.nodes, 1)


def test_zero_to_smallest_subnormal_owner_has_no_missing_station() raises:
    var road = _road()
    var high = bitcast[DType.float64](UInt64(1))
    for query_y in [Float32(0.0), Float32(1.0)]:
        var query = Vector3(0, query_y, 0)
        var certificate = _whole_certificate(road, query, 0.0, high, high)
        var pending: List[Tuple[Float64, Float64, Int]] = [
            (Float64(0.0), high, 0)
        ]
        _run_lane_search(
            road,
            0,
            0,
            0.0,
            high,
            query,
            certificate,
            pending^,
            _ClosedIntervals(),
            List[_ClosedInterval](),
            None,
            100,
            100,
            96,
        )
        assert_true(certificate.exact_witness)
        assert_equal(certificate.s, 0.0)
        assert_equal(certificate.nodes, 1)


def test_optional_frozen_context_preserves_required_node_and_term_headroom() raises:
    var road = _road()
    road.info.geometries[0].geometry.kind = ARC
    road.info.geometries[0].geometry.curvature_start = 0.125
    for budget in range(3):
        var certificate = _whole_certificate(
            road, Vector3(0, 0, 0), 1.0, 1.0, 1.0
        )
        var terms = certificate.terms
        var max_nodes = 1 if budget == 0 else 100
        var max_terms = terms + 1 if budget == 1 else 100
        var terminal: List[_ClosedInterval] = [
            _ClosedInterval(1.0, 1.0, 0, certificate.lower, certificate.scale)
        ]
        _run_lane_search(
            road,
            0,
            0,
            1.0,
            1.0,
            Vector3(0, 0, 0),
            certificate,
            List[Tuple[Float64, Float64, Int]](),
            _ClosedIntervals(),
            terminal^,
            None,
            max_nodes,
            max_terms,
            96,
        )
        assert_true(certificate.exact_witness)
        assert_equal(certificate.s, 1.0)
        var optional_work = 1 if budget == 2 else 0
        assert_equal(certificate.nodes, optional_work)
        assert_equal(certificate.terms, terms + optional_work)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
