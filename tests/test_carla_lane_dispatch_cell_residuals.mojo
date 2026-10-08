# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Original-owner sample cuts must stay inside each retained search cell."""

from extensions.carla.geometry import PARAM_POLY3, RoadGeometry, _Sample
from extensions.carla.lane_refinement import (
    _ClosedInterval,
    _ClosedIntervals,
    _run_lane_search,
)
from extensions.carla.road_info import RoadInfoGeometry
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._lazy_taylor_controls import _whole_certificate
from tests.test_carla_cross_candidate_certificates import _road


def test_saved_dispatch_cuts_are_rechecked_against_each_current_cell() raises:
    var road = _road()
    var geometry = RoadGeometry(PARAM_POLY3, 0.0, 0.0, 0.0, 0.0, 3.0)
    # Three linear traversals revisit x=0 at s=0.5, 1.5 and 2.5.
    # The query remains one unit off every traversal, so no scalar sample
    # can incorrectly trigger the zero-distance completion shortcut.
    for i in range(4):
        var x = Float64(-1.0 if i % 2 == 0 else 1.0)
        geometry.samples.append(_Sample(x, 0.0, Float64(i), 1.0, 0.0))
    road.length = 3.0
    road.info.geometries[0] = RoadInfoGeometry(0.0, geometry^)
    var location = Vector3(0, 1, 0)
    for first_cell in range(3):
        var pending = List[Tuple[Float64, Float64, Int]]()
        var seed = Float64(0.5)
        if first_cell == 0:
            pending.append((0.1, 2.9, 0))
        elif first_cell == 1:
            pending.append((0.1, 1.1, 0))
            pending.append((1.1, 2.9, 0))
            seed = 1.5
        else:
            pending.append((0.1, 2.1, 0))
            pending.append((2.1, 2.9, 0))
            seed = 2.5
        var certificate = _whole_certificate(road, location, 0.1, 2.9, seed)
        with assert_raises(contains="numerical accuracy limit"):
            _run_lane_search(
                road,
                0,
                0,
                0.1,
                2.9,
                location,
                certificate,
                pending^,
                _ClosedIntervals(),
                List[_ClosedInterval](),
                (Float64(0.0), Float64(1.0)),
                100,
                10000,
                3,
            )
        assert_false(certificate.exact_witness)
        assert_equal(certificate.s, seed)
        assert_equal(certificate.point[0], 0.0)
        assert_equal(certificate.point[1], 0.0)
        assert_true(certificate.nodes <= 100)
        assert_true(certificate.terms <= 10000)
        assert_equal(len(certificate.cells), 1)
        assert_equal(certificate.cells[0].low, 0.1)
        assert_equal(certificate.cells[0].high, 2.9)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
