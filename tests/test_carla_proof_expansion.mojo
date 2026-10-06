# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Fresh controls for the same ideal expression and stored distance bounds."""

from extensions.carla.curve_bounds import (
    _expansion_distance_jet,
    _lane_jet_with_proof,
    _scaled_point_distance_jet,
    _try_proof_expansion_jet,
)
from extensions.carla.curve_interval import _Interval
from extensions.carla.curve_distance import _WORDS, _signed_product, _exact_sign
from extensions.carla.spiral_domain_proof import (
    _SpiralRootCapture,
    _try_pack_spiral_proof,
)
from extensions.carla.lane_refinement import (
    _global_lower,
    _chord_certificate_capture,
)
from extensions.carla.map import Map
from extensions.carla.opendrive import load_opendrive_file
from math.vector3 import Vector3
from std.math import isfinite
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def _assert_exact_lower(
    lower: Float64, point: Array[Float64, 3], query: Array[Float64, 3]
) raises:
    # Independent exact products of the original stored binary operands.
    assert_true(isfinite(lower))
    var positive = Array[UInt64, _WORDS](fill=0)
    var negative = Array[UInt64, _WORDS](fill=0)
    for axis in range(3):
        _signed_product(positive, negative, point[axis], point[axis], 0, False)
        _signed_product(positive, negative, point[axis], query[axis], 1, True)
        _signed_product(positive, negative, query[axis], query[axis], 0, False)
    _signed_product(positive, negative, lower, 1.0, 0, True)
    assert_true(_exact_sign(positive, negative) >= 0)


def _proof_index(map: Map) raises -> Int:
    for i in range(len(map._spiral_proofs)):
        if (
            map._spiral_proofs[i].first_count
            == map._spiral_proofs[i].last_count
        ):
            return i
    raise Error("The control requires an admitted single-count proof")


def test_proof_expansion_encloses_the_original_ideal_expression() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    var proof = map._spiral_proofs[_proof_index(map)]
    var segment = map._segments[proof.segment_index]
    var at = map._locate(segment.first)
    var low = min(segment.first.s, segment.second.s)
    var high = max(segment.first.s, segment.second.s)
    var s = low + (high - low) * 0.5
    var waypoint = segment.first
    waypoint.s = s
    var query = map.compute_transform(waypoint).location + Vector3(
        0.125, 0.25, -0.5
    )
    var fast = _try_proof_expansion_jet(
        map.roads[at[0]], at[1], at[2], s, query, 1, low, high, proof
    ).value()
    var original = _expansion_distance_jet(
        map.roads[at[0]], at[1], at[2], s, query, 1
    )
    assert_true(fast.value.low <= original.value.high)
    assert_true(original.value.low <= fast.value.high)
    assert_true(fast.first.low <= original.first.high)
    assert_true(original.first.low <= fast.first.high)
    assert_false(isfinite(fast.error))
    var domain = _scaled_point_distance_jet(
        _lane_jet_with_proof(
            map.roads[at[0]], at[1], at[2], low, high, low, high, proof
        ),
        query,
        1,
    )
    var lower = _global_lower(
        domain, fast, _Interval(low, high) - _Interval.point(s)
    )
    var query_words: Array[Float64, 3] = [
        Float64(query.x),
        Float64(query.y),
        Float64(query.z),
    ]
    for i in range(33):
        var sample = low + (high - low) * Float64(i) / 32.0
        var point = map.roads[at[0]]._lane_center(at[1], at[2], sample)
        _assert_exact_lower(lower, point, query_words)


def test_proof_expansion_retains_station_geometry_and_missing_proof_guards() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    var proof = map._spiral_proofs[_proof_index(map)]
    var segment = map._segments[proof.segment_index]
    var at = map._locate(segment.first)
    var low = min(segment.first.s, segment.second.s)
    var high = max(segment.first.s, segment.second.s)
    var s = low + (high - low) * 0.5
    assert_false(
        Bool(
            _try_proof_expansion_jet(
                map.roads[at[0]],
                at[1],
                at[2],
                s,
                Vector3(0, 0, 0),
                1,
                low,
                high,
                None,
            )
        )
    )
    assert_false(
        Bool(
            _try_proof_expansion_jet(
                map.roads[at[0]],
                at[1],
                at[2],
                s,
                Vector3(0, 0, 0),
                1,
                s + 0.001,
                high,
                proof,
            )
        )
    )
    map.roads[at[0]].info.geometries[proof.record_at].geometry.heading = 0.5
    assert_false(
        Bool(
            _try_proof_expansion_jet(
                map.roads[at[0]],
                at[1],
                at[2],
                s,
                Vector3(0, 0, 0),
                1,
                low,
                high,
                proof,
            )
        )
    )


def test_translated_origins_use_fresh_proofs_and_exact_distance_lower_controls() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    var source_proof = map._spiral_proofs[_proof_index(map)]
    var segment = map._segments[source_proof.segment_index]
    var at = map._locate(segment.first)
    var low = min(segment.first.s, segment.second.s)
    var high = max(segment.first.s, segment.second.s)
    var s = low + (high - low) * 0.5
    for origin in [1000000.0, -1000000.0, 1e20, -1e20]:
        var road = map.roads[at[0]].copy()
        road.info.geometries[source_proof.record_at].geometry.x = origin
        road.info.geometries[source_proof.record_at].geometry.y = -origin
        var first = road.lane_transform(at[1], at[2], low).location
        var last = road.lane_transform(at[1], at[2], high).location
        var captured = _SpiralRootCapture()
        var chord = _chord_certificate_capture(
            road, at[1], at[2], low, high, first, last, captured
        )
        var terms = chord[2]
        var units = 0
        var fresh = _try_pack_spiral_proof(
            road, low, high, 0, captured, 0, terms, units
        ).value()
        var query = road.lane_transform(at[1], at[2], s).location + Vector3(
            0.125, 0.25, -0.5
        )
        var fast = _try_proof_expansion_jet(
            road, at[1], at[2], s, query, 1, low, high, fresh
        ).value()
        var original = _expansion_distance_jet(road, at[1], at[2], s, query, 1)
        assert_true(fast.value.low <= original.value.high)
        assert_true(original.value.low <= fast.value.high)
        assert_true(fast.first.low <= original.first.high)
        assert_true(original.first.low <= fast.first.high)
        var domain = _scaled_point_distance_jet(
            _lane_jet_with_proof(
                road, at[1], at[2], low, high, low, high, fresh
            ),
            query,
            1,
        )
        var lower = _global_lower(
            domain, fast, _Interval(low, high) - _Interval.point(s)
        )
        var query_words: Array[Float64, 3] = [
            Float64(query.x),
            Float64(query.y),
            Float64(query.z),
        ]
        for i in range(33):
            var sample = low + (high - low) * Float64(i) / 32.0
            var point = road._lane_center(at[1], at[2], sample)
            _assert_exact_lower(lower, point, query_words)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
