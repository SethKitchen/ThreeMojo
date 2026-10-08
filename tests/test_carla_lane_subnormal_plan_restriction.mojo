# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""The planar minimizing-set restriction can recover subnormal spacing."""

from extensions.carla.curve_interval import _next_down, _next_up
from extensions.carla.lane_refinement import (
    _ClosedInterval,
    _lane_certificate_contains,
)
from extensions.carla.polynomial import CubicPolynomial
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true
from tests._lazy_taylor_controls import _whole_certificate
from tests.test_carla_cross_candidate_certificates import _road


def test_planar_restriction_removes_a_subnormal_nonminimizing_cell() raises:
    var road = _road(width=2e-200)
    road.info.elevations[0].polynomial = CubicPolynomial(0, 1e-40, 0, 0, 0)
    var at = bitcast[DType.float64](UInt64(0x1E6BB67AE8584CAA))
    var low = _next_down(at)
    var high = _next_up(at)
    var location = Vector3(0, 0, 0)
    var certificate = _whole_certificate(road, location, 0.0, high, 0.0)
    # The checked origin is an exact minimizing point. A conservative
    # candidate set may also retain a nonminimizing cell until classification.
    # These are possible-minimizer cells, not a partition of unsearched work.
    certificate.cells[0] = _ClosedInterval(0.0, 0.0, 0, 0.0, 1.0)
    certificate.cells.append(_ClosedInterval(low, high, 0, 0.0, 1.0))
    assert_equal(certificate.upper, 0.0)
    assert_equal(certificate.point[0], 0.0)
    assert_equal(certificate.point[1], 0.0)
    assert_equal(certificate.point[2], 0.0)
    assert_true(
        _lane_certificate_contains(road, 0, 0, location, certificate, 20, 1000)
    )
    assert_equal(certificate.nodes, 2)
    assert_true(certificate.terms <= 1000)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
