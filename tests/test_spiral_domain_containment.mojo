# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Canonical scalar and pre-union controls for immutable SPIRAL proofs.

Source-only controls. Keep TestSuite's unchanged five-second per-test gate.
The hot root and witness words are frozen from town segments 381 and 385.
"""

from extensions.carla.curve_bounds import (
    _geometry_distance,
    _lane_jet,
    _lane_jet_capture,
    _lane_jet_with_proof,
    _reference_jet,
    _spiral_counts,
    _spiral_jet,
    _union_points,
)
from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _next_down,
    _next_up,
)
from extensions.carla.geometry import RoadGeometry, SPIRAL
from extensions.carla.lane_geometry import _lane_geometry_pos_at
from extensions.carla.lane_refinement import (
    _chord_certificate,
    _chord_certificate_capture,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    LaneId,
    RoadInfoElevation,
    RoadInfoGeometry,
    RoadInfoLaneOffset,
    RoadInfoLaneWidth,
)
from extensions.carla.spiral_domain_proof import (
    _SpiralRootCapture,
    _spiral_proof_branch,
    _spiral_proof_matches,
    _try_pack_spiral_proof,
)
from math.vector3 import Vector3
from std.math import isfinite
from std.testing import TestSuite, assert_equal, assert_true, assert_false
from tests._spiral_domain_controls import (
    _bits,
    _interval_bits,
    _jet_bits,
    _point_bits,
    _f64,
    _geometry,
    _road,
    _capture,
    _proof,
    _canonical_contains,
)


def _capture_errors_match_original(
    road: Road, captured: _SpiralRootCapture
) raises:
    ref geometry = road.info.geometries[captured.record_at].geometry
    var first = _spiral_jet(
        geometry, captured.d, captured.first_count, Vector3(0, 0, 0)
    )
    var last = _spiral_jet(
        geometry, captured.d, captured.last_count, Vector3(0, 0, 0)
    )
    _bits(captured.first_x_error, first[0].error)
    _bits(captured.first_y_error, first[1].error)
    _bits(captured.last_x_error, last[0].error)
    _bits(captured.last_y_error, last[1].error)
    assert_true(isfinite(first[0].error) and first[0].error > 0.0)
    assert_true(isfinite(last[1].error) and last[1].error > 0.0)


def test_authorized_chord_root_capture_preserves_original_result_and_work() raises:
    var road = _road(_geometry())
    for interval in [_Interval(2.125, 2.25), _Interval(1.5, 2.25)]:
        var low = interval.low
        var high = interval.high
        var first = road._lane_center(0, 0, low)
        var last = road._lane_center(0, 0, high)
        var start = Vector3(
            Float32(first[0]), Float32(first[1]), Float32(first[2])
        )
        var end = Vector3(Float32(last[0]), Float32(last[1]), Float32(last[2]))
        var captured = _SpiralRootCapture()
        var actual = _chord_certificate_capture(
            road, 0, 0, low, high, start, end, captured
        )
        var original = _chord_certificate(road, 0, 0, low, high, start, end)
        _bits(actual[0], original[0])
        _interval_bits(actual[1][0], original[1][0])
        _interval_bits(actual[1][1], original[1][1])
        _interval_bits(actual[1][2], original[1][2])
        assert_equal(actual[2], original[2])
        _bits(captured.low, low)
        _bits(captured.high, high)
        assert_equal(captured.record_at, 0)
        _capture_errors_match_original(road, captured)
        var construction_terms = actual[2]
        var proof_units = 0
        var proof = _try_pack_spiral_proof(
            road,
            low,
            high,
            0,
            captured,
            0,
            construction_terms,
            proof_units,
        )
        assert_true(Bool(proof))
        assert_equal(construction_terms, actual[2] + proof_units)


def test_unbudgeted_chord_root_does_not_create_a_capture() raises:
    var road = _road(_geometry())
    var captured = _SpiralRootCapture()
    var result = _chord_certificate_capture(
        road,
        0,
        0,
        2.125,
        2.25,
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        captured,
        max_terms=0,
    )
    assert_equal(result[2], 0)
    assert_equal(captured.first_count, 0)
    var terms = 0
    var units = 0
    assert_false(
        Bool(
            _try_pack_spiral_proof(
                road,
                2.125,
                2.25,
                0,
                captured,
                0,
                terms,
                units,
            )
        )
    )
    assert_equal(terms, 0)
    assert_equal(units, 0)


def _hot(
    root_low: UInt64, root_high: UInt64, anchor: UInt64, first_count: Int
) raises:
    var road = _road(_geometry())
    var low = _f64(root_low)
    var high = _f64(root_high)
    var station = _f64(anchor)
    var proof = _proof(road, low, high)
    assert_equal(proof.first_count, first_count)
    assert_equal(proof.last_count, first_count + 1)
    var captured = _capture(road, low, high)
    _capture_errors_match_original(road, captured)
    ref geometry = road.info.geometries[0].geometry
    var cell_low = low
    var cell_high = high
    for _ in range(11):
        var d = _geometry_distance(geometry, _Jet.variable(cell_low, cell_high))
        var counts = _spiral_counts(geometry, d)
        assert_true(
            _spiral_proof_matches(
                proof, geometry, 0, cell_low, cell_high, low, high, d, counts
            )
        )
        var point = _lane_jet_with_proof(
            road, 0, 0, cell_low, cell_high, low, high, proof
        )
        var middle = cell_low + (cell_high - cell_low) * 0.5
        for sample in [cell_low, middle, cell_high, station]:
            _canonical_contains(road, 0, point, sample)
        var first = _spiral_proof_branch(proof, geometry, d, counts[0])
        var fresh = _spiral_jet(geometry, d, counts[0], Vector3(0, 0, 0))
        _jet_bits(first[2], fresh[2])
        _bits(
            first[0].error,
            proof.last_x_error if counts[0]
            == proof.last_count else proof.first_x_error,
        )
        _bits(
            first[1].error,
            proof.last_y_error if counts[0]
            == proof.last_count else proof.first_y_error,
        )
        if station <= middle:
            cell_high = middle
        else:
            cell_low = middle
    for sample in [_next_down(station), station, _next_up(station)]:
        var point = _lane_jet_with_proof(
            road, 0, 0, sample, sample, low, high, proof
        )
        _canonical_contains(road, 0, point, sample)


def test_hot_segment381_root_children_and_scalar_witness_neighbors() raises:
    _hot(
        UInt64(4609434218613702741),
        UInt64(4612248968380809255),
        UInt64(4611686018091485842),
        3,
    )


def test_hot_segment385_root_children_and_scalar_witness_neighbors() raises:
    _hot(
        UInt64(4616752568008179726),
        UInt64(4617596992938311692),
        UInt64(4617315518064859697),
        6,
    )


def test_count_join_keeps_both_errors_then_discards_union_derivatives() raises:
    var geometry = _geometry()
    geometry.curvature_end = 0.0
    var road = _road(geometry^)
    var proof = _proof(road, 0.99, 1.01)
    assert_equal(proof.first_count, 2)
    assert_equal(proof.last_count, 3)
    ref selected = road.info.geometries[0].geometry
    var d = _geometry_distance(selected, _Jet.variable(0.99, 1.01))
    var counts = _spiral_counts(selected, d)
    assert_equal(counts[0], 2)
    assert_equal(counts[1], 3)
    assert_true(
        _spiral_proof_matches(
            proof, selected, 0, 0.99, 1.01, 0.99, 1.01, d, counts
        )
    )
    var first = _spiral_proof_branch(proof, selected, d, counts[0])
    var last = _spiral_proof_branch(proof, selected, d, counts[1])
    _bits(first[0].error, proof.first_x_error)
    _bits(last[0].error, proof.last_x_error)
    assert_true(first[0].error > 0.0 and last[0].error > 0.0)
    var joined = _union_points(first, last)
    _bits(joined[0].error, 0.0)
    _bits(joined[1].error, 0.0)
    assert_false(joined[0].first.is_finite())
    assert_false(joined[0].second.is_finite())
    assert_false(joined[1].first.is_finite())
    var point = _lane_jet_with_proof(road, 0, 0, 0.99, 1.01, 0.99, 1.01, proof)
    for station in [0.99, _next_down(1.0), 1.0, _next_up(1.0), 1.01]:
        _canonical_contains(road, 0, point, station)
        var scalar = _lane_geometry_pos_at(selected, station)
        assert_true(joined[0].rounded_value().contains(scalar.x))
        assert_true(joined[1].rounded_value().contains(scalar.y))


def test_nonzero_record_station_keeps_original_subtraction_provenance() raises:
    var road = _road(_geometry(), 128.0)
    var proof = _proof(road, 129.0, 129.25)
    for station in [129.0, 129.125, 129.25]:
        var point = _lane_jet_with_proof(
            road, 0, 0, station, station, 129.0, 129.25, proof
        )
        _canonical_contains(road, 0, point, station)
    var entire = _lane_jet_with_proof(
        road, 0, 0, 129.0, 129.25, 129.0, 129.25, proof
    )
    _canonical_contains(road, 0, entire, 129.125)


def test_signed_zero_heading_and_start_curvature_are_supported() raises:
    for heading in [-0.0, 0.0]:
        for start in [-0.0, 0.0]:
            var geometry = _geometry()
            geometry.heading = heading
            geometry.curvature_start = start
            var road = _road(geometry^)
            var proof = _proof(road, 2.125, 2.25)
            var d = _Jet.variable(2.1875, 2.1875)
            ref selected = road.info.geometries[0].geometry
            var counts = _spiral_counts(selected, d)
            assert_true(
                _spiral_proof_matches(
                    proof, selected, 0, 2.1875, 2.1875, 2.125, 2.25, d, counts
                )
            )
            var branch = _spiral_proof_branch(proof, selected, d, counts[0])
            var original = _reference_jet(selected, d, Vector3(0, 0, 0))
            _jet_bits(branch[2], original[2])
            var point = _lane_jet_with_proof(
                road, 0, 0, 2.1875, 2.1875, 2.125, 2.25, proof
            )
            _canonical_contains(road, 0, point, 2.1875)


def test_large_origins_capture_world_addition_error_before_reuse() raises:
    for origin in [281474976710656.25, 1e30, 1e200, 1e308]:
        var geometry = _geometry()
        geometry.x = origin
        geometry.y = -origin
        var road = _road(geometry^)
        var captured = _capture(road, 2.125, 2.25)
        _capture_errors_match_original(road, captured)
        var proof = _proof(road, 2.125, 2.25)
        assert_true(proof.first_x_error > 0.0)
        for station in [2.125, 2.1875, 2.25]:
            var point = _lane_jet_with_proof(
                road, 0, 0, station, station, 2.125, 2.25, proof
            )
            _canonical_contains(road, 0, point, station)


def test_selected_and_inner_width_expressions_remain_fresh() raises:
    var road = _road(_geometry())
    _ = road.sections[0].add_lane(LaneId(-2))
    var inner = road.sections[0].lane_index(LaneId(-1))
    var outer = road.sections[0].lane_index(LaneId(-2))
    road.sections[0].lanes[inner].info.widths[0].polynomial = CubicPolynomial(
        3.0, 0.125, 0.002, 0.0, 0.0
    )
    road.sections[0].lanes[outer].info.widths.append(
        RoadInfoLaneWidth(0.0, CubicPolynomial(2.0, 0.05, 0.001, 0.0, 0.0))
    )
    road.info.lane_offsets[0].polynomial = CubicPolynomial(
        0.5, 0.01, -0.002, 0.0, 0.0
    )
    road.info.elevations[0].polynomial = CubicPolynomial(
        1.0, 0.02, 0.005, 0.001, 0.0
    )
    var proof = _proof(road, 2.125, 2.25, lane=outer)
    for station in [2.125, 2.1875, 2.25]:
        var point = _lane_jet_with_proof(
            road, 0, outer, station, station, 2.125, 2.25, proof
        )
        _canonical_contains(road, outer, point, station)
        _jet_bits(point[2], _lane_jet(road, 0, outer, station, station)[2])


def test_record_crossings_do_not_create_a_partial_root_capture() raises:
    for kind in range(4):
        var road = _road(_geometry())
        if kind == 0:
            road.info.geometries.append(RoadInfoGeometry(2.1875, _geometry()))
        elif kind == 1:
            road.info.elevations.append(
                RoadInfoElevation(2.1875, CubicPolynomial.constant(2.0))
            )
        elif kind == 2:
            road.info.lane_offsets.append(
                RoadInfoLaneOffset(2.1875, CubicPolynomial.constant(0.75))
            )
        else:
            road.sections[0].lanes[0].info.widths.append(
                RoadInfoLaneWidth(2.1875, CubicPolynomial.constant(4.0))
            )
        var captured = _SpiralRootCapture()
        var point = _lane_jet_capture(road, 0, 0, 2.125, 2.25, captured)
        _point_bits(point, _lane_jet(road, 0, 0, 2.125, 2.25))
        assert_false(point[0].value.is_finite())
        assert_equal(captured.first_count, 0)
        var terms = 0
        var units = 0
        assert_false(
            Bool(
                _try_pack_spiral_proof(
                    road, 2.125, 2.25, 0, captured, 0, terms, units
                )
            )
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
