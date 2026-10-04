# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Finite branch guards and a source-scale overflow candidate.

The extreme-rate case is a direct Road/reference candidate for native
confirmation. It is not a proven constructible full-Map regression. The test
requires actual original GL and lane jets to be finite before asserting that
reordered moment derivatives lose finiteness and must take generic fallback.
"""

from extensions.carla.curve_bounds import (
    _finite_spiral_moment_jet, _finite_spiral_moment_branch,
    _geometry_distance, _spiral_counts, _reference_work, _spiral_jet,
    _lane_jet, _lane_jet_with_proof, _union_points,
)
from extensions.carla.curve_interval import _Interval, _Jet, _next_down, _next_up
from extensions.carla.lane_refinement import _checked_center
from extensions.carla.spiral_domain_proof import (
    _spiral_proof_branch, _spiral_proof_matches,
)
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true, assert_false
from tests._spiral_domain_controls import _jet_bits, _point_bits, _interval_bits
from tests._spiral_acceptance_controls import (
    _acceptance_road, _capture_acceptance_proof, _assert_acceptance_hit, _narrow_high,
)
from tests._spiral_domain_controls import _proof


def test_finite_guard_requires_derivatives_and_complete_rounded_enclosure() raises:
    var ordinary = _Jet.constant(1.0)
    assert_true(_finite_spiral_moment_jet(ordinary))
    for field in range(5):
        var broken = ordinary
        if field == 0:
            broken.first = _Interval.whole()
        elif field == 1:
            broken.second = _Interval.whole()
        elif field == 2:
            broken.value = _Interval.whole()
        elif field == 3:
            broken.error = inf[DType.float64]()
        else:
            # Finite ideal value and finite error can still overflow the
            # rounded enclosure. This is a direct helper boundary control.
            var largest = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
            broken.value = _Interval.point(largest)
            broken.error = largest
        assert_false(_finite_spiral_moment_jet(broken))
        assert_false(_finite_spiral_moment_branch((broken, ordinary, ordinary)))
        assert_false(_finite_spiral_moment_branch((ordinary, broken, ordinary)))
        assert_false(_finite_spiral_moment_branch((ordinary, ordinary, broken)))


def test_ordinary_single_count_still_uses_the_finite_moment_branch() raises:
    var road = _acceptance_road()
    var proof = _capture_acceptance_proof(road, 0.5, _narrow_high())
    _assert_acceptance_hit(road, 0.5, _narrow_high(), proof)
    var d = _geometry_distance(road.info.geometries[0].geometry, _Jet.variable(0.5, _narrow_high()))
    var branch = _spiral_proof_branch(proof, road.info.geometries[0].geometry, d, 2)
    assert_true(_finite_spiral_moment_branch(branch))
    var actual = _lane_jet_with_proof(road, 0, 0, 0.5, _narrow_high(), 0.5, _narrow_high(), proof)
    assert_true(_finite_spiral_moment_branch(actual))
    _jet_bits(actual[0], branch[0])


def test_two_finite_count_branches_keep_the_intentional_whole_derivative_union() raises:
    var road = _acceptance_road()
    road.length = 4.0
    var proof = _proof(road, 0.99, 1.01)
    ref geometry = road.info.geometries[0].geometry
    var d = _geometry_distance(geometry, _Jet.variable(0.99, 1.01))
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], 2)
    assert_equal(counts[1], 3)
    assert_true(_spiral_proof_matches(proof, geometry, 0, 0.99, 1.01, 0.99, 1.01, d, counts))
    var first = _spiral_proof_branch(proof, geometry, d, 2)
    var last = _spiral_proof_branch(proof, geometry, d, 3)
    assert_true(_finite_spiral_moment_branch(first))
    assert_true(_finite_spiral_moment_branch(last))
    var joined = _union_points(first, last)
    assert_false(_finite_spiral_moment_branch(joined))
    var cached = _lane_jet_with_proof(road, 0, 0, 0.99, 1.01, 0.99, 1.01, proof)
    _interval_bits(cached[0].value, joined[0].value)
    assert_true(cached[0].rounded_value().is_finite())
    assert_false(cached[0].first.is_finite())
    assert_false(cached[0].second.is_finite())
    var generic = _lane_jet(road, 0, 0, 0.99, 1.01)
    assert_true(
        bitcast[DType.uint64](cached[0].value.low) != bitcast[DType.uint64](generic[0].value.low)
        or bitcast[DType.uint64](cached[0].value.high) != bitcast[DType.uint64](generic[0].value.high)
    )
    assert_equal(_reference_work(road, 0.99, 1.01), 25)


def test_nonfinite_first_or_second_rounded_branch_falls_back_before_union() raises:
    var road = _acceptance_road()
    road.length = 4.0
    road.info.geometries[0].geometry.x = 1e308
    var original = _proof(road, 0.99, 1.01)
    var generic = _lane_jet(road, 0, 0, 0.99, 1.01)
    assert_true(generic[0].rounded_value().is_finite())
    ref geometry = road.info.geometries[0].geometry
    var d = _geometry_distance(geometry, _Jet.variable(0.99, 1.01))
    var counts = _spiral_counts(geometry, d)
    for branch_index in range(2):
        var proof = original
        # Test-only conservative enlargement of one finite error allowance.
        # This does not claim these words came from a real root capture, or
        # mutate a Map pool. Finite metadata alone must not authorize an
        # infinite rounded branch or hide it in an intentional count union.
        var largest = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
        if branch_index == 0:
            proof.first_x_error = largest
        else:
            proof.last_x_error = largest
        assert_true(_spiral_proof_matches(proof, geometry, 0, 0.99, 1.01, 0.99, 1.01, d, counts))
        var first = _spiral_proof_branch(proof, geometry, d, 2)
        var last = _spiral_proof_branch(proof, geometry, d, 3)
        assert_equal(_finite_spiral_moment_branch(first), branch_index != 0)
        assert_equal(_finite_spiral_moment_branch(last), branch_index != 1)
        _point_bits(
            _lane_jet_with_proof(road, 0, 0, 0.99, 1.01, 0.99, 1.01, proof), generic,
        )
        assert_equal(_reference_work(road, 0.99, 1.01), 25)


def test_extreme_rate_reference_candidate_rejects_overflowed_moment_derivatives() raises:
    var road = _acceptance_road()
    road.info.geometries[0].geometry.length = 1.0
    road.info.geometries[0].geometry.curvature_end = 3.85e307
    var station = Float64(2.04e-154)
    var low = _next_down(station)
    var high = _next_up(station)
    # Use only a direct Road and its contained reference domain. No Map is
    # constructed, and no claim about index subdivision reachability is made.
    var proof = _proof(road, low, high)
    ref geometry = road.info.geometries[0].geometry
    var d = _geometry_distance(geometry, _Jet.variable(low, high))
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], 3)
    assert_equal(counts[1], 3)
    assert_equal(_reference_work(road, low, high), 15)
    assert_true(_spiral_proof_matches(proof, geometry, 0, low, high, low, high, d, counts))
    var original = _spiral_jet(geometry, d, 3, Vector3(0, 0, 0))
    assert_true(_finite_spiral_moment_branch(original))
    var generic = _lane_jet(road, 0, 0, low, high)
    assert_true(_finite_spiral_moment_branch(generic))
    var rate = _Jet.constant((geometry.curvature_end - geometry.curvature_start) / geometry.length)
    var u = _Jet.constant(0.5) * rate * d * d
    var z = u * u
    assert_true(u.second.is_finite())
    assert_true(z.value.is_finite())
    assert_true(z.first.is_finite())
    assert_false(z.second.is_finite())
    var reordered = _spiral_proof_branch(proof, geometry, d, 3)
    assert_true(reordered[0].rounded_value().is_finite())
    assert_true(reordered[1].rounded_value().is_finite())
    assert_false(_finite_spiral_moment_branch(reordered))
    _point_bits(_lane_jet_with_proof(road, 0, 0, low, high, low, high, proof), generic)
    var terms = 0
    # This final scalar containment is provided by the unchanged generic
    # fallback and its original captured/propagated error model.
    for sample in [low, station, high]:
        var scalar = _checked_center(road, 0, 0, sample, terms, 2000000)
        assert_true(generic[0].rounded_value().contains(scalar[0]))
        assert_true((-generic[1].rounded_value()).contains(scalar[1]))
        assert_true(generic[2].rounded_value().contains(scalar[2]))
    assert_equal(terms, 45)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
