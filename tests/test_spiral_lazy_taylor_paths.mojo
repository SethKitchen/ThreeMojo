# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Non-tiny proof/fallback paths with independently inventoried work.

Separate trace-only receipts demonstrate actual cached/fresh/fallback branch
execution. This suite runs unchanged production source without tracing.
"""

from extensions.carla.curve_bounds import (
    _reference_work,
    _lane_jet_with_proof,
    _scaled_point_distance_jet,
    _try_proof_expansion_jet,
)
from extensions.carla.curve_interval import _Interval
from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.lane_distance import _refinement_square, _point_gap_scale
from extensions.carla.lane_refinement import (
    _refine_lane_certificate,
    _resume_lane_certificate,
    _checked_center,
    _scaled_accuracy,
    _certificate_within_gap,
    _global_lower,
)
from extensions.carla.map import _query_node_step_cost
from extensions.carla.map_search import MapQueryBudget, _MapQueryWork
from extensions.carla.spiral_domain_proof import _SpiralDomainProof
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_raises,
)
from tests._spiral_acceptance_controls import (
    _capture_acceptance_proof,
    _assert_acceptance_hit,
)
from tests._spiral_domain_controls import _bits
from tests._lazy_taylor_controls import _diagonal_road, _whole_certificate


def _enlarge(
    var proof: _SpiralDomainProof, factor: Float64 = 1048576.0
) -> _SpiralDomainProof:
    # A test-only conservative enlargement of valid error allowances.
    # This does not claim these words were captured or edit a Map cache.
    proof.first_x_error *= factor
    proof.last_x_error *= factor
    proof.first_y_error *= factor
    proof.last_y_error *= factor
    return proof


def _terms(fresh_retry: Bool) -> Int:
    # Every scalar/source traversal has two GL5 panels. Inventory: one
    # initial scalar, three node samples, one domain, forty-two local seed
    # samples, one expansion. A failed cached attempt followed by tightening
    # adds one reserved translated fallback and one fresh local domain.
    return (1 + 3 + 1 + 42 + 1 + (2 if fresh_retry else 0)) * 10


def test_cached_fresh_absent_and_mismatched_proof_paths_preserve_accuracy() raises:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    var proof = _capture_acceptance_proof(road, 0.4, 0.7)
    _assert_acceptance_hit(road, 0.4, 0.7, proof)
    assert_true(
        bitcast[DType.uint64](Float64(0.7))
        - bitcast[DType.uint64](Float64(0.4))
        > UInt64(32)
    )
    assert_equal(_reference_work(road, 0.4, 0.7), 10)
    var generic = _refine_lane_certificate(
        road,
        0,
        0,
        0.4,
        0.7,
        location,
        0.7,
        0.0,
    )
    for kind in range(4):
        var selected = proof
        if kind == 1:
            selected = _enlarge(selected)
            _assert_acceptance_hit(road, 0.4, 0.7, selected)
        elif kind == 3:
            selected.record_at = 1
        var optional: Optional[_SpiralDomainProof] = selected
        if kind == 2:
            optional = None
        var result = _refine_lane_certificate(
            road,
            0,
            0,
            0.4,
            0.7,
            location,
            0.7,
            0.0,
            spiral_proof=optional,
        )
        assert_false(result.exact_witness)
        assert_equal(result.nodes, 2)
        assert_equal(result.terms, _terms(kind == 1))
        _bits(result.s, generic.s)
        for axis in range(3):
            _bits(result.point[axis], generic.point[axis])
        var score = _refinement_square[3](result.point, query, result.scale)
        var allowance = _scaled_accuracy(
            road,
            0,
            0,
            0.4,
            0.7,
            result.s,
            score.low,
            result.scale,
        )
        assert_true(
            _certificate_within_gap(
                result.lower, result.scale, result.scale, score.high, allowance
            )
        )
        assert_equal(len(result.cells), 1)
        _bits(result.cells[0].low, 0.4)
        _bits(result.cells[0].high, 0.7)
        assert_equal(result.cells[0].depth, 0)
        # A scalar reference set supplements the independent interval proof.
        for i in range(31):
            var terms = 0
            var station = 0.4 + Float64(i) * 0.01
            var point = _checked_center(road, 0, 0, station, terms, 10)
            assert_true(_wide_point_order(result.point, point, query) <= 0)


def test_non_tiny_resume_keeps_initial_work_and_exact_vs_one_short_terms() raises:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var proof = _capture_acceptance_proof(road, 0.4, 0.7)
    for fresh in [False, True]:
        var selected = proof
        if fresh:
            selected = _enlarge(selected)
        var total = _terms(fresh)
        var certificate = _whole_certificate(road, location)
        assert_equal(certificate.terms, 10)
        _resume_lane_certificate(
            road,
            0,
            0,
            0.4,
            0.7,
            location,
            certificate,
            1000000.0,
            1.0,
            max_nodes=3,
            max_terms=total,
            spiral_proof=selected,
        )
        assert_equal(certificate.nodes, 3)
        assert_equal(certificate.terms, total)
        assert_false(certificate.exact_witness)
        var limited = _whole_certificate(road, location)
        with assert_raises(contains="quadrature work limit"):
            _resume_lane_certificate(
                road,
                0,
                0,
                0.4,
                0.7,
                location,
                limited,
                1000000.0,
                1.0,
                max_terms=total - 1,
                spiral_proof=selected,
            )
        assert_equal(limited.nodes, 2)
        assert_equal(limited.terms, total - 10)
        assert_false(limited.exact_witness)
        assert_equal(len(limited.cells), 1)
        _bits(limited.cells[0].low, 0.4)
        _bits(limited.cells[0].high, 0.7)
        assert_equal(limited.cells[0].lower, 0.0)
        var spent = limited.terms
        _resume_lane_certificate(
            road,
            0,
            0,
            0.4,
            0.7,
            location,
            limited,
            1000000.0,
            1.0,
            max_nodes=5,
            max_terms=spent + total - 10,
            spiral_proof=selected,
        )
        assert_equal(limited.nodes, 5)
        assert_equal(limited.terms, spent + total - 10)
        _bits(limited.s, certificate.s)
        for axis in range(3):
            _bits(limited.point[axis], certificate.point[axis])


def test_optional_headroom_can_choose_charged_fallback_without_resetting_work() raises:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var proof = _capture_acceptance_proof(road, 0.4, 0.7)
    # Large headroom permits the cached expansion; at 480 terms the same
    # root uses the translated fallback instead. Both satisfy the contract.
    # The separate branch receipts verify those actual execution paths.
    for limit in [480, 489, 490]:
        var certificate = _whole_certificate(road, location)
        _resume_lane_certificate(
            road,
            0,
            0,
            0.4,
            0.7,
            location,
            certificate,
            1000000.0,
            1.0,
            max_nodes=3,
            max_terms=limit,
            spiral_proof=proof,
        )
        assert_equal(certificate.nodes, 3)
        assert_equal(certificate.terms, 480)
    var enlarged = _enlarge(proof)
    var limited = _whole_certificate(road, location)
    with assert_raises(contains="quadrature work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            0.4,
            0.7,
            location,
            limited,
            1000000.0,
            1.0,
            max_terms=489,
            spiral_proof=enlarged,
        )
    assert_equal(limited.terms, 480)


def test_local_seed_recomputes_scale_and_width_before_cached_acceptance() raises:
    var road = _diagonal_road(True)
    var location = Vector3(0.4, 0, 0.6)
    var proof = _capture_acceptance_proof(road, 0.4, 0.7)
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    var terms = 0
    var before_point = _checked_center(road, 0, 0, 0.55, terms, 10)
    var before_scale = _point_gap_scale(before_point, query)
    var before_width = road.lane_width(0, 0, 0.55)
    var result = _refine_lane_certificate(
        road,
        0,
        0,
        0.4,
        0.7,
        location,
        0.7,
        0.0,
        spiral_proof=proof,
    )
    assert_equal(before_scale, 0.125)
    assert_equal(result.scale, 0.0625)
    assert_true(road.lane_width(0, 0, result.s) < before_width)
    assert_true(_wide_point_order(result.point, before_point, query) < 0)
    assert_equal(result.terms, 480)
    var score = _refinement_square[3](result.point, query, result.scale)
    var allowance = _scaled_accuracy(
        road,
        0,
        0,
        0.4,
        0.7,
        result.s,
        score.low,
        result.scale,
    )
    assert_true(
        _certificate_within_gap(
            result.lower, result.scale, result.scale, score.high, allowance
        )
    )


def test_global_step_remainder_enforces_exact_non_tiny_resume_node_cost() raises:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var proof = _enlarge(_capture_acceptance_proof(road, 0.4, 0.7))
    var node_cost = _query_node_step_cost(1)
    assert_equal(node_cost, 120)
    var certificate = _whole_certificate(road, location)
    var work = _MapQueryWork(MapQueryBudget(1, max_steps=3 * node_cost))
    work.charge(0, certificate.terms, node_cost)
    var previous_terms = certificate.terms
    _resume_lane_certificate(
        road,
        0,
        0,
        0.4,
        0.7,
        location,
        certificate,
        1000000.0,
        1.0,
        max_nodes=work.node_cap(certificate.nodes, node_cost),
        max_terms=work.term_cap(certificate.terms),
        spiral_proof=proof,
    )
    work.charge(
        certificate.nodes, certificate.terms - previous_terms, node_cost
    )
    assert_equal(work.steps, 3 * node_cost)
    assert_equal(work.terms, 500)
    assert_equal(work.nodes, 3)
    certificate = _whole_certificate(road, location)
    work = _MapQueryWork(MapQueryBudget(1, max_steps=3 * node_cost - 1))
    work.charge(0, certificate.terms, node_cost)
    with assert_raises(contains="interval work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            0.4,
            0.7,
            location,
            certificate,
            1000000.0,
            1.0,
            max_nodes=work.node_cap(certificate.nodes, node_cost),
            max_terms=work.term_cap(certificate.terms),
            spiral_proof=proof,
        )
    assert_equal(certificate.nodes, 2)
    assert_equal(certificate.terms, 500)
    assert_false(certificate.exact_witness)


def test_cached_taylor_closes_above_the_old_eager_error_threshold() raises:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var proof = _enlarge(_capture_acceptance_proof(road, 0.4, 0.7), 512.0)
    _assert_acceptance_hit(road, 0.4, 0.7, proof)
    var result = _refine_lane_certificate(
        road,
        0,
        0,
        0.4,
        0.7,
        location,
        0.7,
        0.0,
        spiral_proof=proof,
    )
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    var score = _refinement_square[3](result.point, query, result.scale)
    var tolerance = _scaled_accuracy(
        road,
        0,
        0,
        0.4,
        0.7,
        result.s,
        score.low,
        result.scale,
    )
    var point = _lane_jet_with_proof(road, 0, 0, 0.4, 0.7, 0.4, 0.7, proof)
    var domain = _scaled_point_distance_jet(point, location, result.scale)
    assert_true(domain.error > tolerance * 0.25)
    assert_true(domain.error < tolerance)
    var center = _try_proof_expansion_jet(
        road,
        0,
        0,
        result.s,
        location,
        result.scale,
        0.4,
        0.7,
        proof,
    )
    assert_true(Bool(center))
    var lower = _global_lower(
        domain,
        center.value(),
        _Interval(0.4, 0.7) - _Interval.point(result.s),
    )
    assert_true(score.high - lower < tolerance)
    assert_equal(result.terms, 480)
    assert_equal(result.nodes, 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
