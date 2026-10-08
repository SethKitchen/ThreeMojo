# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Actual admitted-proof Map ties, deterministic repeats, and unequal minima."""

from extensions.carla.curve_bounds import _reference_work
from extensions.carla.curve_distance import _wide_point_order
from extensions.carla.lane_distance import _normalized_square
from extensions.carla.lane_refinement import (
    _checked_center,
    _midpoint,
    _scaled_accuracy,
    _certificate_within_gap,
)
from extensions.carla.map import Map, _use_projected_spiral_seed
from extensions.carla.road_info import RoadId, LaneId, LANE_DRIVING
from extensions.carla.spiral_domain_proof import (
    _SpiralDomainProof,
    _find_spiral_proof,
)
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_true, assert_false
from tests._spiral_domain_controls import _bits
from tests._spiral_acceptance_controls import (
    _acceptance_map,
    _map_proof_segment,
    _assert_acceptance_hit,
)


def _assert_map_hit_inputs(
    map: Map, road_id: RoadId, query: Vector3
) raises -> Int:
    var index = _map_proof_segment(map, road_id)
    ref segment = map._segments[index]
    var low = min(segment.first.s, segment.second.s)
    var high = max(segment.first.s, segment.second.s)
    ref road = map.road(road_id)
    var proof = _find_spiral_proof(map._spiral_proofs, index).value()
    _assert_acceptance_hit(road, low, high, proof)
    assert_false(
        _use_projected_spiral_seed(
            road,
            0,
            0,
            low,
            high,
            segment.bounds,
            query,
        )
    )
    var coordinates: Array[Float64, 3] = [
        Float64(query.x),
        Float64(query.y),
        Float64(query.z),
    ]
    var terms = 0
    for station in [_midpoint(low, high), low, high]:
        var point = _checked_center(road, 0, 0, station, terms, 2000000)
        assert_true(_normalized_square[3](point, coordinates, 1.0).low > 0.0)
    assert_equal(terms, 30)
    assert_equal(_reference_work(road, low, high), 10)
    # Map starts from the midpoint, then samples midpoint and both edges.
    # None is coincident. The finite root encloses the known zero minimum,
    # so it cannot be strictly excluded before its charged domain evaluation.
    return index


def test_exact_duplicate_spiral_tie_keeps_segment_winner_after_proof_hits() raises:
    var map = _acceptance_map()
    var query = Vector3(0.5, 0.0, 0.0)
    var first = _assert_map_hit_inputs(map, RoadId(1), query)
    var second = _assert_map_hit_inputs(map, RoadId(2), query)
    assert_true(first < second)
    var terms = 0
    var one = _checked_center(map.road(RoadId(1)), 0, 0, 0.5, terms, 2000000)
    var two = _checked_center(map.road(RoadId(2)), 0, 0, 0.5, terms, 2000000)
    var coordinates: Array[Float64, 3] = [0.5, 0.0, 0.0]
    for axis in range(3):
        assert_equal(one[axis], coordinates[axis])
        assert_equal(two[axis], coordinates[axis])
    assert_equal(_wide_point_order(one, two, coordinates), 0)
    # Both global minima are exactly zero because these are actual stored
    # centers. This is not equality inferred from overlapping tolerances.
    var result = (
        map._closest_lane_certificate(query, LANE_DRIVING).value().copy()
    )
    assert_equal(result[0].road_id, RoadId(1))
    assert_equal(result[0].lane_id, LaneId(-1))
    assert_true(result[1].exact_witness)
    assert_true(result[1].terms >= 50)
    assert_true(result[1].nodes > 0 and result[1].nodes <= 16384)
    assert_true(result[1].terms <= 2000000)
    assert_equal(_map_proof_segment(map, result[0].road_id), first)
    for axis in range(3):
        assert_equal(result[1].point[axis], coordinates[axis])
    # Remove only optional proof availability in a separately built owner.
    # Road/index geometry is unchanged. This is a test-only generic control,
    # not a mutation/invalidation API or a proof transplanted between Maps.
    var generic = _acceptance_map()
    generic._spiral_proofs = List[_SpiralDomainProof]()
    assert_equal(len(generic._spiral_proofs), 0)
    var baseline = (
        generic._closest_lane_certificate(query, LANE_DRIVING).value().copy()
    )
    assert_equal(baseline[0].road_id, result[0].road_id)
    assert_equal(baseline[0].lane_id, result[0].lane_id)
    assert_true(baseline[1].exact_witness)
    for axis in range(3):
        _bits(baseline[1].point[axis], result[1].point[axis])
    var selected = map.segment(first)
    var low = min(selected[2].s, selected[3].s)
    var high = max(selected[2].s, selected[3].s)
    assert_true(result[0].s >= low and result[0].s <= high)
    assert_true(baseline[0].s >= low and baseline[0].s <= high)


