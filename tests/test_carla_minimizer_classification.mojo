# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Minimizing-set classification bounds preserve strictness and work limits."""

from extensions.carla.curve_bounds import _reference_work
from extensions.carla.curve_distance import _point_gap_scale
from extensions.carla.curve_interval import _Interval
from extensions.carla.geometry import SPIRAL
from extensions.carla.lane_refinement import (
    _lane_certificate_contains, _minimizer_plan_width_upper,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import RoadInfoLaneWidth
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_false, assert_raises, assert_true
from tests.test_carla_cross_candidate_certificates import _bounded, _road


def test_minimizer_plan_cap_is_scale_safe_and_strict() raises:
    var zero: Array[Float64, 3] = [0.0, 0.0, 0.0]
    for width in [Float64(1e-200), Float64(2.0), Float64(1e200)]:
        var scale = _point_gap_scale([width, 0.0, 0.0], zero)
        assert_true(_minimizer_plan_width_upper(_Interval.point(width), 0.0, scale) < 0.0)
    # Exact equality is a strict boundary, never an inside certificate.
    assert_true(_minimizer_plan_width_upper(_Interval.point(2.0), 1.0, 1.0) >= 0.0)
    assert_true(_minimizer_plan_width_upper(_Interval.point(2.0), 0.5, 1.0) < 0.0)
    # The narrowest width, not the maximum width, constrains the upper sign.
    assert_true(_minimizer_plan_width_upper(_Interval(1.0, 2.0), 1.0, 1.0) >= 3.0)


def test_minimizer_cap_bypasses_unresolved_spiral_work_without_budget_reset() raises:
    var road = _road()
    road.info.geometries[0].geometry.kind = SPIRAL
    assert_equal(_reference_work(road, 0.0, 4.0), -1)
    var certificate = _bounded(road._lane_center(0, 0, 0.5), 0.0, 0.01, low=0.0, high=4.0)
    certificate.terms = 2000000
    assert_true(_lane_certificate_contains(road, 0, 0, Vector3(0.5, 0, 0), certificate))
    assert_equal(certificate.nodes, 1)
    assert_equal(certificate.terms, 2000000)


def test_minimizer_cap_still_checks_the_returned_sample() raises:
    var road = _road()
    road.sections[0].lanes[0].info.widths[0].polynomial = CubicPolynomial(1.0, 2.0, 0.0, 0.0, 0.0)
    road.info.lane_offsets[0].polynomial = CubicPolynomial(0.5, 1.0, 0.0, 0.0, 0.0)
    # Center=(s,0,0). Returned s=0 is outside its width1; the exact
    # minimum s=1 is inside its width3. Both facts are independent of cap.
    var certificate = _bounded(road._lane_center(0, 0, 0.0), 0.0, 1.0, low=0.9, high=1.1)
    certificate.s = 0.0
    with assert_raises(contains="disagrees across possible minimizing cells"):
        _ = _lane_certificate_contains(road, 0, 0, Vector3(1, 0, 0), certificate, max_terms=0)
    assert_equal(certificate.nodes, 1)
    assert_equal(certificate.terms, 0)


def test_nonfinite_width_enclosure_cannot_use_minimizer_cap() raises:
    var road = _road()
    road.sections[0].lanes[0].info.widths.append(RoadInfoLaneWidth(2.0, CubicPolynomial.constant(4.0)))
    var certificate = _bounded([0.5, 0.0, 0.0], 0.0, 0.01, low=0.0, high=4.0)
    with assert_raises(contains="finite width enclosure"):
        _ = _lane_certificate_contains(road, 0, 0, Vector3(0.5, 0, 0), certificate, max_terms=0)
    assert_equal(certificate.nodes, 1)
    assert_equal(certificate.terms, 0)


def test_nonpositive_width_needs_no_curve_terms_but_still_charges_a_node() raises:
    var road = _road(width=0.0)
    var certificate = _bounded([0.5, 0.0, 0.0], 0.0, 0.01, low=0.0, high=4.0)
    assert_false(_lane_certificate_contains(road, 0, 0, Vector3(0.5, 0, 0), certificate, max_terms=0))
    assert_equal(certificate.nodes, 1)
    assert_equal(certificate.terms, 0)


def test_minimizer_cap_cannot_bypass_the_node_limit() raises:
    var road = _road()
    var certificate = _bounded([0.5, 0.0, 0.0], 0.0, 0.01, low=0.0, high=4.0)
    certificate.nodes = 16384
    with assert_raises(contains="interval work limit"):
        _ = _lane_certificate_contains(road, 0, 0, Vector3(0.5, 0, 0), certificate)
    assert_equal(certificate.nodes, 16384)
    assert_equal(certificate.terms, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
