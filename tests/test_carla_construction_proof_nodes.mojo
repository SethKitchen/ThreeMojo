# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Global construction steps include cells with unresolved quadrature counts."""

from extensions.carla.geometry import SPIRAL
from extensions.carla.lane_refinement import (
    _ProofNodeWork,
    _subdivided_lane_box,
    _subdivided_lane_box_with_nodes,
    _chord_certificate_capture,
    _chord_certificate_capture_with_nodes,
)
from extensions.carla.spiral_domain_proof import _SpiralRootCapture
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_raises
from tests.test_carla_lane_orientation import _road


def test_global_node_limit_raises_before_pop_but_legacy_local_limit_keeps_unknown() raises:
    var road = _road(SPIRAL)
    var local = _subdivided_lane_box(road, 0, 0, 0, 20, 2000000, max_nodes=0)
    assert_equal(local[1], 0)
    assert_false(local[0][0].is_finite())
    var global_nodes = _ProofNodeWork(0)
    with assert_raises(contains="global proof node budget"):
        _ = _subdivided_lane_box_with_nodes(
            road, 0, 0, 0, 20, 2000000, global_nodes
        )
    assert_equal(global_nodes.used, 0)


def test_unresolved_quadrature_cells_spend_global_steps() raises:
    var road = _road(SPIRAL)
    var global_nodes = _ProofNodeWork(1)
    var captured = _SpiralRootCapture()
    with assert_raises(contains="global proof node budget"):
        _ = _chord_certificate_capture_with_nodes(
            road,
            0,
            0,
            0,
            20,
            Vector3(0, 0, 0),
            Vector3(20, 0, 0),
            captured,
            global_nodes,
        )
    assert_equal(global_nodes.used, 1)


def test_sufficient_counted_proof_retains_original_bounds_and_terms() raises:
    var road = _road(SPIRAL)
    var first = road.lane_transform(0, 0, 0.1).location
    var last = road.lane_transform(0, 0, 2.1).location
    var original_capture = _SpiralRootCapture()
    var counted_capture = _SpiralRootCapture()
    var original = _chord_certificate_capture(
        road, 0, 0, 0.1, 2.1, first, last, original_capture
    )
    var nodes = _ProofNodeWork(16384)
    var counted = _chord_certificate_capture_with_nodes(
        road, 0, 0, 0.1, 2.1, first, last, counted_capture, nodes
    )
    assert_equal(
        bitcast[DType.uint64](original[0]), bitcast[DType.uint64](counted[0])
    )
    assert_equal(original[2], counted[2])
    assert_equal(
        bitcast[DType.uint64](original[1][0].low),
        bitcast[DType.uint64](counted[1][0].low),
    )
    assert_equal(
        bitcast[DType.uint64](original[1][0].high),
        bitcast[DType.uint64](counted[1][0].high),
    )
    assert_equal(
        bitcast[DType.uint64](original[1][1].low),
        bitcast[DType.uint64](counted[1][1].low),
    )
    assert_equal(
        bitcast[DType.uint64](original[1][1].high),
        bitcast[DType.uint64](counted[1][1].high),
    )
    assert_equal(
        bitcast[DType.uint64](original[1][2].low),
        bitcast[DType.uint64](counted[1][2].low),
    )
    assert_equal(
        bitcast[DType.uint64](original[1][2].high),
        bitcast[DType.uint64](counted[1][2].high),
    )


def test_invalid_mutated_node_ledgers_are_refused_before_increment() raises:
    var negative = _ProofNodeWork(-1)
    with assert_raises(contains="node budget is not valid"):
        _ = negative.take()
    var used = _ProofNodeWork(1)
    used.used = -1
    with assert_raises(contains="node budget is not valid"):
        _ = used.take()
    used.used = 2
    with assert_raises(contains="node budget is not valid"):
        _ = used.take()
    assert_equal(used.used, 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
