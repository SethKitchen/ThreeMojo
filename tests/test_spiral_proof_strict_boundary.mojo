# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Exact boundary and adjacent-Float32 decisions after an actual proof hit."""

from extensions.carla.lane_distance import _wide_plan_contains
from extensions.carla.lane_refinement import _lane_certificate_contains
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true, assert_false
from tests._spiral_domain_controls import _bits
from tests._spiral_acceptance_controls import (
    _acceptance_road, _narrow_high, _capture_acceptance_proof, _assert_acceptance_hit,
)
from tests.test_spiral_proof_successful_resume import _complete_resume


def _strict_case(word: UInt32, inside: Bool) raises:
    var road = _acceptance_road()
    var proof = _capture_acceptance_proof(road, 0.5, _narrow_high())
    _assert_acceptance_hit(road, 0.5, _narrow_high(), proof)
    var y = bitcast[DType.float32](word)
    var location = Vector3(0.5, y, 0.0)
    var cached = _complete_resume(road, location, proof)
    var generic = _complete_resume(road, location, None)
    assert_true(cached.exact_witness)
    _bits(cached.point[0], 0.5)
    assert_equal(cached.point[1], 0.0)
    assert_equal(cached.point[2], 0.0)
    var width = road.lane_width(0, 0, cached.s)
    _bits(width, 2.0)
    var query: Array[Float64, 3] = [0.5, Float64(y), 0.0]
    # Exact rational stored inputs: the plan distance is |y| and width/2=1.
    # This does not compare a rounded squared distance to an epsilon.
    assert_equal(Float64(y) < 1.0, inside)
    assert_equal(_wide_plan_contains(cached.point, query, width), inside)
    assert_equal(_lane_certificate_contains(road, 0, 0, location, cached), inside)
    assert_equal(_lane_certificate_contains(road, 0, 0, location, generic), inside)
    assert_equal(cached.nodes, generic.nodes)
    assert_equal(cached.terms, generic.terms)


def test_admitted_proof_exact_boundary_is_excluded() raises:
    _strict_case(UInt32(0x3F800000), False)


def test_admitted_proof_adjacent_float32_inside_is_included() raises:
    _strict_case(UInt32(0x3F7FFFFF), True)


def test_admitted_proof_adjacent_float32_outside_is_excluded() raises:
    _strict_case(UInt32(0x3F800001), False)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
