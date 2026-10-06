# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""An existing natural bound closes only under the original final-gap rule."""

from extensions.carla.curve_distance import _normalized_square
from extensions.carla.geometry import LINE, RoadGeometry
from extensions.carla.lane_refinement import (
    _refine_lane_certificate,
    _resume_lane_certificate,
    _search_accuracy,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_carla_lane_certificates import _road


def test_natural_gap_closes_without_optional_golden_seed() raises:
    var road = _road(RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.3, 1.0))
    var query = Vector3(0.25, 0, 100000000)
    var result = _refine_lane_certificate(
        road, 0, 0, 0.0, 1.0, query, 0.25, 0.0, max_nodes=2, max_terms=5
    )
    assert_equal(result.nodes, 2)
    assert_equal(result.terms, 5)
    assert_false(result.exact_witness)
    assert_equal(len(result.cells), 1)
    assert_equal(result.cells[0].low, 0.0)
    assert_equal(result.cells[0].high, 1.0)
    var target: Array[Float64, 3] = [0.25, 0.0, 100000000.0]
    var score = _normalized_square[3](result.point, target, result.scale)
    var tolerance = _search_accuracy(
        road, 0, 0, 0.0, 1.0, result.s, score.low, result.scale, None
    )
    assert_true(result.upper - result.lower <= tolerance)
    for i in range(1001):
        var point = road._lane_center(0, 0, Float64(i) / 1000.0)
        var bound = _normalized_square[3](point, target, result.scale)
        assert_true(result.lower <= bound.high)


def test_natural_gap_charges_domain_before_admission() raises:
    var road = _road(RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.3, 1.0))
    with assert_raises(contains="quadrature work limit"):
        _ = _refine_lane_certificate(
            road,
            0,
            0,
            0.0,
            1.0,
            Vector3(0.25, 0, 100000000),
            0.25,
            0.0,
            max_nodes=2,
            max_terms=4,
        )
    with assert_raises(contains="interval work limit"):
        _ = _refine_lane_certificate(
            road,
            0,
            0,
            0.0,
            1.0,
            Vector3(0.25, 0, 100000000),
            0.25,
            0.0,
            max_nodes=1,
            max_terms=5,
        )


def test_natural_gap_cover_reopens_for_tighter_resume() raises:
    var road = _road(RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.3, 1.0))
    var query = Vector3(0.25, 0, 100000000)
    var result = _refine_lane_certificate(
        road, 0, 0, 0.0, 1.0, query, 0.25, 0.0, max_nodes=2, max_terms=5
    )
    var nodes = result.nodes
    with assert_raises(contains="quadrature work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            0.0,
            1.0,
            query,
            result,
            0.0,
            result.scale,
            max_nodes=16,
            max_terms=5,
        )
    assert_true(result.nodes > nodes)
    assert_equal(result.terms, 5)
    assert_false(result.exact_witness)
    assert_equal(len(result.cells), 1)
    assert_equal(result.cells[0].low, 0.0)
    assert_equal(result.cells[0].high, 1.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
