# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Exact-fit optional work retains compulsory child and validation capacity."""

from extensions.carla.curve_objective_model import (
    _objective_followup_room,
    _objective_recheck_room,
)
from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.lane_refinement import _resume_lane_certificate
from extensions.carla.spiral_grouped_lane import _try_grouped_lane_jet
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_raises,
)
from tests._lazy_taylor_controls import _diagonal_road, _whole_certificate
from tests._spiral_acceptance_controls import _capture_acceptance_proof
from tests.test_spiral_lazy_taylor_paths import _enlarge


def test_cache_followup_exact_fit_and_one_short_tables() raises:
    for nodes in [0, 9, 9223372036854775803]:
        for terms in [0, 17]:
            for work in [0, 1, 10, 205]:
                for center in [0, 1, 5]:
                    # Two children and their two possible closure rechecks;
                    # each child has three edge witnesses and one domain.
                    var node_cap = nodes + 4
                    var term_cap = terms + center + 8 * work
                    assert_true(
                        _objective_followup_room(
                            nodes, terms, node_cap, term_cap, work, center
                        )
                    )
                    assert_false(
                        _objective_followup_room(
                            nodes, terms, node_cap - 1, term_cap, work, center
                        )
                    )
                    assert_false(
                        _objective_followup_room(
                            nodes, terms, node_cap, term_cap - 1, work, center
                        )
                    )
    comptime largest = 9223372036854775807
    assert_true(
        _objective_followup_room(
            largest - 4, largest - 17, largest, largest, 2, 1
        )
    )
    assert_false(_objective_followup_room(0, 0, 4, largest, largest, 0))
    assert_false(_objective_followup_room(0, 0, 4, largest, 1, largest))
    for bad in [
        (-1, 0, 4, 8, 1, 0),
        (0, -1, 4, 8, 1, 0),
        (5, 0, 4, 8, 1, 0),
        (0, 9, 4, 8, 1, 0),
        (0, 0, -9223372036854775807 - 1, 8, 1, 0),
        (0, 0, 4, -9223372036854775807 - 1, 1, 0),
        (0, 0, 4, 8, -1, 0),
        (0, 0, 4, 8, 1, -1),
    ]:
        assert_false(
            _objective_followup_room(
                bad[0], bad[1], bad[2], bad[3], bad[4], bad[5]
            )
        )


def test_cached_closure_exact_recheck_node_and_one_short() raises:
    for nodes in [0, 9, 9223372036854775806]:
        assert_true(_objective_recheck_room(nodes, nodes + 1))
        assert_false(_objective_recheck_room(nodes, nodes))
        assert_false(_objective_recheck_room(nodes, nodes - 1))
    assert_false(_objective_recheck_room(-1, 5))
    assert_false(_objective_recheck_room(0, -9223372036854775807 - 1))


def test_grouped_attempt_declines_before_spending_the_required_recheck() raises:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var query: Array[Float64, 3] = [
        Float64(location.x),
        Float64(location.y),
        Float64(location.z),
    ]
    var proof = _enlarge(_capture_acceptance_proof(road, 0.4, 0.7))
    assert_equal(proof.first_count, 2)
    assert_equal(proof.last_count, 2)
    var reference = _whole_certificate(road, location)
    _resume_lane_certificate(
        road,
        0,
        0,
        0.4,
        0.7,
        location,
        reference,
        1000000.0,
        1.0,
        max_nodes=3,
        spiral_proof=proof,
    )
    assert_equal(reference.nodes, 3)
    assert_equal(reference.terms, 500)
    for node_cap in [2, 3, 4, 5]:
        var certificate = _whole_certificate(road, location)
        if node_cap == 2:
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
                    max_nodes=node_cap,
                    spiral_proof=proof,
                )
            assert_equal(certificate.nodes, 2)
            assert_equal(certificate.terms, 500)
        else:
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
                max_nodes=node_cap,
                spiral_proof=proof,
            )
            assert_equal(certificate.nodes, 3 if node_cap == 3 else 4)
            assert_equal(certificate.terms, 500 if node_cap == 3 else 506)
            assert_equal(
                _wide_point_order(certificate.point, reference.point, query), 0
            )
            assert_false(certificate.exact_witness)
            assert_equal(len(certificate.cells), 1)
            assert_equal(certificate.cells[0].low, 0.4)
            assert_equal(certificate.cells[0].high, 0.7)
            assert_equal(certificate.cells[0].depth, 0)


def test_two_panel_grouped_refresh_returns_its_separately_charged_bound() raises:
    var road = _diagonal_road()
    var nodes = 0
    var terms = 500
    var result = _try_grouped_lane_jet(
        road, 0, 0, 0.4, 0.7, nodes, terms, 100, 2000000
    )
    assert_true(Bool(result))
    assert_equal(nodes, 1)
    # Two groups, three exact stored-weight multiplicities per group.
    assert_equal(terms, 506)
    assert_true(result.value()[0].rounded_value().is_finite())
    assert_true(result.value()[1].rounded_value().is_finite())
    assert_true(result.value()[2].rounded_value().is_finite())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
