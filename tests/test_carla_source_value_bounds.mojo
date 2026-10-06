# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Source boxes retain the full lane Jet's exact value and error fields."""

from extensions.carla.curve_bounds import _lane_jet, _arc_offset_jet
from extensions.carla.curve_interval import (
    _Jet,
    _ValueJet,
    _next_down,
    _next_up,
)
from extensions.carla.curve_trig import _sinc_jet, _constant_sincos_jet
from extensions.carla.geometry import (
    LINE,
    ARC,
    SPIRAL,
    POLY3,
    PARAM_POLY3,
    RoadGeometry,
)
from extensions.carla.lane_value_bounds import (
    _lane_value_bound,
    _arc_offset_value,
    _constant_sincos_value,
    _sinc_value,
)
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.road_info import RoadInfoElevation
from extensions.carla.polynomial import CubicPolynomial
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import TestSuite, assert_raises
from tests.test_carla_sampled_value_bounds import _equal_value
from tests.test_carla_lane_orientation import _road


def test_every_town_segment_value_and_error_matches_full_source_jet() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    for segment in map._segments:
        var at = map._locate(segment.first)
        ref road = map.roads[at[0]]
        var low = min(segment.first.s, segment.second.s)
        var high = max(segment.first.s, segment.second.s)
        var full = _lane_jet(road, at[1], at[2], low, high)
        var value = _lane_value_bound(road, at[1], at[2], low, high)
        _equal_value(full[0], value[0])
        _equal_value(full[1], value[1])
        _equal_value(full[2], value[2])


def test_sinc_and_constant_trig_retain_branch_and_signed_zero_bounds() raises:
    for low in [-10.0, -1.0, -0.8, -0.0, 0.0, 0.5, 0.8, 1.0, 10.0]:
        for width in [0.0, 1e-6, 0.1, 2.0]:
            var full = _sinc_jet(_Jet.variable(low, low + width))
            var value = _sinc_value(_ValueJet.variable(low, low + width))
            _equal_value(full, value)
    for heading in [
        -1e20,
        -1000000.0,
        -0.0,
        0.0,
        0.3,
        1000000.0,
        1e20,
        inf[DType.float64](),
        nan[DType.float64](),
    ]:
        var full = _constant_sincos_jet(heading)
        var value = _constant_sincos_value(heading)
        _equal_value(full[0], value[0])
        _equal_value(full[1], value[1])


def test_arc_value_matches_full_graph_at_scale_and_radius_limits() raises:
    for scale in [1e-200, 1.0, 1e200]:
        var geometry = RoadGeometry(ARC, 0, scale, -scale, 0.3, 1)
        for curvature in [-1e200, -2.0, -1e-320, 1e-320, 2.0, 1e200]:
            geometry.curvature_start = curvature
            var full = _arc_offset_jet(
                geometry,
                _Jet.variable(0.1, 0.9),
                _Jet.constant(scale),
                Vector3(0, 0, 0),
            )
            var value = _arc_offset_value(
                geometry,
                _ValueJet.variable(0.1, 0.9),
                _ValueJet.constant(scale),
                Vector3(0, 0, 0),
            )
            _equal_value(full[0], value[0])
            _equal_value(full[1], value[1])
            _equal_value(full[2], value[2])


def test_all_geometry_kinds_keep_clamps_record_joins_and_missing_records() raises:
    for kind in [LINE, ARC, SPIRAL, POLY3, PARAM_POLY3]:
        var road = _road(kind)
        for low in [
            0.0,
            _next_up(0.0),
            1.0,
            19.9,
            _next_down(20.0),
            20.0,
            20.1,
        ]:
            for width in [0.0, 0.01]:
                var high = low + width
                for lane in range(5):
                    var full = _lane_jet(road, 0, lane, low, high)
                    var value = _lane_value_bound(road, 0, lane, low, high)
                    _equal_value(full[0], value[0])
                    _equal_value(full[1], value[1])
                    _equal_value(full[2], value[2])
        road.info.elevations.append(
            RoadInfoElevation(10.0, CubicPolynomial.constant(2.0))
        )
        var full = _lane_jet(road, 0, 0, 9.0, 11.0)
        var value = _lane_value_bound(road, 0, 0, 9.0, 11.0)
        _equal_value(full[0], value[0])
        _equal_value(full[1], value[1])
        _equal_value(full[2], value[2])
        road.info.elevations.clear()
        with assert_raises(contains="geometry, elevation and offset"):
            _ = _lane_value_bound(road, 0, 0, 0.0, 1.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
