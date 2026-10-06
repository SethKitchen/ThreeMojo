# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Single-load town integration for the immutable SPIRAL proof pool.

Exercise the same certificate search and strict classifier as Map.waypoint.
Reuse each returned certificate for classification to avoid a second identical
search. No duration gate or original numerical/work budget is changed.
"""

from extensions.carla.curve_bounds import _lane_jet_with_proof
from extensions.carla.lane_distance import _normalized_square
from extensions.carla.lane_refinement import (
    _certificate_within_gap, _checked_center, _lane_certificate_contains,
    _scaled_accuracy,
)
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.road_info import RoadId, LaneId, LANE_DRIVING
from extensions.carla.spiral_domain_proof import _find_spiral_proof
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true
from tests._spiral_domain_controls import _bits, _interval_bits, _canonical_contains


def test_town_proof_membership_hot_queries_classification_and_readonly_pool() raises:
    var constructed = load_opendrive_file("assets/carla/town.xodr")
    # Ownership moves the pool with the index. No proof is transplanted to a
    # second Map, and this test does not promise detection of road mutation.
    var map = constructed^
    assert_equal(map.segment_count(), 987)
    assert_true(len(map._spiral_proofs) > 0)
    assert_true(map._spiral_proof_units > 0)
    var before = map._spiral_proofs.copy()
    var units = map._spiral_proof_units
    var previous = -1
    for proof in map._spiral_proofs:
        assert_true(proof.segment_index > previous)
        previous = proof.segment_index
    ref road = map.road(RoadId(5))
    var lane = road.sections[0].lane_index(LaneId(-1))
    for index in [381, 385]:
        var segment = map.segment(index)
        assert_equal(segment[2].road_id, RoadId(5))
        assert_equal(segment[2].lane_id, LaneId(-1))
        var low = min(segment[2].s, segment[3].s)
        var high = max(segment[2].s, segment[3].s)
        assert_equal(bitcast[DType.uint64](low), UInt64(4609434218613702741) if index == 381 else UInt64(4616752568008179726))
        assert_equal(bitcast[DType.uint64](high), UInt64(4612248968380809255) if index == 381 else UInt64(4617596992938311692))
        var found_proof = _find_spiral_proof(map._spiral_proofs, index)
        assert_true(Bool(found_proof))
        var proof = found_proof.value()
        assert_equal(proof.first_count, 3 if index == 381 else 6)
        assert_equal(proof.last_count, 4 if index == 381 else 7)
        var root = _lane_jet_with_proof(road, 0, lane, low, high, low, high, proof)
        var anchor = bitcast[DType.float64](UInt64(4611686018091485842) if index == 381 else UInt64(4617315518064859697))
        _canonical_contains(road, lane, root, anchor)
        var query = Vector3(
            bitcast[DType.float32](UInt32(1073768017) if index == 381 else UInt32(1084308467)),
            bitcast[DType.float32](UInt32(3267723703) if index == 381 else UInt32(3267730170)),
            bitcast[DType.float32](UInt32(1065688760) if index == 381 else UInt32(1066192077)),
        )
        var found = map._closest_lane_certificate(query, LANE_DRIVING)
        assert_true(Bool(found))
        var waypoint = found.value()[0]
        var certificate = found.value()[1].copy()
        assert_equal(waypoint.road_id, RoadId(5))
        assert_equal(waypoint.lane_id, LaneId(-1))
        assert_true(waypoint.s >= low and waypoint.s <= high)
        _bits(waypoint.s, certificate.s)
        var terms = 0
        var canonical = _checked_center(road, 0, lane, certificate.s, terms, 2000000)
        for axis in range(3):
            # Comparison stays within this compiled scalar graph. Do not pin
            # a cross-mode witness word: allowed contraction can differ.
            _bits(canonical[axis], certificate.point[axis])
        var coordinates: Array[Float64, 3] = [Float64(query.x), Float64(query.y), Float64(query.z)]
        var score = _normalized_square[3](certificate.point, coordinates, certificate.scale)
        var tolerance = _scaled_accuracy(road, 0, lane, low, high, certificate.s, score.low, certificate.scale)
        assert_true(_certificate_within_gap(certificate.lower, certificate.scale, certificate.scale, score.high, tolerance))
        assert_true(certificate.nodes <= 16384)
        assert_true(certificate.terms <= 2000000)
        assert_true(_lane_certificate_contains(road, 0, lane, query, certificate))
    assert_equal(map._spiral_proof_units, units)
    assert_equal(len(map._spiral_proofs), len(before))
    for i in range(len(before)):
        assert_equal(map._spiral_proofs[i].segment_index, before[i].segment_index)
        assert_equal(map._spiral_proofs[i].record_at, before[i].record_at)
        assert_equal(map._spiral_proofs[i].first_count, before[i].first_count)
        assert_equal(map._spiral_proofs[i].last_count, before[i].last_count)
        _interval_bits(map._spiral_proofs[i].rounded_d, before[i].rounded_d)
        _bits(map._spiral_proofs[i].first_x_error, before[i].first_x_error)
        _bits(map._spiral_proofs[i].first_y_error, before[i].first_y_error)
        _bits(map._spiral_proofs[i].last_x_error, before[i].last_x_error)
        _bits(map._spiral_proofs[i].last_y_error, before[i].last_y_error)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
