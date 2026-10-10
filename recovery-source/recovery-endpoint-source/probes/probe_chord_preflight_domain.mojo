# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Differential no-quadrature checks for newly evaluated endpoint preflights.

Malformed records are robustness checks only, not supported Road witnesses.
"""
from extensions.carla.geometry import SPIRAL
from extensions.carla.lane_refinement import _ProofNodeWork, _chord_certificate_capture_with_nodes
from extensions.carla.spiral_domain_proof import _SpiralRootCapture
from math.vector3 import Vector3
from probe_chord_endpoint_refusals import _road
from std.math import inf, nan
from std.testing import TestSuite, assert_equal


def _check(low: Float64, high: Float64, variant: Int) raises:
    var road = _road(False, False)
    if variant == 1:
        road.info.geometries.clear()
    elif variant >= 2:
        road.info.geometries[0].geometry.kind = SPIRAL
        if variant == 2:
            road.info.geometries[0].geometry.length = 0.0
        elif variant == 3:
            road.info.geometries[0].geometry.length = -1.0
        elif variant == 4:
            road.info.geometries[0].geometry.length = nan[DType.float64]()
        elif variant == 5:
            road.info.geometries[0].geometry.length = inf[DType.float64]()
        elif variant == 6:
            road.info.geometries[0].geometry.curvature_start = nan[DType.float64]()
        elif variant == 7:
            road.info.geometries[0].geometry.curvature_end = inf[DType.float64]()
    var nodes = _ProofNodeWork(1, fail_on_limit=False)
    var captured = _SpiralRootCapture()
    # This is a genuine zero remaining term budget, so even a one-term
    # traversal is refused. Newly evaluated counts cannot trigger GL work.
    var result = _chord_certificate_capture_with_nodes(road, 0, 0, low, high, Vector3(1, 0, 0), Vector3(3, 0, 0), captured, nodes, 0)
    assert_equal(result[0], inf[DType.float64]())
    for value in [result[1][0], result[1][1], result[1][2]]:
        assert_equal(value.low, -inf[DType.float64]())
        assert_equal(value.high, inf[DType.float64]())
    assert_equal(result[2], 0)
    assert_equal(nodes.used, 1)
    print("PREFLIGHT_DOMAIN", variant, result[2], nodes.used)


def test_nonfinite_and_reversed_station_preflights() raises:
    for pair in [(nan[DType.float64](), Float64(3)), (Float64(1), nan[DType.float64]()), (-inf[DType.float64](), Float64(3)), (Float64(1), inf[DType.float64]()), (inf[DType.float64](), inf[DType.float64]()), (Float64(3), Float64(1))]:
        _check(pair[0], pair[1], 0)


def test_empty_and_malformed_record_preflights_remain_nonraising() raises:
    for variant in range(1, 8):
        _check(1.0, 3.0, variant)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
