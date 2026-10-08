# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""External goals and conservative cached-error refresh controls."""

from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.lane_distance import _point_gap_scale, _refinement_square
from extensions.carla.lane_refinement import (
    _ClosedInterval,
    _ClosedIntervals,
    _LaneCertificate,
    _LaneExclusionGoal,
    _checked_center,
    _continue_lane_certificate,
    _goal_excludes,
    _run_lane_search,
)
from extensions.carla.road import Road
from extensions.carla.spiral_domain_proof import _SpiralDomainProof
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._lazy_taylor_controls import _diagonal_road, _whole_certificate
from tests._spiral_acceptance_controls import _capture_acceptance_proof


def _loose(var proof: _SpiralDomainProof) -> _SpiralDomainProof:
    # The original root errors remain valid after conservative enlargement.
    # These are explicitly enlarged allowances, not claimed capture words.
    proof.first_x_error *= 1e18
    proof.last_x_error *= 1e18
    proof.first_y_error *= 1e18
    proof.last_y_error *= 1e18
    return proof


def _external_goal(
    road: Road, location: Vector3, station: Float64
) raises -> Tuple[_LaneExclusionGoal, Array[Float64, 3]]:
    var parallel = road.copy()
    parallel.info.geometries[0].geometry.y -= 1e-6
    var terms = 0
    var point = _checked_center(parallel, 0, 0, station, terms, 100)
    # A valid checked point from a parallel segment shifted toward q.y=1.
    # The score is computed normally; no invented loose goal is supplied.
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    var scale = _point_gap_scale(point, query)
    var goal = _LaneExclusionGoal(
        _refinement_square[3](point, query, scale).high, scale, False
    )
    return (goal, point^)


def _solve_partition(
    road: Road,
    location: Vector3,
    seed: Float64,
    pending: List[Tuple[Float64, Float64, Int]],
    proof: Optional[_SpiralDomainProof],
) raises -> _LaneCertificate:
    var certificate = _whole_certificate(road, location, 0.4, 0.7, seed)
    _run_lane_search(
        road,
        0,
        0,
        0.4,
        0.7,
        location,
        certificate,
        pending.copy(),
        _ClosedIntervals(),
        List[_ClosedInterval](),
        None,
        200,
        20000,
        96,
        proof,
    )
    return certificate^


def _same_stored_minimum(
    one: _LaneCertificate, two: _LaneCertificate, location: Vector3
) raises:
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    assert_equal(_wide_point_order(one.point, two.point, query), 0)
    assert_true(one.lower <= one.upper)
    assert_true(two.lower <= two.upper)
    assert_true(len(one.cells) > 0)
    assert_true(len(two.cells) > 0)


def test_stale_optional_proof_with_external_witness_uses_valid_fallback() raises:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var packed = _capture_acceptance_proof(road, 0.4, 0.7)
    var external = _external_goal(road, location, 0.5)
    for stale in [False, True]:
        var proof = packed
        if stale:
            proof.record_at = 1
        var certificate = _whole_certificate(road, location)
        _continue_lane_certificate(
            road,
            0,
            0,
            0.4,
            0.7,
            location,
            certificate,
            None,
            1.0,
            max_nodes=100,
            max_terms=10000,
            spiral_proof=proof,
            goal=external[0],
            external_witness=external[1].copy(),
        )
        assert_true(
            _goal_excludes(certificate.lower, certificate.scale, external[0])
        )
        assert_true(certificate.terms >= 10)
        assert_true(certificate.nodes > 0)


def test_grouped_refresh_can_exclude_a_far_cell_against_existing_incumbent() raises:
    var road = _diagonal_road()
    var location = Vector3(0, 1, 0)
    var proof = _loose(_capture_acceptance_proof(road, 0.4, 0.7))
    var pending: List[Tuple[Float64, Float64, Int]] = [
        (0.4, 0.55, 0),
        (0.55, 0.7, 0),
    ]
    var baseline = _solve_partition(road, location, 0.4, pending, None)
    var refreshed = _solve_partition(road, location, 0.4, pending, proof)
    _same_stored_minimum(baseline, refreshed, location)
    assert_equal(refreshed.s, 0.4)


def test_grouped_refresh_can_prove_an_external_endpoint_goal() raises:
    var road = _diagonal_road()
    var location = Vector3(0, 1, 0)
    var proof = _loose(_capture_acceptance_proof(road, 0.4, 0.7))
    var external = _external_goal(road, location, 0.4)
    var certificate = _whole_certificate(road, location, 0.4, 0.7, 0.7)
    _continue_lane_certificate(
        road,
        0,
        0,
        0.4,
        0.7,
        location,
        certificate,
        None,
        1.0,
        max_nodes=100,
        max_terms=10000,
        spiral_proof=proof,
        goal=external[0],
        external_witness=external[1].copy(),
    )
    assert_true(
        _goal_excludes(certificate.lower, certificate.scale, external[0])
    )
    assert_equal(certificate.s, 0.4)


def test_refreshed_taylor_model_can_strictly_exclude_a_correlated_cell() raises:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var proof = _loose(_capture_acceptance_proof(road, 0.4, 0.7))
    var pending: List[Tuple[Float64, Float64, Int]] = [
        (0.4, 0.51, 0),
        (0.59, 0.7, 0),
        (0.51, 0.59, 0),
    ]
    var baseline = _solve_partition(road, location, 0.5, pending, None)
    var refreshed = _solve_partition(road, location, 0.5, pending, proof)
    _same_stored_minimum(baseline, refreshed, location)


def test_refreshed_taylor_model_can_prove_an_external_interior_goal() raises:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var proof = _loose(_capture_acceptance_proof(road, 0.4, 0.7))
    var external = _external_goal(road, location, 0.5)
    var certificate = _whole_certificate(road, location)
    _continue_lane_certificate(
        road,
        0,
        0,
        0.4,
        0.7,
        location,
        certificate,
        None,
        1.0,
        max_nodes=100,
        max_terms=10000,
        spiral_proof=proof,
        goal=external[0],
        external_witness=external[1].copy(),
    )
    assert_true(
        _goal_excludes(certificate.lower, certificate.scale, external[0])
    )


def test_refreshed_model_does_not_satisfy_an_unproved_zero_gap() raises:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var proof = _loose(_capture_acceptance_proof(road, 0.4, 0.7))
    var certificate = _whole_certificate(road, location)
    var pending: List[Tuple[Float64, Float64, Int]] = [(0.4, 0.7, 0)]
    with assert_raises(contains="numerical accuracy limit"):
        _run_lane_search(
            road,
            0,
            0,
            0.4,
            0.7,
            location,
            certificate,
            pending^,
            _ClosedIntervals(),
            List[_ClosedInterval](),
            (Float64(0.0), Float64(1.0)),
            100,
            10000,
            0,
            proof,
        )
    assert_false(certificate.exact_witness)
    assert_equal(certificate.cells[0].low, 0.4)
    assert_equal(certificate.cells[0].high, 0.7)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
