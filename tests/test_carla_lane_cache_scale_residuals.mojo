# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""A repeated expansion station must retain its exact normalization scale."""

from extensions.carla.curve_interval import _next_down, _next_up
from extensions.carla.geometry import LINE
from extensions.carla.lane_distance import _point_gap_scale, _refinement_square
from extensions.carla.lane_refinement import (
    _ClosedInterval,
    _ClosedIntervals,
    _LaneExclusionGoal,
    _checked_center,
    _run_lane_search,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.spiral_domain_proof import _SpiralDomainProof
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._lazy_taylor_controls import _whole_certificate
from tests._spiral_acceptance_controls import (
    _acceptance_road,
    _capture_acceptance_proof,
)
from tests.test_carla_cross_candidate_certificates import _road


def _check_scale_identity(spiral: Bool) raises:
    var road = _acceptance_road()
    if not spiral:
        road.info.geometries[0].geometry.kind = LINE
    var center = Float64(0.6875)
    var step = _next_up(center) - center
    var first_root = center - 8.0 * step
    var magnitude = bitcast[DType.float64](UInt64(1127) << UInt64(52))
    # The dyadic coefficients represent K*(s-first_root)*(s-center).
    # Large cancellation makes the whole-cell interval conservative even
    # though the exact stored value at center is zero in either graph.
    road.info.elevations[0].polynomial = CubicPolynomial(
        magnitude * first_root * center,
        -magnitude * (first_root + center),
        magnitude,
        0.0,
        0.0,
    )
    var terms = 0
    var at_center = _checked_center(road, 0, 0, center, terms, 100)
    road.info.geometries[0].geometry.x -= at_center[0]
    var low = _next_down(center)
    var high = _next_up(_next_up(_next_up(center)))
    var proof: Optional[_SpiralDomainProof] = None
    if spiral:
        proof = _capture_acceptance_proof(road, low, high)
    var qx = Float64(-1.3877787807814457e-17)  # -2^-56
    var qy = Float64(7.888609052210118e-31)  # 2^-100
    var location = Vector3(Float32(qx), Float32(qy), 0)
    var query: Array[Float64, 3] = [qx, qy, 0.0]
    var external_road = _road()
    external_road.info.geometries[0].geometry.x = qx
    terms = 0
    var external = _checked_center(external_road, 0, 0, 0.0, terms, 100)
    var scale = _point_gap_scale(external, query)
    var goal = _LaneExclusionGoal(
        _refinement_square[3](external, query, scale).high, scale, False
    )
    # Four representable steps need two virtual levels. A depth budget of
    # one deliberately retains the ordinary three-witness path. The first
    # child's midpoint is the same word as its parent's expansion center.
    for seed_at_center in [False, True]:
        var seed = center if seed_at_center else low
        var certificate = _whole_certificate(road, location, low, high, seed)
        var pending: List[Tuple[Float64, Float64, Int]] = [(low, high, 0)]
        with assert_raises(contains="numerical accuracy limit"):
            _run_lane_search(
                road,
                0,
                0,
                low,
                high,
                location,
                certificate,
                pending^,
                _ClosedIntervals(),
                List[_ClosedInterval](),
                (Float64(0.0), Float64(1.0)),
                100,
                20000,
                1,
                proof,
                goal,
                external.copy(),
            )
        assert_false(certificate.exact_witness)
        assert_equal(certificate.s, center)
        assert_equal(certificate.point[0], 0.0)
        assert_equal(certificate.point[2], 0.0)
        assert_true(certificate.nodes <= 100)
        assert_true(certificate.terms <= 20000)
        assert_equal(certificate.cells[0].low, low)
        assert_equal(certificate.cells[0].high, high)


def test_translated_expansion_cache_requires_matching_scale() raises:
    _check_scale_identity(False)


def test_moment_expansion_cache_requires_matching_scale() raises:
    _check_scale_identity(True)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
