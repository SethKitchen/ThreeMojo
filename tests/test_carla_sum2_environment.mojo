# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Test-process-only CPU modes, linked with tools/fixtures/carla_sum2_fp_state.c.

The saved control register is restored on success or exception. This suite
must run on each supported CPU; x86 success does not qualify Apple Silicon.
"""

from tests._winner_seed_recovery_fp_controls import (
    _winner_seed_fp_fixture,
    _assert_winner_seed_refuses_hostile_state,
)
from extensions.carla.curve_sum2 import _sum2_supported_environment, _sum2_error
from extensions.carla.curve_bounds import (
    _spiral_jet,
    _lane_jet_with_proof,
    _try_proof_expansion_jet,
    _lane_jet_capture,
)
from extensions.carla.spiral_moment_table import (
    _SpiralMomentProof as TableProof,
    _try_spiral_moment_expansion as table_expansion,
)
from extensions.carla.spiral_moment_proof import (
    _try_build_spiral_moments,
    _try_spiral_moment_expansion as dynamic_expansion,
)
from tests._spiral_grouped_fp_controls import (
    _assert_grouped_refuses_hostile_state,
)
from tests._spiral_grouped_lane_fp_controls import (
    _assert_grouped_lane_refuses_hostile_state,
)
from tests._sample_dispatch_controls import (
    _dispatch_road,
    _assert_dispatch_refuses_hostile_state,
)
from tests._objective_model_fp_controls import (
    _objective_fp_fixture,
    _assert_objective_refuses_hostile_state,
)
from tests._lazy_taylor_controls import _diagonal_road
from tests._spiral_acceptance_controls import _capture_acceptance_proof
from extensions.carla.spiral_domain_proof import (
    _SpiralRootCapture,
    _try_pack_spiral_proof,
)
from extensions.carla.curve_interval import _Jet
from extensions.carla.lane_geometry import _lane_geometry_pos_at
from extensions.carla.lane_refinement import (
    _refine_lane_certificate,
    _resume_lane_certificate,
    _lane_certificate_contains,
)
from extensions.carla.map_builder import MapBuilder
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.road_info import RoadId
from tests.test_carla_cross_candidate_certificates import _sampled_road
from math.vector3 import Vector3
from std.ffi import external_call
from std.math import isfinite
from std.testing import TestSuite, assert_raises, assert_true, assert_equal


def test_sum2_refuses_unsupported_cpu_state_and_restores_controls() raises:
    var modes = Int(external_call["sum2_test_mode_count", Int32]())
    assert_true(modes == 5 or modes == 7)
    print("CPU_MODE_COUNT", modes)
    var map = load_opendrive_file("assets/carla/town.xodr")
    var winner_seed_road = map.roads[map.road_index(RoadId(5))].copy()
    var winner_seed_fixture = _winner_seed_fp_fixture(winner_seed_road)
    var query = Vector3(19.200000762939453, -99.26249694824219, 0)
    var waypoint = map.certified_closest_waypoint_on_road(query).value()
    var road = _sampled_road(1.0)
    var certificate = _refine_lane_certificate(
        road, 0, 0, 0.5, 0.5, Vector3(0, 0, 0), 0.5, 0.0
    )
    assert_true(certificate.exact_witness)
    var nodes = certificate.nodes
    var terms = certificate.terms
    var builder = MapBuilder()
    builder.roads.append(_sampled_road(1.0))
    var segments = len(map._segments)
    var geometry = (
        map.roads[map.road_index(RoadId(5))].info.geometries[0].geometry.copy()
    )
    var proof_road = _diagonal_road()
    var cached = _capture_acceptance_proof(proof_road, 0.4, 0.7)
    var proof_geometry = proof_road.info.geometries[0].geometry.copy()
    var d = _Jet.variable(0.5, 0.5)
    var table = TableProof(cached.first_count)
    var work = 0
    var dynamic = (
        _try_build_spiral_moments(cached.first_count, work, 10000)
        .value()
        .copy()
    )
    var captured = _SpiralRootCapture()
    _ = _lane_jet_capture(proof_road, 0, 0, 0.4, 0.7, captured)
    var normal_terms = 7
    var normal_units = 11
    assert_true(
        Bool(
            _try_pack_spiral_proof(
                proof_road, 0.4, 0.7, 0, captured, 0, normal_terms, normal_units
            )
        )
    )
    var counts = (cached.first_count, cached.first_count)
    assert_true(
        Bool(
            table_expansion(table, proof_geometry, d, counts, Vector3(0, 0, 0))
        )
    )
    assert_true(
        Bool(
            dynamic_expansion(
                dynamic, proof_geometry, d, counts, Vector3(0, 0, 0)
            )
        )
    )
    var sampled_dispatch_road = _dispatch_road()
    var objective_fixture = _objective_fp_fixture()
    for repeat in range(2):
        for mode in range(1, modes):
            assert_true(_sum2_supported_environment())
            var original = external_call["sum2_test_set_mode", UInt64](
                Int32(mode)
            )
            try:
                var mask = external_call["sum2_test_control_mask", UInt64]()
                var actual = external_call["sum2_test_get_state", UInt64]()
                var expected = external_call["sum2_test_mode_bits", UInt64](
                    Int32(mode)
                )
                assert_equal(actual & mask, expected)
                assert_true(not _sum2_supported_environment())
                _assert_winner_seed_refuses_hostile_state(
                    winner_seed_road,
                    winner_seed_fixture[0],
                    winner_seed_fixture[1],
                )
                _assert_objective_refuses_hostile_state(
                    objective_fixture[0],
                    objective_fixture[1],
                    objective_fixture[2],
                )
                _assert_dispatch_refuses_hostile_state(sampled_dispatch_road)
                _assert_grouped_lane_refuses_hostile_state(proof_road, cached)
                _assert_grouped_refuses_hostile_state(
                    proof_geometry, d, cached.first_count
                )
                assert_true(not isfinite(_sum2_error(1.0, 0.0, 5)))
                var bound = _spiral_jet(
                    geometry, _Jet.variable(1.0, 1.1), 3, Vector3(0, 0, 0)
                )
                assert_true(not isfinite(bound[0].error))
                var cached_bound = _lane_jet_with_proof(
                    proof_road, 0, 0, 0.4, 0.7, 0.4, 0.7, cached
                )
                assert_true(not cached_bound[0].rounded_value().is_finite())
                var expansion = _try_proof_expansion_jet(
                    proof_road,
                    0,
                    0,
                    0.5,
                    Vector3(0, 0, 0),
                    1.0,
                    0.4,
                    0.7,
                    cached,
                )
                if expansion:
                    assert_true(not expansion.value().value.is_finite())
                assert_true(
                    not Bool(
                        table_expansion(
                            table, proof_geometry, d, counts, Vector3(0, 0, 0)
                        )
                    )
                )
                assert_true(
                    not Bool(
                        dynamic_expansion(
                            dynamic, proof_geometry, d, counts, Vector3(0, 0, 0)
                        )
                    )
                )
                var declined_work = 7
                assert_true(
                    not Bool(
                        _try_build_spiral_moments(
                            cached.first_count, declined_work, 10000
                        )
                    )
                )
                assert_equal(declined_work, 7)
                var rejected_terms = 7
                var rejected_units = 11
                assert_true(
                    not Bool(
                        _try_pack_spiral_proof(
                            proof_road,
                            0.4,
                            0.7,
                            0,
                            captured,
                            0,
                            rejected_terms,
                            rejected_units,
                        )
                    )
                )
                assert_equal(rejected_terms, 7)
                assert_equal(rejected_units, 11)

                with assert_raises(contains="Canonical lane arithmetic"):
                    _ = _lane_geometry_pos_at(geometry, 1.0)
                with assert_raises(contains="Canonical lane arithmetic"):
                    _ = map.certified_waypoint(query)
                with assert_raises(contains="Canonical lane arithmetic"):
                    _ = map.certified_closest_waypoint_on_road(query)
                with assert_raises(contains="Canonical lane arithmetic"):
                    _ = map.compute_transform(waypoint)
                with assert_raises(contains="Canonical lane arithmetic"):
                    _ = builder.build()
                with assert_raises(contains="Canonical lane arithmetic"):
                    map._create_segments()
                with assert_raises(contains="Canonical lane arithmetic"):
                    _resume_lane_certificate(
                        road,
                        0,
                        0,
                        0.5,
                        0.5,
                        Vector3(0, 0, 0),
                        certificate,
                        0.0,
                        1.0,
                    )
                with assert_raises(contains="Canonical lane arithmetic"):
                    _ = _lane_certificate_contains(
                        road, 0, 0, Vector3(0, 0, 0), certificate
                    )
                with assert_raises(contains="Canonical lane arithmetic"):
                    _ = _refine_lane_certificate(
                        road, 0, 0, 0.5, 0.5, Vector3(0, 0, 0), 0.5, 0.0
                    )
            except error:
                external_call["sum2_test_restore_mode", NoneType](original)
                raise error
            external_call["sum2_test_restore_mode", NoneType](original)
            assert_equal(
                external_call["sum2_test_get_state", UInt64](), original
            )
            assert_true(_sum2_supported_environment())
            assert_equal(certificate.nodes, nodes)
            assert_equal(certificate.terms, terms)
            assert_equal(len(builder.roads), 1)
            assert_equal(len(map._segments), segments)
            print("ENTRY_MODE_PASS", repeat, mode)
    var final = map.certified_closest_waypoint_on_road(query).value()
    assert_equal(final.s, waypoint.s)
    print("RESTORED_QUERY", final.s)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
