# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""A local witness can restore an external-goal bound lost to underflow."""

from extensions.carla.lane_distance import _point_gap_scale, _refinement_square
from extensions.carla.lane_refinement import (
    _ClosedInterval,
    _ClosedIntervals,
    _LaneExclusionGoal,
    _checked_center,
    _goal_excludes,
    _run_lane_search,
)
from extensions.carla.polynomial import CubicPolynomial
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from tests._lazy_taylor_controls import _whole_certificate
from tests.test_carla_cross_candidate_certificates import _road


def test_local_scale_recovers_a_strict_external_goal() raises:
    var road = _road()
    # This exact dyadic station is retained by the bounded golden-section
    # search on [0.1, 0.9]. A power-of-two slope keeps its stored zero exact.
    var root = bitcast[DType.float64](UInt64(0x3FD7AE147A450500))
    var slope = bitcast[DType.float64](UInt64(1623) << UInt64(52))
    road.info.elevations[0].polynomial = CubicPolynomial(
        -slope * root, slope, 0.0, 0.0, 0.0
    )
    var location = Vector3(0, 1, 0)
    var query: Array[Float64, 3] = [0.0, 1.0, 0.0]
    var external_road = _road()
    var terms = 0
    var external = _checked_center(external_road, 0, 0, 0.0, terms, 100)
    var goal_scale = _point_gap_scale(external, query)
    var goal = _LaneExclusionGoal(
        _refinement_square[3](external, query, goal_scale).high,
        goal_scale,
        False,
    )
    var certificate = _whole_certificate(road, location, 0.1, 0.9, 0.5)
    var original_scale = certificate.scale
    var pending: List[Tuple[Float64, Float64, Int]] = [(0.1, 0.9, 0)]
    _run_lane_search(
        road,
        0,
        0,
        0.1,
        0.9,
        location,
        certificate,
        pending^,
        _ClosedIntervals(),
        List[_ClosedInterval](),
        (Float64(0.0), Float64(1.0)),
        20,
        1000,
        0,
        None,
        goal,
        external.copy(),
    )
    assert_false(certificate.exact_witness)
    assert_equal(certificate.s, root)
    assert_equal(certificate.point[2], 0.0)
    assert_true(certificate.scale < original_scale)
    assert_true(_goal_excludes(certificate.lower, certificate.scale, goal))
    assert_equal(certificate.nodes, 2)
    assert_true(certificate.terms <= 1000)
    assert_equal(len(certificate.cells), 1)
    assert_equal(certificate.cells[0].low, 0.1)
    assert_equal(certificate.cells[0].high, 0.9)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
