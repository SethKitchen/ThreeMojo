# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Narrow controls for the separately metered, try-only grouped lane path."""

from extensions.carla.curve_bounds import (
    _lane_jet,
    _lane_jet_model_proof,
    _lane_jet_with_proof,
    _geometry_distance,
    _spiral_counts,
    _reference_work,
    _finite_spiral_moment_branch,
)
from extensions.carla.curve_interval import _Jet, _next_down, _next_up
from extensions.carla.spiral_domain_proof import (
    _SpiralRootCapture,
    _SpiralDomainProof,
    _spiral_proof_matches,
    _spiral_proof_branch,
)
from extensions.carla.spiral_grouped_lane import _try_grouped_lane_jet
from extensions.carla.lane_refinement import _checked_center
from extensions.carla.road import Road
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from tests._spiral_domain_controls import _geometry, _road, _proof, _point_bits
from tests._spiral_acceptance_controls import _acceptance_road


def _try_only(
    road: Road,
    low: Float64,
    high: Float64,
    proof: Optional[_SpiralDomainProof],
) raises -> Tuple[_Jet, _Jet, _Jet]:
    var captured = _SpiralRootCapture()
    var point = _lane_jet_model_proof[False](
        road,
        0,
        0,
        low,
        high,
        Vector3(0, 0, 0),
        proof,
        low,
        high,
        captured,
        require_reuse=True,
    )
    assert_equal(captured.record_at, -1)
    return point


def _unknown(point: Tuple[_Jet, _Jet, _Jet]) raises:
    # Refusal is a whole rounded value, not necessarily an infinite error.
    assert_false(point[0].rounded_value().is_finite())
    assert_false(point[1].rounded_value().is_finite())
    assert_false(point[2].rounded_value().is_finite())


def test_prepaid_union_fallback_survives_exact_optional_cap_skips() raises:
    var road = _road(_geometry())
    var low = Float64(17.999999999999986)
    var high = Float64(18.249999999999986)
    var fallback = _reference_work(road, low, high)
    assert_equal(fallback, 205)
    var original = _lane_jet(road, 0, 0, low, high)
    for headroom in [0, 11, 12, 23]:
        var nodes = 7
        var terms = fallback
        assert_false(
            Bool(
                _try_grouped_lane_jet(
                    road,
                    0,
                    0,
                    low,
                    high,
                    nodes,
                    terms,
                    8,
                    fallback + headroom,
                )
            )
        )
        assert_equal(nodes, 7)
        assert_equal(terms, fallback)
        # The one prepaid ordinary producer is still available, unchanged.
        _point_bits(_lane_jet(road, 0, 0, low, high), original)
    var nodes = 8
    var terms = fallback
    assert_false(
        Bool(
            _try_grouped_lane_jet(
                road,
                0,
                0,
                low,
                high,
                nodes,
                terms,
                8,
                fallback + 24,
            )
        )
    )
    assert_equal(nodes, 8)
    assert_equal(terms, fallback)


def test_two_count_admission_debits_both_branches_atomically() raises:
    var road = _road(_geometry())
    var low = Float64(17.999999999999986)
    var high = Float64(18.249999999999986)
    var d = _geometry_distance(
        road.info.geometries[0].geometry, _Jet.variable(low, high)
    )
    var counts = _spiral_counts(road.info.geometries[0].geometry, d)
    assert_equal(counts[0], 20)
    assert_equal(counts[1], 21)
    var nodes = 7
    var terms = 205
    var result = _try_grouped_lane_jet(
        road,
        0,
        0,
        low,
        high,
        nodes,
        terms,
        8,
        229,
    )
    assert_true(Bool(result))
    assert_equal(nodes, 8)
    assert_equal(terms, 229)
    # A union remains nonsmooth even though both fixed-count proofs are valid.
    assert_false(result.value()[0].first.is_finite())
    assert_false(result.value()[0].second.is_finite())
    var scalar_terms = 0
    for station in [low, Float64(18.09471066868641), high]:
        var scalar = _checked_center(road, 0, 0, station, scalar_terms, 1000)
        assert_true(result.value()[0].rounded_value().contains(scalar[0]))
        assert_true((-result.value()[1].rounded_value()).contains(scalar[1]))
        assert_true(result.value()[2].rounded_value().contains(scalar[2]))


def test_single_count_and_zero_rate_use_actual_optional_work() raises:
    var road = _road(_geometry())
    var at = Float64(18.09471066868641)
    var fallback = _reference_work(road, at - 1e-6, at + 1e-6)
    assert_equal(fallback, 100)
    var nodes = 0
    var terms = fallback
    assert_true(
        Bool(
            _try_grouped_lane_jet(
                road,
                0,
                0,
                at - 1e-6,
                at + 1e-6,
                nodes,
                terms,
                1,
                fallback + 24,
            )
        )
    )
    assert_equal(nodes, 1)
    assert_equal(terms, fallback + 12)
    var straight_spiral = _acceptance_road()
    assert_equal(_reference_work(straight_spiral, 0.4, 0.7), 10)
    nodes = 0
    terms = 10
    assert_true(
        Bool(
            _try_grouped_lane_jet(
                straight_spiral,
                0,
                0,
                0.4,
                0.7,
                nodes,
                terms,
                1,
                34,
            )
        )
    )
    assert_equal(nodes, 1)
    assert_equal(terms, 16)


