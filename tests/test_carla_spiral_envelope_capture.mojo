# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Explicit fast-capture budgets, generic fallback and fresh stored distances."""

from extensions.carla.curve_bounds import (
    _try_lane_envelope_capture,
    _lane_jet_with_proof,
    _scaled_point_distance_jet,
    _try_proof_expansion_jet,
)
from extensions.carla.curve_interval import _Interval
from extensions.carla.geometry import SPIRAL
from extensions.carla.lane_refinement import (
    _chord_certificate_capture,
    _chord_certificate_capture_fast,
    _global_lower,
)
from extensions.carla.road import Road
from extensions.carla.spiral_domain_proof import (
    _SpiralRootCapture,
    _try_pack_spiral_proof,
)
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from tests.test_carla_lane_orientation import _road
from tests.test_carla_proof_expansion import _assert_exact_lower


def _eligible_road() raises -> Road:
    var road = _road(SPIRAL)
    road.info.geometries[0].geometry.heading = 0.0
    road.info.geometries[0].geometry.curvature_start = 0.0
    road.info.geometries[0].geometry.curvature_end = 0.05
    return road^


def test_unavailable_optional_allowance_does_not_attempt_or_spend() raises:
    var road = _eligible_road()
    var capture = _SpiralRootCapture()
    for available in [0, 1023]:
        var spent = 20
        assert_false(
            Bool(
                _try_lane_envelope_capture(
                    road, 0, 0, 0.1, 0.2, capture, spent, 20 + available
                )
            )
        )
        assert_equal(spent, 20)
        assert_equal(capture.record_at, -1)
    var spent = 20
    assert_true(
        Bool(
            _try_lane_envelope_capture(
                road, 0, 0, 0.1, 0.2, capture, spent, 1044
            )
        )
    )
    assert_equal(spent, 1044)


def test_failed_quadrant_attempt_is_charged_and_original_fallback_is_exact() raises:
    var road = _eligible_road()
    road.info.geometries[0].geometry.curvature_end = 1.0
    var low = 6.0
    var high = 6.001
    var one = _SpiralRootCapture()
    var two = _SpiralRootCapture()
    var spent = 0
    assert_false(
        Bool(
            _try_lane_envelope_capture(
                road, 0, 0, low, high, one, spent, 2000000
            )
        )
    )
    assert_equal(spent, 1024)
    var first = road.lane_transform(0, 0, low).location
    var last = road.lane_transform(0, 0, high).location
    var original = _chord_certificate_capture(
        road, 0, 0, low, high, first, last, one
    )
    var fast = _chord_certificate_capture_fast(
        road, 0, 0, low, high, first, last, two
    )
    assert_equal(fast[2], original[2] + 1024)
    assert_equal(
        bitcast[DType.uint64](fast[0]), bitcast[DType.uint64](original[0])
    )
    assert_equal(
        bitcast[DType.uint64](two.first_x_error),
        bitcast[DType.uint64](one.first_x_error),
    )
    assert_equal(
        bitcast[DType.uint64](two.first_y_error),
        bitcast[DType.uint64](one.first_y_error),
    )


def test_two_count_branches_reserve_both_envelopes_and_cover_stored_values() raises:
    var road = _eligible_road()
    road.info.geometries[0].geometry.curvature_end = 0.0
    var capture = _SpiralRootCapture()
    var spent = 0
    assert_false(
        Bool(
            _try_lane_envelope_capture(
                road, 0, 0, 0.99, 1.01, capture, spent, 2047
            )
        )
    )
    assert_equal(spent, 0)
    var point = _try_lane_envelope_capture(
        road, 0, 0, 0.99, 1.01, capture, spent, 2048
    ).value()
    assert_equal(spent, 2048)
    assert_equal(capture.first_count, 2)
    assert_equal(capture.last_count, 3)
    for i in range(17):
        var station = 0.99 + 0.02 * Float64(i) / 16.0
        var actual = road._lane_center(0, 0, station)
        assert_true(point[0].rounded_value().contains(actual[0]))
        assert_true((-point[1].rounded_value()).contains(actual[1]))
        assert_true(point[2].rounded_value().contains(actual[2]))


def test_fast_capture_translated_origins_keep_exact_stored_distance_lower_bounds() raises:
    var low = 0.1
    var high = 0.2
    var center = 0.15
    for origin in [0.0, 1000000.0, -1000000.0, 1e20, -1e20]:
        var road = _eligible_road()
        road.info.geometries[0].geometry.x = origin
        road.info.geometries[0].geometry.y = -origin
        var first = road.lane_transform(0, 0, low).location
        var last = road.lane_transform(0, 0, high).location
        var capture = _SpiralRootCapture()
        var chord = _chord_certificate_capture_fast(
            road, 0, 0, low, high, first, last, capture
        )
        var terms = chord[2]
        var units = 0
        var proof = _try_pack_spiral_proof(
            road, low, high, 0, capture, 0, terms, units
        ).value()
        var query = road.lane_transform(0, 0, center).location + Vector3(
            0.125, 0.25, -0.5
        )
        var domain = _scaled_point_distance_jet(
            _lane_jet_with_proof(road, 0, 0, low, high, low, high, proof),
            query,
            1,
        )
        var expansion = _try_proof_expansion_jet(
            road, 0, 0, center, query, 1, low, high, proof
        ).value()
        var lower = _global_lower(
            domain, expansion, _Interval(low, high) - _Interval.point(center)
        )
        var query_words: Array[Float64, 3] = [
            Float64(query.x),
            Float64(query.y),
            Float64(query.z),
        ]
        for i in range(33):
            var station = low + (high - low) * Float64(i) / 32.0
            _assert_exact_lower(
                lower, road._lane_center(0, 0, station), query_words
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
