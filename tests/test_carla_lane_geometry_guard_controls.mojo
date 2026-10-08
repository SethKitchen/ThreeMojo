# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Finite tiny-curvature and canonical derivative boundary controls."""

from extensions.carla.geometry import ARC, LINE, RoadGeometry
from extensions.carla.lane_geometry import (
    _lane_arc_offset,
    _lane_arc_offset_derivative,
    _lane_geometry_derivative_at,
)
from std.math import isfinite, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def test_tiny_arc_radius_overflow_preserves_finite_offset_and_tangent() raises:
    # The inverse radius overflows, but curvature, offset and displacement
    # are finite. The circular result converges to a line with finite offset.
    for curvature in [Float64(1e-310), Float64(-1e-310)]:
        var geometry = RoadGeometry(ARC, 0.0, 0.0, 0.0, 0.0, 4.0)
        geometry.curvature_start = curvature
        geometry.curvature_end = curvature
        var point = _lane_arc_offset(geometry, 3.0, 2.0)
        assert_true(isfinite(point.x))
        assert_true(isfinite(point.y))
        assert_equal(point.x, Float64(3.0))
        assert_equal(point.y, Float64(-2.0))
        assert_equal(point.tangent, curvature * 3.0)
        var derivative = _lane_arc_offset_derivative(geometry, 3.0, 2.0, 0.5)
        assert_almost_equal(derivative[0], Float64(1.0), atol=1e-12, rtol=0)
        assert_almost_equal(derivative[1], Float64(-0.5), atol=1e-12, rtol=0)


def test_canonical_derivative_checks_distance_and_heading_independently() raises:
    var geometry = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 4.0)
    with assert_raises(contains="finite distance and heading"):
        _ = _lane_geometry_derivative_at(geometry, nan[DType.float64]())
    geometry.heading = nan[DType.float64]()
    with assert_raises(contains="finite distance and heading"):
        _ = _lane_geometry_derivative_at(geometry, 1.0)
    geometry.heading = 0.0
    assert_equal(_lane_geometry_derivative_at(geometry, 1.0), (1.0, 0.0, 0.0))


def test_canonical_derivative_keeps_both_clamped_sides_zero() raises:
    var geometry = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 4.0)
    for distance in [-1.0, 5.0]:
        assert_equal(
            _lane_geometry_derivative_at(geometry, distance), (0.0, 0.0, 0.0)
        )
    for distance in [0.0, 4.0]:
        assert_equal(
            _lane_geometry_derivative_at(geometry, distance), (1.0, 0.0, 0.0)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
