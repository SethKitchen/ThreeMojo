# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""An interior optional ARC proof step preserves the caller's depth limit."""

from extensions.carla.geometry import ARC
from extensions.carla.lane_refinement import _try_rounded_arc_witness
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_false
from tests._lazy_taylor_controls import _whole_certificate
from tests.test_carla_cross_candidate_certificates import _road


def test_optional_arc_interior_step_cannot_reset_retained_depth() raises:
    var road = _road()
    road.info.geometries[0].geometry.kind = ARC
    road.info.geometries[0].geometry.curvature_start = 0.125
    var certificate = _whole_certificate(road, Vector3(0, 0, 0), 1.0, 2.0, 1.0)
    var original = certificate.point.copy()
    var proved = _try_rounded_arc_witness(
        road, 0, 0, 1.0, 2.0, [0.0, 0.0, 0.0], certificate, 100, 1000, 0
    )
    assert_false(proved)
    assert_false(certificate.exact_witness)
    assert_equal(certificate.s, 1.0)
    assert_equal(certificate.nodes, 1)
    for axis in range(3):
        assert_equal(certificate.point[axis], original[axis])
    assert_equal(len(certificate.cells), 1)
    assert_equal(certificate.cells[0].low, 1.0)
    assert_equal(certificate.cells[0].high, 2.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
