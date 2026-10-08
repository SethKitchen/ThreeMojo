# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Positive and adjacent-boundary pairs from unchanged valid arithmetic graphs."""

from extensions.carla.curve_bounds import (
    _sample_jet,
    _geometry_distance,
    _lane_jet,
    _spiral_counts,
)
from extensions.carla.curve_interval import (
    _Jet,
    _ValueJet,
    _next_down,
    _next_up,
)
from extensions.carla.curve_trig import _curve_atan2
from extensions.carla.geometry import (
    RoadGeometry,
    PARAM_POLY3,
    POLY3,
    LINE,
    SPIRAL,
    NORMALIZED,
    with_param_poly3,
    with_poly3,
    with_spiral,
)
from extensions.carla.junction_bounds import (
    _certify_junction_span,
    _centered_elevation_enclosure,
)
from extensions.carla.lane_value_bounds import (
    _lane_value_bound,
    _sample_value,
    _atan2_value,
    _reference_sampled_value,
)
from extensions.carla.road_info import RoadInfoGeometry, RoadInfoLaneWidth
from extensions.carla.spiral_grouped_lane import _try_grouped_lane_jet
from extensions.carla.spiral_grouped_roundoff_proof import (
    _try_spiral_grouped_roundoff_envelope,
)
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.polynomial import CubicPolynomial
from math.bounds import Box3
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from std.memory import bitcast
from tests._spiral_domain_controls import _road
from tests.test_carla_junction_arithmetic_states import _line, _valid, _point


def test_valid_record_and_tangent_domains_keep_conservative_fallbacks() raises:
    var road = _line()
    road.info.geometries[0].geometry.length = 10.0
    road.info.geometries.append(
        RoadInfoGeometry(10.0, RoadGeometry(LINE, 10.0, 10.0, 0.0, 0.0, 10.0))
    )
    _valid(road)
    var ordinary = _lane_value_bound(road, 0, 0, 9.0, 9.5)
    assert_true(ordinary[0].rounded_value().is_finite())
    var joined = _lane_value_bound(road, 0, 0, 9.5, 10.5)
    assert_false(joined[0].rounded_value().is_finite())
    for low_y in [-3.0, 1.0]:
        var heading = _atan2_value(
            _ValueJet.variable(low_y, 3.0), _ValueJet.variable(1.0, 2.0)
        ).rounded_value()
        assert_true(heading.contains(_curve_atan2(low_y, 1.0)))
        assert_true(heading.contains(_curve_atan2(3.0, 1.0)))
    var poly = with_poly3(
        RoadGeometry(POLY3, 0.0, 0.0, 0.0, 0.0, 1.0), 0.0, 0.1, 0.0, 0.0
    )
    var poly_road = _road(poly.copy())
    _valid(poly_road)
    var sampled = _reference_sampled_value(
        poly, _ValueJet.variable(0.1, 0.2), Vector3(0, 0, 0)
    )
    assert_true(sampled[0].rounded_value().is_finite())
    assert_true(sampled[1].rounded_value().is_finite())


def test_grouped_lane_refuses_separate_y_and_z_arithmetic_overflow() raises:
    var maximum = bitcast[DType.float64](UInt64(0x7FEFFFFFFFFFFFFF))
    for axis in range(3):
        var geometry = with_spiral(
            RoadGeometry(
                SPIRAL,
                0.0,
                0.0,
                -maximum * 0.5 if axis == 1 else 0.0,
                0.0,
                20.0,
            ),
            0.0,
            0.0,
        )
        var road = _road(geometry.copy())
        if axis == 1:
            road.sections[0].lanes[0].info.widths[
                0
            ].polynomial = CubicPolynomial.constant(maximum)
            road.info.lane_offsets[0].polynomial = CubicPolynomial.constant(0.0)
        elif axis == 2:
            road.info.elevations[0].polynomial = CubicPolynomial(
                -1.7e308, 1.7e308, 1e307, 0.0, 0.0
            )
        _valid(road)
        var d = _geometry_distance(geometry, _Jet.variable(2.125, 2.25))
        var counts = _spiral_counts(geometry, d)
        assert_equal(counts[0], 4)
        assert_equal(counts[1], 4)
        assert_true(
            Bool(_try_spiral_grouped_roundoff_envelope(geometry, d, counts[0]))
        )
        var full = _lane_jet(road, 0, 0, 2.125, 2.25)
        assert_true(full[0].rounded_value().is_finite())
        assert_equal(full[1].rounded_value().is_finite(), axis != 1)
        assert_equal(full[2].rounded_value().is_finite(), axis != 2)
        var nodes = 0
        var terms = 0
        var result = _try_grouped_lane_jet(
            road, 0, 0, 2.125, 2.25, nodes, terms, 100, 10000
        )
        assert_equal(Bool(result), axis == 0)
        assert_equal(nodes, 1)
        assert_equal(terms, 12)


def test_valid_width_record_join_requires_split() raises:
    var road = _line()
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(10.0, CubicPolynomial.constant(4.0))
    )
    _valid(road)
    for low in [9.0, 10.0]:
        var ordinary = _lane_value_bound(road, 0, 0, low, low + 0.5)
        assert_true(ordinary[0].rounded_value().is_finite())
        assert_true(ordinary[1].rounded_value().is_finite())
        assert_true(ordinary[2].rounded_value().is_finite())
    var joined = _lane_value_bound(road, 0, 0, 9.5, 10.5)
    assert_false(joined[0].rounded_value().is_finite())
    assert_false(joined[1].rounded_value().is_finite())
    assert_false(joined[2].rounded_value().is_finite())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
