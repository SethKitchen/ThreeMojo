# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""A strict subinterval sign fixes a sampled positive-zero offset heading."""

from extensions.carla.curve_bounds import _sample_jet
from extensions.carla.curve_interval import _Jet
from extensions.carla.curve_trig import _curve_atan2
from extensions.carla.geometry import PARAM_POLY3, RoadGeometry, _Sample
from extensions.carla.lane_geometry import _lane_geometry_pos_at
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def _geometry(vertical: Float64 = 0.0) raises -> RoadGeometry:
    var geometry = RoadGeometry(PARAM_POLY3, 0, 0, 0, 0, 1)
    geometry.samples.append(_Sample(0, 0, 0, -1, vertical))
    geometry.samples.append(_Sample(1, 0, 1, 1, vertical))
    return geometry^


def test_strict_negative_subinterval_retains_exact_positive_pi_heading() raises:
    var geometry = _geometry()
    var result = _sample_jet(
        geometry, _Jet.variable(0.1, 0.2), 0, Vector3(0, 0, 0)
    )[2]
    assert_equal(result.value.low, _curve_atan2(0.0, -1.0))
    assert_equal(result.value.high, _curve_atan2(0.0, -1.0))
    assert_true(result.first.is_point(0.0))
    assert_true(result.second.is_point(0.0))
    for station in [0.1, 0.15, 0.2]:
        assert_true(
            result.rounded_value().contains(
                _lane_geometry_pos_at(geometry, station).tangent
            )
        )


def test_strict_positive_subinterval_retains_exact_zero_heading() raises:
    var geometry = _geometry()
    var result = _sample_jet(
        geometry, _Jet.variable(0.8, 0.9), 0, Vector3(0, 0, 0)
    )[2]
    assert_true(result.value.is_point(0.0))
    assert_true(result.first.is_point(0.0))
    assert_true(result.second.is_point(0.0))
    for station in [0.8, 0.85, 0.9]:
        assert_true(
            result.rounded_value().contains(
                _lane_geometry_pos_at(geometry, station).tangent
            )
        )


def test_zero_crossing_keeps_branch_uncertainty() raises:
    var geometry = _geometry()
    var result = _sample_jet(
        geometry, _Jet.variable(0.4, 0.6), 0, Vector3(0, 0, 0)
    )[2]
    assert_false(result.first.is_finite())
    for station in [0.4, 0.5, 0.6]:
        assert_true(
            result.rounded_value().contains(
                _lane_geometry_pos_at(geometry, station).tangent
            )
        )


def test_negative_zero_vertical_samples_do_not_get_positive_pi_proof() raises:
    var geometry = _geometry(-0.0)
    var result = _sample_jet(
        geometry, _Jet.variable(0.1, 0.2), 0, Vector3(0, 0, 0)
    )[2]
    for station in [0.1, 0.15, 0.2]:
        assert_true(
            result.rounded_value().contains(
                _lane_geometry_pos_at(geometry, station).tangent
            )
        )
    assert_true(result.rounded_value().contains(_curve_atan2(-0.0, -1.0)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