def test_admitted_phase_refusal_keeps_optional_node_and_terms() raises:
    var geometry = _geometry()
    geometry.curvature_end = 1.0
    var road = _road(geometry^)
    var low = Float64(6.0)
    var high = Float64(6.001)
    var fallback = _reference_work(road, low, high)
    assert_equal(fallback, 45)
    var original = _lane_jet(road, 0, 0, low, high)
    assert_true(original[0].rounded_value().is_finite())
    var nodes = 0
    var terms = fallback
    assert_false(
        Bool(
            _try_grouped_lane_jet(
                road,
                0,
                0,
                low,
                high,
                nodes,
                terms,
                1,
                fallback + 24,
            )
        )
    )
    assert_equal(nodes, 1)
    assert_equal(terms, fallback + 12)
    _point_bits(_lane_jet(road, 0, 0, low, high), original)


def test_invalid_counters_refuse_without_debits() raises:
    var road = _road(_geometry())
    for state in [
        (-1, 205, 8, 229),
        (7, -1, 8, 229),
        (7, 230, 8, 229),
        (8, 205, 8, 229),
        (0, 0, -1, 100),
        (0, 0, 1, -1),
    ]:
        var nodes = state[0]
        var terms = state[1]
        assert_false(
            Bool(
                _try_grouped_lane_jet(
                    road,
                    0,
                    0,
                    18.0,
                    18.25,
                    nodes,
                    terms,
                    state[2],
                    state[3],
                )
            )
        )
        assert_equal(nodes, state[0])
        assert_equal(terms, state[1])


def test_require_reuse_miss_refuses_while_default_keeps_exact_fallback() raises:
    var road = _road(_geometry())
    var low = Float64(18.09)
    var high = Float64(18.10)
    var proof = _proof(road, low, high)
    var original = _lane_jet(road, 0, 0, low, high)
    _unknown(_try_only(road, low, high, None))
    proof.record_at += 1
    _unknown(_try_only(road, low, high, proof))
    _point_bits(
        _lane_jet_with_proof(road, 0, 0, low, high, low, high, proof), original
    )


def test_nonfinite_count_branch_cannot_hide_in_union_or_trigger_gl() raises:
    var road = _acceptance_road()
    road.length = 4.0
    road.info.geometries[0].geometry.x = 1e308
    var low = Float64(0.99)
    var high = Float64(1.01)
    var original_proof = _proof(road, low, high)
    var original = _lane_jet(road, 0, 0, low, high)
    assert_true(original[0].rounded_value().is_finite())
    var d = _geometry_distance(
        road.info.geometries[0].geometry, _Jet.variable(low, high)
    )
    var counts = _spiral_counts(road.info.geometries[0].geometry, d)
    for branch in range(2):
        var proof = original_proof
        # Deliberately enlarged, conservative test-only error metadata.
        var largest = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
        if branch == 0:
            proof.first_x_error = largest
        else:
            proof.last_x_error = largest
        assert_true(
            _spiral_proof_matches(
                proof,
                road.info.geometries[0].geometry,
                0,
                low,
                high,
                low,
                high,
                d,
                counts,
            )
        )
        _unknown(_try_only(road, low, high, proof))
        _point_bits(
            _lane_jet_with_proof(road, 0, 0, low, high, low, high, proof),
            original,
        )


def test_actual_extreme_rate_refuses_nonfinite_moment_and_retains_work() raises:
    var road = _acceptance_road()
    road.info.geometries[0].geometry.length = 1.0
    road.info.geometries[0].geometry.curvature_end = 3.85e307
    var station = Float64(2.04e-154)
    var low = _next_down(station)
    var high = _next_up(station)
    var proof = _proof(road, low, high)
    var original = _lane_jet(road, 0, 0, low, high)
    assert_true(_finite_spiral_moment_branch(original))
    var d = _geometry_distance(
        road.info.geometries[0].geometry, _Jet.variable(low, high)
    )
    var branch = _spiral_proof_branch(
        proof, road.info.geometries[0].geometry, d, 3
    )
    assert_false(_finite_spiral_moment_branch(branch))
    _unknown(_try_only(road, low, high, proof))
    _point_bits(
        _lane_jet_with_proof(road, 0, 0, low, high, low, high, proof), original
    )
    assert_equal(_reference_work(road, low, high), 15)
    var nodes = 0
    var terms = 15
    assert_false(
        Bool(_try_grouped_lane_jet(road, 0, 0, low, high, nodes, terms, 1, 39))
    )
    assert_equal(nodes, 1)
    assert_equal(terms, 24)


def test_changed_grid_stations_preserve_public_pose_words() raises:
    # Same reference, elevation, width and offset graph as town road 5 lane -1
    # strictly below s=20. Superelevation does not enter this canonical API.
    # Word pairs are previous/new stations for exact grid IDs 435, 560, 643.
    var road = _road(_geometry())
    for pair in [
        (UInt64(0x4033FFFFFFFFFFD3), UInt64(0x4033FFFFFFFFFFE2)),
        (UInt64(0x4033FFFFFFFFFFCA), UInt64(0x4033FFFFFFFFFFD3)),
        (UInt64(0x4033FFFFFFFFFFDA), UInt64(0x4033FFFFFFFFFFD9)),
    ]:
        var before = road.lane_transform(0, 0, bitcast[DType.float64](pair[0]))
        var after = road.lane_transform(0, 0, bitcast[DType.float64](pair[1]))
        for component in [
            (before.location.x, after.location.x),
            (before.location.y, after.location.y),
            (before.location.z, after.location.z),
            (before.rotation.yaw, after.rotation.yaw),
            (before.rotation.pitch, after.rotation.pitch),
            (before.rotation.roll, after.rotation.roll),
        ]:
            assert_equal(
                bitcast[DType.uint32](Float32(component[0])),
                bitcast[DType.uint32](Float32(component[1])),
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
