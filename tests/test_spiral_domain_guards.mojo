# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Refusal, association and unchanged logical-budget controls.

No proof authorizes geometry mutation or moves a payload between Map owners.
Malformed payloads below are explicit adversarial private-API controls.
"""

from extensions.carla.curve_bounds import (
    _geometry_distance, _lane_jet, _lane_jet_with_proof, _reference_work,
    _spiral_counts,
)
from extensions.carla.curve_distance import _normalized_square
from extensions.carla.curve_interval import _Interval, _Jet, _next_down, _next_up
from extensions.carla.geometry import LINE
from extensions.carla.lane_refinement import (
    _ClosedInterval, _LaneCertificate, _refine_lane_certificate,
    _resume_lane_certificate,
)
from extensions.carla.road import Road
from extensions.carla.road_info import RoadInfoGeometry
from extensions.carla.spiral_domain_proof import (
    _SpiralDomainProof, _SpiralRootCapture, _find_spiral_proof,
    _spiral_proof_matches, _try_pack_spiral_proof,
)
from math.vector3 import Vector3
from std.math import inf
from std.testing import TestSuite, assert_equal, assert_true, assert_false, assert_raises
from tests._spiral_domain_controls import (
    _bits, _point_bits, _f64, _geometry, _road, _capture, _proof,
)


def test_optional_allowance_below_at_and_above_both_branch_costs() raises:
    var road = _road(_geometry())
    for interval in [_Interval(2.125, 2.25), _Interval(1.5, 2.25)]:
        var captured = _capture(road, interval.low, interval.high)
        var branches = 1 if captured.first_count == captured.last_count else 2
        var extra = 16 + 128 * branches
        for delta in [-1, 0, 1]:
            var terms = 17
            var units = 9
            var found = _try_pack_spiral_proof(
                road, interval.low, interval.high, 0, captured, 0, terms, units,
                max_terms=17 + extra + delta, max_proof_units=9 + extra,
            )
            assert_equal(Bool(found), delta >= 0)
            assert_equal(terms, 17 + extra if delta >= 0 else 17)
            assert_equal(units, 9 + extra if delta >= 0 else 9)
            terms = 17
            units = 9
            found = _try_pack_spiral_proof(
                road, interval.low, interval.high, 0, captured, 0, terms, units,
                max_terms=17 + extra, max_proof_units=9 + extra + delta,
            )
            assert_equal(Bool(found), delta >= 0)
            assert_equal(terms, 17 + extra if delta >= 0 else 17)
            assert_equal(units, 9 + extra if delta >= 0 else 9)


def test_payload_cap_reserves_only_complete_eighty_byte_entries() raises:
    var road = _road(_geometry())
    var captured = _capture(road, 1.5, 2.25)
    assert_equal(captured.last_count - captured.first_count, 1)
    for cap in [-1, 0, 79, 80, 81, 159, 160, 161]:
        for count in [0, 1, 2]:
            var terms = 17
            var units = 9
            var found = _try_pack_spiral_proof(
                road, 1.5, 2.25, 0, captured, count, terms, units,
                max_payload_bytes=cap,
            )
            var eligible = cap >= 80 and count < cap // 80
            assert_equal(Bool(found), eligible)
            assert_equal(terms, 289 if eligible else 17)
            assert_equal(units, 281 if eligible else 9)
            if found:
                assert_equal(found.value().first_count, 3)
                assert_equal(found.value().last_count, 4)


def test_invalid_allowance_states_leave_counters_unchanged() raises:
    var road = _road(_geometry())
    var captured = _capture(road, 2.125, 2.25)
    for kind in range(6):
        var terms = -1 if kind == 0 else 17
        var units = -1 if kind == 1 else 9
        var initial_terms = terms
        var initial_units = units
        var found = _try_pack_spiral_proof(
            road, 2.125, 2.25, -1 if kind == 4 else 0,
            captured, -1 if kind == 5 else 0, terms, units,
            max_terms=16 if kind == 2 else 2000000,
            max_proof_units=8 if kind == 3 else 1048576,
        )
        assert_false(Bool(found))
        assert_equal(terms, initial_terms)
        assert_equal(units, initial_units)


def test_capture_station_record_and_error_metadata_must_be_complete() raises:
    var road = _road(_geometry())
    var original = _capture(road, 2.125, 2.25)
    for kind in range(12):
        var captured = original
        if kind == 0:
            captured.first_count = 0
        elif kind == 1:
            captured.last_count = 65
        elif kind == 2:
            captured.last_count = captured.first_count - 1
        elif kind == 3:
            captured.last_count = captured.first_count + 2
        elif kind == 4:
            captured.low = _next_down(captured.low)
        elif kind == 5:
            captured.high = _next_up(captured.high)
        elif kind == 6:
            captured.record_at = 1
        elif kind == 7:
            captured.first_x_error = -1.0
        elif kind == 8:
            captured.last_y_error = inf[DType.float64]()
        elif kind == 9:
            captured.first_y_error = _f64(UInt64(0x7FF8000000000001))
        elif kind == 10:
            captured.d.first = _Interval.whole()
        else:
            captured.d.second = _Interval.whole()
        var terms = 17
        var units = 9
        assert_false(Bool(_try_pack_spiral_proof(
            road, 2.125, 2.25, 0, captured, 0, terms, units,
        )))
        # Counts are rejected before reservation. Other rejection paths have
        # already performed optional validation, and must keep that debit.
        assert_equal(terms, 17 if kind < 4 else 161)
        assert_equal(units, 9 if kind < 4 else 153)


def _root_miss(road: Road, low: Float64, high: Float64) raises:
    var captured = _capture(road, low, high)
    var terms = 0
    var units = 0
    assert_false(Bool(_try_pack_spiral_proof(
        road, low, high, 0, captured, 0, terms, units,
    )))
    _point_bits(
        _lane_jet_with_proof(road, 0, 0, low, high, low, high, None),
        _lane_jet(road, 0, 0, low, high),
    )


def test_clamp_joins_and_count65_keep_generic_fallback() raises:
    var road = _road(_geometry())
    for interval in [_Interval(0.0, 0.0), _Interval(-0.0, 0.0),
                     _Interval(0.0, 0.125), _Interval(19.875, 20.0),
                     _Interval(20.0, 20.0), _Interval(20.0, 21.0)]:
        _root_miss(road, interval.low, interval.high)
    var geometry = _geometry()
    geometry.length = 128.0
    geometry.curvature_end = 0.0
    var unsupported = _road(geometry^)
    var d = _geometry_distance(unsupported.info.geometries[0].geometry, _Jet.variable(63.5, 63.5))
    var counts = _spiral_counts(unsupported.info.geometries[0].geometry, d)
    assert_equal(counts[0], 65)
    assert_equal(counts[1], 65)
    _root_miss(unsupported, 63.5, 63.5)


def test_original_mixed_quadrant_count22_root_is_charged_then_rejected() raises:
    var geometry = _geometry()
    geometry.curvature_end = 0.1
    var road = _road(geometry^)
    var captured = _capture(road, 19.0, 19.0)
    assert_equal(captured.first_count, 22)
    assert_equal(captured.last_count, 22)
    var terms = 17
    var units = 9
    assert_false(Bool(_try_pack_spiral_proof(
        road, 19.0, 19.0, 0, captured, 0, terms, units,
    )))
    assert_equal(terms, 161)
    assert_equal(units, 153)
    _root_miss(road, 19.0, 19.0)


def test_unsupported_geometry_and_subnormal_clamp_uncertainty_are_misses() raises:
    for kind in range(6):
        var geometry = _geometry()
        if kind == 0:
            geometry.kind = LINE
        elif kind == 1:
            geometry.heading = 0.125
        elif kind == 2:
            geometry.curvature_start = 0.001
        elif kind == 3:
            geometry.x = inf[DType.float64]()
        elif kind == 4:
            geometry.y = -inf[DType.float64]()
        else:
            geometry.curvature_end = inf[DType.float64]()
        var road = _road(geometry^)
        _root_miss(road, 2.125, 2.25)
    var tiny = _f64(UInt64(1))
    var road = _road(_geometry(), tiny)
    # A nonzero subnormal record subtraction carries its actual rounding
    # allowance into the clamp selector. Do not assume all tiny roots miss.
    _root_miss(road, tiny + tiny, tiny + tiny + tiny)


def test_sparse_associations_have_exact_hits_and_readonly_misses() raises:
    var road = _road(_geometry())
    var proofs = List[_SpiralDomainProof]()
    for segment in [0, 4, 19]:
        proofs.append(_proof(road, 2.125, 2.25, segment))
    for segment in [-1, 0, 1, 3, 4, 5, 18, 19, 20]:
        var found = _find_spiral_proof(proofs, segment)
        var expected = segment == 0 or segment == 4 or segment == 19
        assert_equal(Bool(found), expected)
        if found:
            assert_equal(found.value().segment_index, segment)
            _bits(found.value().first_x_error, proofs[0].first_x_error)
        assert_equal(len(proofs), 3)
    var empty = List[_SpiralDomainProof]()
    assert_false(Bool(_find_spiral_proof(empty, 0)))


def test_query_rejects_missing_counts_bad_errors_and_stale_record_index() raises:
    var road = _road(_geometry())
    road.info.geometries.append(RoadInfoGeometry(2.0, _geometry()))
    var proof = _proof(road, 2.125, 2.25)
    assert_equal(proof.record_at, 1)
    var original = _lane_jet(road, 0, 0, 2.1875, 2.1875)
    for kind in range(9):
        var bad = proof
        if kind == 0:
            bad.record_at = 0
        elif kind == 1:
            bad.first_count = 63
            bad.last_count = 64
        elif kind == 2:
            bad.first_count = 0
        elif kind == 3:
            bad.last_count = 65
        elif kind == 4:
            bad.first_x_error = -1.0
        elif kind == 5:
            bad.last_y_error = inf[DType.float64]()
        elif kind == 6:
            bad.first_y_error = _f64(UInt64(0x7FF8000000000001))
        elif kind == 7:
            bad.rounded_d = _Interval(0.2, 0.1)
        else:
            bad.rounded_d = _Interval(0.0, 20.0)
        _point_bits(_lane_jet_with_proof(road, 0, 0, 2.1875, 2.1875, 2.125, 2.25, bad), original)
    _point_bits(_lane_jet_with_proof(road, 0, 0, 2.1875, 2.1875, 2.125, 2.25, None), original)


def test_query_station_and_actual_rounded_distance_containment_are_both_required() raises:
    var road = _road(_geometry())
    var proof = _proof(road, 2.125, 2.25)
    ref geometry = road.info.geometries[0].geometry
    var d = _geometry_distance(geometry, _Jet.variable(2.1875, 2.1875))
    var counts = _spiral_counts(geometry, d)
    assert_true(_spiral_proof_matches(proof, geometry, 0, 2.1875, 2.1875, 2.125, 2.25, d, counts))
    assert_false(_spiral_proof_matches(proof, geometry, 0, 2.0, 2.1875, 2.125, 2.25, d, counts))
    assert_false(_spiral_proof_matches(proof, geometry, 0, 2.1875, 2.5, 2.125, 2.25, d, counts))
    assert_false(_spiral_proof_matches(proof, geometry, 0, 2.25, 2.125, 2.125, 2.25, d, counts))
    var outside = d
    outside.error = 1.0
    assert_false(_spiral_proof_matches(proof, geometry, 0, 2.1875, 2.1875, 2.125, 2.25, outside, counts))
    outside = d
    outside.first = _Interval.whole()
    assert_false(_spiral_proof_matches(proof, geometry, 0, 2.1875, 2.1875, 2.125, 2.25, outside, counts))
    for station in [2.0, 2.5]:
        _point_bits(_lane_jet_with_proof(road, 0, 0, station, station, 2.125, 2.25, proof), _lane_jet(road, 0, 0, station, station))
    assert_equal(_reference_work(road, 0.0, 20.0), -1)
    _point_bits(_lane_jet_with_proof(road, 0, 0, 0.0, 20.0, 2.125, 2.25, proof), _lane_jet(road, 0, 0, 0.0, 20.0))


def test_refine_scalar_witness_below_at_above_budget_is_unchanged() raises:
    var road = _road(_geometry())
    var proof = _proof(road, 2.125, 2.25)
    var station = Float64(2.1875)
    var work = _reference_work(road, station, station)
    assert_equal(work, 20)
    var location = Vector3(0, 0, 0)
    var score = road._lane_distance_squared(0, 0, station, location)
    with assert_raises(contains="quadrature work limit"):
        _ = _refine_lane_certificate(road, 0, 0, station, station, location, station, score, max_terms=work - 1)
    with assert_raises(contains="quadrature work limit"):
        _ = _refine_lane_certificate(road, 0, 0, station, station, location, station, score, max_terms=work - 1, spiral_proof=proof)
    for cap in [work, work + 1]:
        var generic = _refine_lane_certificate(road, 0, 0, station, station, location, station, score, max_terms=cap)
        var cached = _refine_lane_certificate(road, 0, 0, station, station, location, station, score, max_terms=cap, spiral_proof=proof)
        assert_true(cached.exact_witness)
        assert_equal(cached.nodes, generic.nodes)
        assert_equal(cached.terms, work)
        assert_equal(cached.terms, generic.terms)
        _bits(cached.s, generic.s)
        for axis in range(3):
            _bits(cached.point[axis], generic.point[axis])


def test_refine_early_domain_refusals_do_not_spend_the_proof_as_free_gl_work() raises:
    var road = _road(_geometry())
    var proof = _proof(road, 2.125, 2.25)
    var location = Vector3(0, 0, 0)
    var seed = Float64(2.1875)
    var score = road._lane_distance_squared(0, 0, seed, location)
    # Four scalar witnesses cost 80 logical terms. The root domain costs
    # another 20 even on a proof hit; its next local witness is not free.
    for cap in [0, 19, 20, 79, 80, 99, 100, 101]:
        with assert_raises(contains="quadrature work limit"):
            _ = _refine_lane_certificate(road, 0, 0, 2.125, 2.25, location, seed, score, max_terms=cap)
        with assert_raises(contains="quadrature work limit"):
            _ = _refine_lane_certificate(road, 0, 0, 2.125, 2.25, location, seed, score, max_terms=cap, spiral_proof=proof)


def _resume_input(road: Road) raises -> _LaneCertificate:
    var point = road._lane_center(0, 0, 2.1875)
    var zero: Array[Float64, 3] = [0.0, 0.0, 0.0]
    var upper = _normalized_square[3](point, zero, 1.0).high
    var cells: List[_ClosedInterval] = [_ClosedInterval(2.125, 2.25, 3, 0.0, 1.0)]
    return _LaneCertificate(2.1875, point^, 1.0, 0.0, upper, False, cells^, 7, 11)


def test_resume_keeps_cumulative_work_and_early_refusal_boundaries() raises:
    var road = _road(_geometry())
    var proof = _proof(road, 2.125, 2.25)
    for cap in [11, 30, 31, 70, 71, 90, 91, 92]:
        var generic = _resume_input(road)
        var cached = _resume_input(road)
        with assert_raises(contains="quadrature work limit"):
            _resume_lane_certificate(road, 0, 0, 2.125, 2.25, Vector3(0, 0, 0), generic, 0.0, 1.0, max_terms=cap)
        with assert_raises(contains="quadrature work limit"):
            _resume_lane_certificate(road, 0, 0, 2.125, 2.25, Vector3(0, 0, 0), cached, 0.0, 1.0, max_terms=cap, spiral_proof=proof)
        assert_equal(cached.terms, generic.terms)
        assert_equal(cached.nodes, generic.nodes)
        assert_true(cached.terms >= 11 and cached.terms <= cap)
        assert_equal(len(cached.cells), len(generic.cells))
        _bits(cached.s, generic.s)
        for axis in range(3):
            _bits(cached.point[axis], generic.point[axis])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
