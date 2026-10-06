# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Successful admitted-proof resumption over three exact stored parameters."""

from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.lane_distance import _normalized_square
from extensions.carla.curve_interval import _next_up
from extensions.carla.lane_refinement import (
    _LaneCertificate,
    _resume_lane_certificate,
    _checked_center,
    _scaled_accuracy,
    _certificate_within_gap,
)
from extensions.carla.road import Road
from extensions.carla.spiral_domain_proof import _SpiralDomainProof
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_true,
    assert_false,
    assert_equal,
    assert_raises,
)
from tests._spiral_domain_controls import _bits
from tests._spiral_acceptance_controls import (
    _acceptance_road,
    _narrow_high,
    _capture_acceptance_proof,
    _assert_acceptance_hit,
    _initial_acceptance_certificate,
)


def _acceptance_resume_terms(with_proof: Bool) -> Int:
    # Every station in this three-value domain has two GL5 panels: ten
    # logical terms per center or Jet. Independently inventory the search:
    # initial witness, three root samples, one domain Jet, the seed's two
    # initial samples plus forty iterations, one translated expansion, and
    # three samples for each of two adjacent terminal children.
    var evaluations = 1 + 3 + 1 + (2 + 40) + 1 + 2 * 3
    if with_proof:
        # The admitted optional expansion cannot certify the requested zero
        # gap here. Its work remains charged before the translated fallback.
        evaluations += 1
    return evaluations * (2 * 5)


def _complete_resume(
    road: Road,
    location: Vector3,
    proof: Optional[_SpiralDomainProof],
    max_terms: Int = 2000000,
) raises -> _LaneCertificate:
    var certificate = _initial_acceptance_certificate(road, location)
    var initial_point = certificate.point.copy()
    assert_false(certificate.exact_witness)
    assert_equal(certificate.nodes, 0)
    assert_equal(certificate.terms, 10)
    # Retain a real failed attempt, not invented cumulative counter values.
    # The unchanged ten-term cap is already spent on the stored incumbent.
    with assert_raises(contains="quadrature work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            0.5,
            _narrow_high(),
            location,
            certificate,
            0.0,
            1.0,
            max_terms=10,
            spiral_proof=proof,
        )
    var retained_nodes = certificate.nodes
    var retained_terms = certificate.terms
    assert_true(retained_nodes > 0)
    assert_equal(retained_terms, 10)
    assert_equal(len(certificate.cells), 1)
    _bits(certificate.cells[0].low, 0.5)
    _bits(certificate.cells[0].high, _narrow_high())
    assert_equal(certificate.cells[0].depth, 0)
    for axis in range(3):
        _bits(certificate.point[axis], initial_point[axis])
    # Zero is a supported stricter request, never an enlarged tolerance.
    # The complete original domain has exactly three Float64 stations, so
    # discrete completion gives an independent finite-domain reference.
    _resume_lane_certificate(
        road,
        0,
        0,
        0.5,
        _narrow_high(),
        location,
        certificate,
        0.0,
        1.0,
        max_terms=max_terms,
        spiral_proof=proof,
    )
    assert_true(certificate.exact_witness)
    assert_true(certificate.nodes > retained_nodes)
    assert_true(certificate.terms > retained_terms + 30)
    assert_equal((certificate.terms - retained_terms) % 10, 0)
    assert_true(certificate.nodes <= 16384)
    assert_true(certificate.terms <= 2000000)
    # The original s=0.5 witness is an exact minimum, not tolerance-close.
    # No later equal sample may replace this retained incumbent.
    _bits(certificate.s, 0.5)
    for axis in range(3):
        _bits(certificate.point[axis], initial_point[axis])
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    for station in [Float64(0.5), _next_up(Float64(0.5)), _narrow_high()]:
        var terms = 0
        var scalar = _checked_center(road, 0, 0, station, terms, 2000000)
        assert_true(_wide_point_order(certificate.point, scalar, query) <= 0)
    assert_true(len(certificate.cells) > 0)
    for cell in certificate.cells:
        _bits(cell.low, cell.high)
        assert_true(cell.low >= 0.5 and cell.high <= _narrow_high())
        assert_true(cell.depth >= 1)
    var score = _normalized_square[3](
        certificate.point, query, certificate.scale
    )
    var allowance = _scaled_accuracy(
        road,
        0,
        0,
        0.5,
        _narrow_high(),
        certificate.s,
        score.low,
        certificate.scale,
    )
    assert_true(
        _certificate_within_gap(
            certificate.lower,
            certificate.scale,
            certificate.scale,
            score.high,
            allowance,
        )
    )
    return certificate^