def test_admitted_duplicate_tie_repeated_input_is_deterministic() raises:
    var map = _acceptance_map()
    var query = Vector3(0.5, 0.0, 0.0)
    _ = _assert_map_hit_inputs(map, RoadId(1), query)
    _ = _assert_map_hit_inputs(map, RoadId(2), query)
    var size = len(map._spiral_proofs)
    var units = map._spiral_proof_units
    var first = (
        map._closest_lane_certificate(query, LANE_DRIVING).value().copy()
    )
    var again = (
        map._closest_lane_certificate(query, LANE_DRIVING).value().copy()
    )
    assert_equal(first[0].road_id, RoadId(1))
    assert_equal(again[0].road_id, first[0].road_id)
    assert_equal(again[0].lane_id, first[0].lane_id)
    _bits(again[0].s, first[0].s)
    _bits(again[1].s, first[1].s)
    assert_true(first[1].terms >= 50)
    assert_equal(again[1].terms, first[1].terms)
    assert_equal(again[1].nodes, first[1].nodes)
    assert_equal(len(again[1].cells), len(first[1].cells))
    for axis in range(3):
        _bits(again[1].point[axis], first[1].point[axis])
    for i in range(len(first[1].cells)):
        _bits(again[1].cells[i].low, first[1].cells[i].low)
        _bits(again[1].cells[i].high, first[1].cells[i].high)
        assert_equal(again[1].cells[i].depth, first[1].cells[i].depth)
    assert_equal(len(map._spiral_proofs), size)
    assert_equal(map._spiral_proof_units, units)


def test_tolerance_close_unequal_minima_do_not_become_a_segment_tie() raises:
    var epsilon = Float64(0.000000059604644775390625)
    var map = _acceptance_map(epsilon)
    var query = Vector3(0.5, Float32(-epsilon), 0.0)
    var first = _assert_map_hit_inputs(map, RoadId(1), query)
    var second = _assert_map_hit_inputs(map, RoadId(2), query)
    assert_true(first < second)
    var coordinates: Array[Float64, 3] = [0.5, -epsilon, 0.0]
    var terms = 0
    var one = _checked_center(map.road(RoadId(1)), 0, 0, 0.5, terms, 2000000)
    var two = _checked_center(map.road(RoadId(2)), 0, 0, 0.5, terms, 2000000)
    _bits(one[0], 0.5)
    _bits(two[0], 0.5)
    assert_equal(one[1], 0.0)
    _bits(two[1], -epsilon)
    assert_equal(_wide_point_order(two, one, coordinates), -1)
    var one_score = _normalized_square[3](one, coordinates, 1.0)
    var exact_gap = epsilon * epsilon
    assert_true(exact_gap > 0.0)
    # The exact stored rational value need not equal either directed bound.
    assert_true(one_score.low > 0.0)
    assert_true(one_score.contains(exact_gap))
    var two_score = _normalized_square[3](two, coordinates, 1.0)
    assert_equal(two_score.low, 0.0)
    assert_equal(two_score.high, 0.0)
    var segment = map.segment(first)
    var allowance = _scaled_accuracy(
        map.road(RoadId(1)),
        0,
        0,
        min(segment[2].s, segment[3].s),
        max(segment[2].s, segment[3].s),
        0.5,
        one_score.low,
        1.0,
    )
    assert_true(one_score.high > 0.0 and one_score.high < allowance)
    # Road 2 has an exact zero minimum. Road 1's exact constant Y residual
    # is epsilon, so its squared minimum is epsilon^2, not a true tie.
    var result = (
        map._closest_lane_certificate(query, LANE_DRIVING).value().copy()
    )
    assert_equal(result[0].road_id, RoadId(2))
    assert_equal(result[0].lane_id, LaneId(-1))
    assert_true(result[1].terms >= 50)
    assert_true(result[1].terms <= 2000000)
    assert_true(result[1].nodes <= 16384)
    assert_equal(_map_proof_segment(map, result[0].road_id), second)
    var selected = map.segment(second)
    var low = min(selected[2].s, selected[3].s)
    var high = max(selected[2].s, selected[3].s)
    assert_true(result[0].s >= low and result[0].s <= high)
    _bits(result[0].s, result[1].s)
    var witness_terms = 0
    var canonical = _checked_center(
        map.road(RoadId(2)),
        0,
        0,
        result[1].s,
        witness_terms,
        2000000,
    )
    for axis in range(3):
        _bits(result[1].point[axis], canonical[axis])
    # A bounded search need not discover the known zero-distance station.
    # Its actual returned witness must still strictly beat Road 1's exact
    # minimum, with a certified original-allowance gap. This is stronger
    # than selecting by overlapping intervals or a tolerance-close tie.
    assert_true(_wide_point_order(result[1].point, one, coordinates) < 0)
    var returned = _normalized_square[3](result[1].point, coordinates, 1.0)
    assert_true(returned.high < exact_gap)
    var score = _normalized_square[3](
        result[1].point,
        coordinates,
        result[1].scale,
    )
    var permitted = _scaled_accuracy(
        map.road(RoadId(2)),
        0,
        0,
        low,
        high,
        result[1].s,
        score.low,
        result[1].scale,
    )
    assert_true(
        _certificate_within_gap(
            result[1].lower,
            result[1].scale,
            result[1].scale,
            score.high,
            permitted,
        )
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
