# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bounded CARLA geometry and record validation controls."""

from extensions.carla.geometry import POLY3, _Sample
from extensions.carla.junction_bounds import (
    _geometry_rates,
    _lane_section_box,
    _span_box,
)
from extensions.carla.map_builder import MapBuilder
from extensions.carla.polynomial import CubicPolynomial
from std.math import inf
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from tests.test_carla_junction_bounds import _road


def test_clamped_curved_geometry_has_zero_rates() raises:
    var builder = MapBuilder()
    var r = _road(builder, 1, 2, -1)
    builder.add_road_geometry_arc(r, 0, 0, 0, 0, 2, 0.5)
    var geometry = builder.roads[r].info.geometries[0].geometry.copy()
    var active = _geometry_rates(geometry, 0, 1)
    assert_equal(active[0], 0.5)
    var clamped = _geometry_rates(geometry, 2, 3)
    assert_equal(clamped[0], 0.0)
    assert_equal(clamped[1], 0.0)
    assert_equal(clamped[2], 0.0)
    assert_true(clamped[3])


def test_repeated_sample_abscissa_is_refused() raises:
    var builder = MapBuilder()
    var r = _road(builder, 1, 2, -1)
    builder.add_road_geometry_line(r, 0, 0, 0, 0, 2)
    var geometry = builder.roads[r].info.geometries[0].geometry.copy()
    geometry.kind = POLY3
    geometry.samples = [
        _Sample(0, 0, 0, 1, 0),
        _Sample(1, 0, 0, 1, 0),
    ]
    with assert_raises(contains="zero-length sample interval"):
        _ = _geometry_rates(geometry, 0, 1)


def test_each_missing_span_record_is_refused() raises:
    for kind in range(3):
        var builder = MapBuilder()
        var r = _road(builder, 1, 2, -1)
        builder.add_road_geometry_line(r, 0, 0, 0, 0, 2)
        if kind == 0:
            builder.roads[r].info.geometries.clear()
        elif kind == 1:
            builder.roads[r].info.lane_offsets.clear()
        else:
            builder.roads[r].info.elevations.clear()
        with assert_raises(contains="missing a geometry, offset, or elevation"):
            _ = _span_box(builder.roads[r], 0, 0, 0, 1)


def test_nonfinite_and_reversed_section_intervals_are_refused() raises:
    for kind in range(3):
        var builder = MapBuilder()
        var r = _road(builder, 1, 2, -1)
        builder.add_road_geometry_line(r, 0, 0, 0, 0, 2)
        if kind == 0:
            builder.roads[r].sections[0].s = inf[DType.float64]()
        elif kind == 1:
            builder.roads[r].length = inf[DType.float64]()
        else:
            builder.roads[r].sections[0].s = 3
        with assert_raises(contains="invalid section interval"):
            _ = _lane_section_box(builder.roads[r], 0, 0)


def test_nonfinite_bounds_fail_before_sampling() raises:
    for kind in range(3):
        var builder = MapBuilder()
        var r = _road(builder, 1, 2, -1)
        builder.add_road_geometry_line(r, 0, 0, 0, 0, 2)
        if kind == 0:
            builder.roads[r].info.lane_offsets[0].polynomial.c = 1e307
        elif kind == 1:
            builder.roads[r].info.lane_offsets[0].polynomial = CubicPolynomial(
                inf[DType.float64](), 0, 0, 0, 0
            )
        else:
            builder.roads[r].info.elevations[0].polynomial = CubicPolynomial(
                inf[DType.float64](), 0, 0, 0, 0
            )
        with assert_raises(contains="non-finite bounds"):
            _ = _span_box(builder.roads[r], 0, 0, 0, 1)


def test_lane_transform_refuses_missing_geometry_and_nonfinite_slope() raises:
    var builder = MapBuilder()
    var r = _road(builder, 1, 2, -1)
    builder.add_road_geometry_line(r, 0, 0, 0, 0, 2)
    builder.roads[r].info.geometries.clear()
    with assert_raises(contains="no geometry"):
        _ = builder.roads[r].lane_transform(0, 0, 0)
    builder.add_road_geometry_line(r, 0, 0, 0, 0, 2)
    # At s=1, 1e308*s^2 is finite, while its derivative 2e308 overflows.
    builder.roads[r].info.lane_offsets[0].polynomial.c = 1e308
    with assert_raises(contains="offset or derivative is not representable"):
        _ = builder.roads[r].lane_transform(0, 0, 1)


def test_only_y_lane_derivative_overflow_is_refused() raises:
    var builder = MapBuilder()
    var r = _road(builder, 1, 2, -1)
    builder.add_road_geometry_line(r, 0, 0, 0, 0, 2)
    ref geometry = builder.roads[r].info.geometries[0].geometry
    geometry.kind = POLY3
    geometry.heading = 0.7853981633974483
    geometry.samples = [
        _Sample(0, 0, 0, 1, 1),
        _Sample(1.5e308, 1.5e308, 1, 1, 1),
    ]
    # Both stored differences are finite. Rotation cancels dx, while
    # adding their positive y contributions exceeds Float64 range.
    with assert_raises(contains="Lane center derivative is not representable"):
        _ = builder.roads[r].lane_transform(0, 0, 0)


def test_curved_lane_slope_and_elevation_disable_constant_arc_shortcut() raises:
    for elevated in [False, True]:
        var builder = MapBuilder()
        var r = _road(builder, 1, 2, -1)
        builder.add_road_geometry_arc(r, 0, 0, 0, 0, 2, 0.5)
        if elevated:
            builder.roads[r].info.elevations[0].polynomial.c = 1
        else:
            builder.roads[r].info.lane_offsets[0].polynomial.b = 1
        var box = _span_box(builder.roads[r], 0, 0, 0, 1)
        for i in range(18):
            var s = Float64(i) / 17.0
            assert_true(
                box.contains_point(
                    builder.roads[r].lane_transform(0, 0, s).location
                )
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