def test_successful_proof_resume_preserves_consumed_work_incumbent_and_cells() raises:
    var road = _acceptance_road()
    var proof = _capture_acceptance_proof(road, 0.5, _narrow_high())
    _assert_acceptance_hit(road, 0.5, _narrow_high(), proof)
    var query = Vector3(0.5, 1.0, 0.0)
    var cached = _complete_resume(road, query, proof)
    var generic = _complete_resume(road, query, None)
    # Both process the same root and adjacent children. The cached path also
    # evaluates an optional expansion before its charged translated fallback.
    assert_equal(cached.nodes, generic.nodes)
    assert_equal(cached.terms, _acceptance_resume_terms(True))
    assert_equal(generic.terms, _acceptance_resume_terms(False))
    assert_equal(len(cached.cells), len(generic.cells))
    _bits(cached.s, generic.s)
    for axis in range(3):
        _bits(cached.point[axis], generic.point[axis])
    for i in range(len(cached.cells)):
        _bits(cached.cells[i].low, generic.cells[i].low)
        _bits(cached.cells[i].high, generic.cells[i].high)
        assert_equal(cached.cells[i].depth, generic.cells[i].depth)
    var nodes = cached.nodes
    var terms = cached.terms
    var cells = len(cached.cells)
    _resume_lane_certificate(
        road,
        0,
        0,
        0.5,
        _narrow_high(),
        query,
        cached,
        0.0,
        1.0,
        spiral_proof=proof,
    )
    assert_equal(cached.nodes, nodes)
    assert_equal(cached.terms, terms)
    assert_equal(len(cached.cells), cells)


def test_optional_resume_work_obeys_exact_cap_and_survives_retry() raises:
    var road = _acceptance_road()
    var proof = _capture_acceptance_proof(road, 0.5, _narrow_high())
    _assert_acceptance_hit(road, 0.5, _narrow_high(), proof)
    var query = Vector3(0.5, 1.0, 0.0)
    var generic_limit = _acceptance_resume_terms(False)
    var cached_limit = _acceptance_resume_terms(True)
    var generic = _complete_resume(road, query, None, generic_limit)
    var cached = _complete_resume(road, query, proof, cached_limit)
    assert_equal(generic.terms, generic_limit)
    assert_equal(cached.terms, cached_limit)
    var limited = _initial_acceptance_certificate(road, query)
    var initial_terms = limited.terms
    var initial_point = limited.point.copy()
    with assert_raises(contains="quadrature work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            0.5,
            _narrow_high(),
            query,
            limited,
            0.0,
            1.0,
            max_terms=cached_limit - 1,
            spiral_proof=proof,
        )
    # Refusal occurs before the final ten-term sample, retaining all work
    # already consumed, including the optional attempt and its fallback.
    assert_equal(limited.terms, cached_limit - (2 * 5))
    assert_true(limited.terms <= cached_limit - 1)
    assert_false(limited.exact_witness)
    assert_equal(len(limited.cells), 1)
    _bits(limited.cells[0].low, 0.5)
    _bits(limited.cells[0].high, _narrow_high())
    for axis in range(3):
        _bits(limited.point[axis], initial_point[axis])
    var spent = limited.terms
    var nodes = limited.nodes
    _resume_lane_certificate(
        road,
        0,
        0,
        0.5,
        _narrow_high(),
        query,
        limited,
        0.0,
        1.0,
        spiral_proof=proof,
    )
    assert_true(limited.exact_witness)
    assert_true(limited.nodes > nodes)
    assert_equal(limited.terms, spent + cached_limit - initial_terms)
    _bits(limited.s, cached.s)
    for axis in range(3):
        _bits(limited.point[axis], cached.point[axis])


def test_optional_expansion_requires_headroom_before_its_work() raises:
    var road = _acceptance_road()
    var proof = _capture_acceptance_proof(road, 0.5, _narrow_high())
    _assert_acceptance_hit(road, 0.5, _narrow_high(), proof)
    var query = Vector3(0.5, 1.0, 0.0)
    var unit = 2 * 5
    var root_terms = _acceptance_resume_terms(False) - (2 * 3) * unit
    for with_proof in [False, True]:
        var optional: Optional[_SpiralDomainProof] = None
        if with_proof:
            optional = proof
        for kind in range(4):
            var limit = root_terms - 1
            if kind == 1:
                limit = root_terms
            elif kind == 2:
                limit = root_terms + unit - 1
            elif kind == 3:
                limit = root_terms + unit
            var certificate = _initial_acceptance_certificate(road, query)
            var initial_point = certificate.point.copy()
            var message = String("interval work limit")
            if kind == 0:
                message = "quadrature work limit"
            # One closed-cell recheck and one root node isolate expansion
            # work before either child's scalar evaluations can mask it.
            with assert_raises(contains=message):
                _resume_lane_certificate(
                    road,
                    0,
                    0,
                    0.5,
                    _narrow_high(),
                    query,
                    certificate,
                    0.0,
                    1.0,
                    max_nodes=2,
                    max_terms=limit,
                    spiral_proof=optional,
                )
            var expected = root_terms
            if kind == 0:
                expected -= unit
            elif with_proof and kind == 3:
                expected += unit
            assert_equal(certificate.nodes, 2)
            assert_equal(certificate.terms, expected)
            assert_true(certificate.terms <= limit)
            assert_false(certificate.exact_witness)
            assert_equal(len(certificate.cells), 1)
            _bits(certificate.cells[0].low, 0.5)
            _bits(certificate.cells[0].high, _narrow_high())
            assert_equal(certificate.cells[0].depth, 0)
            for axis in range(3):
                _bits(certificate.point[axis], initial_point[axis])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
