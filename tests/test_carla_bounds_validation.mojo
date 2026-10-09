# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bounded CARLA geometry and record validation controls."""

from extensions.carla.curve_bounds import (
    _lane_jet,
    _lane_jet_with_proof,
    _reference_jet,
)
from extensions.carla.curve_interval import _Jet
from extensions.carla.geometry import (
    LINE,
    POLY3,
    RoadGeometry,
    _Sample,
    with_poly3,
)
from extensions.carla.junction_bounds import (
    _geometry_rates,
    _lane_section_box,
    _lane_section_box_with_work,
    _span_box,
)
from extensions.carla.map_builder import MapBuilder
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.polynomial import CubicPolynomial
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._spiral_domain_controls import (
    _canonical_contains,
    _geometry as _proof_geometry,
    _point_bits,
    _proof,
    _road as _proof_road,
)
from tests.test_carla_curve_arithmetic_states import (
    _valid as _valid_curve_road,
)
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
        var work = _MapBuildWork(MapBuildBudget())
        with assert_raises(contains="missing a geometry, offset, or elevation"):
            _ = _span_box(builder.roads[r], 0, 0, 0, 1, work)


def test_nonfinite_and_reversed_section_intervals_are_refused() raises:
    for kind in range(4):
        var builder = MapBuilder()
        var r = _road(builder, 1, 2, -1)
        builder.add_road_geometry_line(r, 0, 0, 0, 0, 2)
        if kind == 0:
            builder.roads[r].sections[0].s = inf[DType.float64]()
        elif kind == 1:
            builder.roads[r].length = inf[DType.float64]()
        elif kind == 2:
            builder.roads[r].sections[0].s = 3
        else:
            builder.roads[r].sections[0].s = -1
        # The wrapper rejects invalid input during global preflight.
        with assert_raises(contains="invalid finite domain"):
            _ = _lane_section_box(builder.roads[r], 0, 0)
        # Keep coverage of the original lower interval guard as well.
        var work = _MapBuildWork(MapBuildBudget())
        with assert_raises(contains="invalid section interval"):
            _ = _lane_section_box_with_work(builder.roads[r], 0, 0, work)


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
        var work = _MapBuildWork(MapBuildBudget())
        with assert_raises(contains="non-finite bounds"):
            _ = _span_box(builder.roads[r], 0, 0, 0, 1, work)


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
        var work = _MapBuildWork(MapBuildBudget())
        var box = _span_box(builder.roads[r], 0, 0, 0, 1, work)
        for i in range(18):
            var s = Float64(i) / 17.0
            assert_true(
                box.contains_point(
                    builder.roads[r].lane_transform(0, 0, s).location
                )
            )


def test_nonfinite_record_start_refuses_junction_proposal() raises:
    var builder = MapBuilder()
    var r = _road(builder, 1, 2, -1)
    builder.add_road_geometry_line(r, 0, 0, 0, 0, 2)
    var ordinary = _lane_section_box(builder.roads[r], 0, 0)
    assert_true(
        ordinary.contains_point(
            builder.roads[r].lane_transform(0, 0, 1).location
        )
    )
    builder.roads[r].sections[0].lanes[0].info.widths[0].s = nan[
        DType.float64
    ]()
    # Preflight counts profile records without validating their starts.
    # Both entry points must refuse before returning a proposal box.
    with assert_raises(contains="missing a geometry, offset, or elevation"):
        _ = _lane_section_box(builder.roads[r], 0, 0)
    var work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="missing a geometry, offset, or elevation"):
        _ = _lane_section_box_with_work(builder.roads[r], 0, 0, work)


def test_incomplete_sample_tables_keep_reference_bounds_unknown() raises:
    for count in range(2):
        var geometry = with_poly3(
            RoadGeometry(POLY3, 0.0, 0.0, 0.0, 0.0, 1.0),
            0.0,
            0.1,
            0.0,
            0.0,
        )
        var ordinary = _reference_jet(
            geometry, _Jet.variable(0.1, 0.2), Vector3(0, 0, 0)
        )
        assert_true(ordinary[0].rounded_value().is_finite())
        assert_true(ordinary[1].rounded_value().is_finite())
        geometry.samples.clear()
        if count == 1:
            geometry.samples.append(_Sample(0.0, 0.0, 0.0, 1.0, 0.1))
        var unknown = _reference_jet(
            geometry, _Jet.variable(0.1, 0.2), Vector3(0, 0, 0)
        )
        for bound in [unknown[0], unknown[1], unknown[2]]:
            assert_false(bound.rounded_value().is_finite())
            assert_false(bound.first.is_finite())
            assert_false(bound.second.is_finite())


def test_each_missing_lane_bound_record_is_refused() raises:
    for kind in range(3):
        var road = _proof_road(RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 20.0))
        var ordinary = _lane_jet(road, 0, 0, 2.125, 2.25)
        _canonical_contains(road, 0, ordinary, 2.125)
        _canonical_contains(road, 0, ordinary, 2.25)
        if kind == 0:
            road.info.geometries.clear()
        elif kind == 1:
            road.info.elevations.clear()
        else:
            road.info.lane_offsets.clear()
        with assert_raises(
            contains="A lane bound needs geometry, elevation and offset records"
        ):
            _ = _lane_jet(road, 0, 0, 2.125, 2.25)


def test_spiral_proof_cannot_replace_sampled_geometry_bounds() raises:
    var spiral_road = _proof_road(_proof_geometry())
    _valid_curve_road(spiral_road)
    var proof = _proof(spiral_road, 2.125, 2.25)
    var owned = _lane_jet_with_proof(
        spiral_road, 0, 0, 2.125, 2.25, 2.125, 2.25, proof
    )
    _canonical_contains(spiral_road, 0, owned, 2.125)
    _canonical_contains(spiral_road, 0, owned, 2.25)
    var geometry = with_poly3(
        RoadGeometry(POLY3, 0.0, 0.0, 0.0, 0.0, 20.0),
        0.0,
        0.1,
        0.0,
        0.0,
    )
    var road = _proof_road(geometry^)
    _valid_curve_road(road)
    var expected = _lane_jet(road, 0, 0, 2.125, 2.25)
    var actual = _lane_jet_with_proof(
        road, 0, 0, 2.125, 2.25, 2.125, 2.25, proof
    )
    _point_bits(actual, expected)
    for bound in [actual[0], actual[1], actual[2]]:
        assert_true(bound.rounded_value().is_finite())
    for station in [2.125, 2.1875, 2.25]:
        _canonical_contains(road, 0, actual, station)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
