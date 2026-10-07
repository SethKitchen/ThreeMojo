# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Independent finite-leaf replacement controls, preserving the legacy test.

The legacy successful-resume file remains unchanged beside this file. Its
three-parameter interval now exercises finite enumeration, not Taylor work.
"""

from extensions.carla.curve_bounds import _reference_work
from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.lane_refinement import (
    _resume_lane_certificate,
    _checked_center,
)
from extensions.carla.spiral_domain_proof import _SpiralDomainProof
from extensions.carla.curve_interval import _next_up
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_raises,
)
from tests._spiral_acceptance_controls import (
    _acceptance_road,
    _narrow_high,
    _capture_acceptance_proof,
    _assert_acceptance_hit,
    _initial_acceptance_certificate,
)
from tests._spiral_domain_controls import _bits


def test_three_parameter_resume_charges_one_leaf_and_three_actual_centers() raises:
    var road = _acceptance_road()
    var high = _narrow_high()
    var proof = _capture_acceptance_proof(road, 0.5, high)
    _assert_acceptance_hit(road, 0.5, high, proof)
    var location = Vector3(0.5, 1, 0)
    var query: Array[Float64, 3] = [0.5, 1.0, 0.0]
    var unit = _reference_work(road, 0.5, high)
    assert_equal(unit, 10)
    for cached in [False, True]:
        var optional: Optional[_SpiralDomainProof] = None
        if cached:
            optional = proof
        var certificate = _initial_acceptance_certificate(road, location)
        var first_point = certificate.point.copy()
        # A real refused attempt retains its recheck and leaf node. It
        # cannot evaluate a scalar because the ten-term incumbent spent all.
        with assert_raises(contains="quadrature work limit"):
            _resume_lane_certificate(
                road,
                0,
                0,
                0.5,
                high,
                location,
                certificate,
                0.0,
                1.0,
                max_terms=unit,
                spiral_proof=optional,
            )
        assert_equal(certificate.nodes, 2)
        assert_equal(certificate.terms, unit)
        assert_false(certificate.exact_witness)
        assert_equal(len(certificate.cells), 1)
        assert_equal(certificate.cells[0].depth, 0)
        _bits(certificate.cells[0].low, 0.5)
        _bits(certificate.cells[0].high, high)
        _resume_lane_certificate(
            road,
            0,
            0,
            0.5,
            high,
            location,
            certificate,
            0.0,
            1.0,
            max_nodes=4,
            max_terms=(1 + 3) * unit,
            spiral_proof=optional,
        )
        assert_true(certificate.exact_witness)
        assert_equal(certificate.nodes, 4)
        assert_equal(certificate.terms, (1 + 3) * unit)
        _bits(certificate.s, 0.5)
        for axis in range(3):
            _bits(certificate.point[axis], first_point[axis])
        # Independent exhaustive reference, using all three actual stations.
        for station in [Float64(0.5), _next_up(Float64(0.5)), high]:
            var terms = 0
            var point = _checked_center(road, 0, 0, station, terms, unit)
            assert_equal(terms, unit)
            assert_true(_wide_point_order(certificate.point, point, query) <= 0)
        for cell in certificate.cells:
            _bits(cell.low, cell.high)
            assert_true(cell.low >= 0.5 and cell.high <= high)
            assert_equal(cell.depth, 1)
        var nodes = certificate.nodes
        var terms = certificate.terms
        _resume_lane_certificate(
            road,
            0,
            0,
            0.5,
            high,
            location,
            certificate,
            0.0,
            1.0,
            max_nodes=nodes,
            max_terms=terms,
            spiral_proof=optional,
        )
        assert_equal(certificate.nodes, nodes)
        assert_equal(certificate.terms, terms)


def test_leaf_exact_and_one_short_term_caps_preserve_retry_work() raises:
    var road = _acceptance_road()
    var high = _narrow_high()
    var proof = _capture_acceptance_proof(road, 0.5, high)
    var location = Vector3(0.5, 1, 0)
    for cached in [False, True]:
        var optional: Optional[_SpiralDomainProof] = None
        if cached:
            optional = proof
        var certificate = _initial_acceptance_certificate(road, location)
        _resume_lane_certificate(
            road,
            0,
            0,
            0.5,
            high,
            location,
            certificate,
            0.0,
            1.0,
            max_nodes=2,
            max_terms=40,
            spiral_proof=optional,
        )
        assert_true(certificate.exact_witness)
        assert_equal(certificate.nodes, 2)
        assert_equal(certificate.terms, 40)
        var limited = _initial_acceptance_certificate(road, location)
        with assert_raises(contains="quadrature work limit"):
            _resume_lane_certificate(
                road,
                0,
                0,
                0.5,
                high,
                location,
                limited,
                0.0,
                1.0,
                max_nodes=2,
                max_terms=39,
                spiral_proof=optional,
            )
        assert_equal(limited.nodes, 2)
        assert_equal(limited.terms, 30)
        assert_false(limited.exact_witness)
        assert_equal(len(limited.cells), 1)
        _bits(limited.cells[0].low, 0.5)
        _bits(limited.cells[0].high, high)
        # The safe old cover must be searched again; already spent samples
        # stay charged. A retry therefore adds thirty terms, not ten.
        _resume_lane_certificate(
            road,
            0,
            0,
            0.5,
            high,
            location,
            limited,
            0.0,
            1.0,
            max_nodes=4,
            max_terms=60,
            spiral_proof=optional,
        )
        assert_true(limited.exact_witness)
        assert_equal(limited.nodes, 4)
        assert_equal(limited.terms, 60)
        _bits(limited.s, certificate.s)
        for axis in range(3):
            _bits(limited.point[axis], certificate.point[axis])


def test_leaf_node_and_depth_boundaries_do_not_claim_optional_expansion() raises:
    var road = _acceptance_road()
    var high = _narrow_high()
    var proof = _capture_acceptance_proof(road, 0.5, high)
    var location = Vector3(0.5, 1, 0)
    var limited = _initial_acceptance_certificate(road, location)
    with assert_raises(contains="interval work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            0.5,
            high,
            location,
            limited,
            0.0,
            1.0,
            max_nodes=1,
            max_terms=40,
            spiral_proof=proof,
        )
    assert_equal(limited.nodes, 1)
    assert_equal(limited.terms, 10)
    var deeper = _initial_acceptance_certificate(road, location)
    deeper.cells[0].depth = 7
    _resume_lane_certificate(
        road,
        0,
        0,
        0.5,
        high,
        location,
        deeper,
        0.0,
        1.0,
        max_nodes=2,
        max_terms=40,
        max_depth=8,
        spiral_proof=proof,
    )
    assert_true(deeper.exact_witness)
    for cell in deeper.cells:
        assert_equal(cell.depth, 8)
    limited = _initial_acceptance_certificate(road, location)
    with assert_raises(contains="numerical accuracy limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            0.5,
            high,
            location,
            limited,
            0.0,
            1.0,
            max_depth=0,
            spiral_proof=proof,
        )
    assert_false(limited.exact_witness)
    assert_equal(limited.cells[0].depth, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
