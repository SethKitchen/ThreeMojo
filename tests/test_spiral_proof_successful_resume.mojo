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


def _complete_resume(
    road: Road,
    location: Vector3,
    proof: Optional[_SpiralDomainProof],
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
    # Both process this same finite root and two adjacent children. Logical
    # GL reservations include the root hit and unchanged expansion work.
    assert_equal(cached.nodes, generic.nodes)
    assert_equal(cached.terms, generic.terms)
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
