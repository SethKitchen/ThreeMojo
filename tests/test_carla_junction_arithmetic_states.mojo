# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Junction arithmetic controls from complete, finite road records.

Each road passes the maintained preflight. No record, proof, or work counter
is corrupted. A proposed box may need expansion; certification owns that job.
"""

from extensions.carla.curve_interval import _next_up
from extensions.carla.geometry import RoadGeometry, LINE
from extensions.carla.junction_bounds import (
    _canonical_endpoint,
    _certify_junction_span,
    _centered_elevation_enclosure,
    _lane_section_box,
)
from extensions.carla.lane_value_bounds import _lane_value_bound
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.map_validation import _preflight_road_records
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import LaneId, SectionId, RoadInfoLaneWidth
from math.bounds import Box3
from math.vector3 import Vector3
from std.math import isfinite
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
    assert_raises,
)
from tests._spiral_domain_controls import _road


def _line(
    x: Float64 = 0.0, y: Float64 = 0.0, length: Float64 = 20.0
) raises -> Road:
    return _road(RoadGeometry(LINE, 0.0, x, y, 0.0, length))


def _valid(road: Road) raises:
    var work = _MapBuildWork(MapBuildBudget())
    _preflight_road_records(road, work)
    assert_false(work.exhausted)
    for record in road.info.elevations:
        assert_true(isfinite(record.polynomial.a))
        assert_true(isfinite(record.polynomial.b))
        assert_true(isfinite(record.polynomial.c))
        assert_true(isfinite(record.polynomial.d))


def _point(road: Road, section: Int, station: Float64) raises -> Vector3:
    var value = road._lane_center(section, 0, station)
    return Vector3(Float32(value[0]), Float32(value[1]), Float32(value[2]))


def test_equal_station_certification_covers_its_canonical_point() raises:
    var road = _line()
    _valid(road)
    var box = Box3.empty()
    var work = _MapBuildWork(MapBuildBudget())
    _certify_junction_span(road, 0, 0, 2.0, 2.0, box, work)
    assert_true(box.contains_point(_point(road, 0, 2.0)))
    assert_true(work.terms > 0)
    assert_false(work.exhausted)


def test_adjacent_stations_certify_both_midpoint_rounding_directions() raises:
    var road = _line()
    road.info.elevations[0].polynomial = CubicPolynomial(
        0.0, 1.0, 0.0, 0.0, 0.0
    )
    _valid(road)
    for low in [1.0, _next_up(1.0)]:
        var high = _next_up(low)
        for boundary in range(3):
            # The endpoints have the same public Float32 z=1. The ideal
            # interval and its rounding allowance can cross that exact box.
            var box = Box3(Vector3(-100, -100, 0), Vector3(100, 100, 2))
            if boundary == 1:
                box.min.z = 1.0
            elif boundary == 2:
                box.max.z = 1.0
            var work = _MapBuildWork(MapBuildBudget())
            _certify_junction_span(road, 0, 0, low, high, box, work)
            assert_true(box.contains_point(_point(road, 0, low)))
            assert_true(box.contains_point(_point(road, 0, high)))
            assert_false(work.exhausted)


def test_one_ulp_section_skips_an_empty_interior_but_keeps_endpoints() raises:
    var end = _next_up(1.0)
    var road = _line(length=end)
    var section = road.add_section(SectionId(1), 1.0)
    _ = road.sections[section].add_lane(LaneId(-1))
    road.sections[section].lanes[0].info.widths.append(
        RoadInfoLaneWidth(1.0, CubicPolynomial.constant(3.5))
    )
    _valid(road)
    var box = _lane_section_box(road, section, 0)
    assert_true(box.contains_point(_point(road, section, 1.0)))
    assert_true(box.contains_point(_point(road, section, end)))


def test_finite_double_endpoints_refuse_public_coordinate_overflow() raises:
    for axis in range(4):
        var road = _line(1e40 if axis == 1 else 0.0, 1e40 if axis == 2 else 0.0)
        if axis == 3:
            road.info.elevations[0].polynomial = CubicPolynomial.constant(1e40)
        _valid(road)
        var work = _MapBuildWork(MapBuildBudget())
        if axis == 0:
            var point = _canonical_endpoint(road, 0, 0, 1.0, work)
            assert_true(
                isfinite(point.x) and isfinite(point.y) and isfinite(point.z)
            )
        else:
            with assert_raises(
                contains="canonical endpoint is not finite in public storage"
            ):
                _ = _canonical_endpoint(road, 0, 0, 1.0, work)
        assert_false(work.exhausted)
        assert_true(work.terms > 0)


def test_finite_extreme_origins_refuse_each_overflowing_proposal_face() raises:
    var maximum = Float64(bitcast[DType.float32](UInt32(0x7F7FFFFF)))
    var ordinary = _line()
    _valid(ordinary)
    var accepted = _lane_section_box(ordinary, 0, 0)
    assert_true(accepted.contains_point(_point(ordinary, 0, 1.0)))
    for axis in range(3):
        for sign in [-1.0, 1.0]:
            var road = _line(
                sign * maximum if axis == 0 else 0.0,
                sign * maximum if axis == 1 else 0.0,
            )
            if axis == 2:
                road.info.elevations[0].polynomial = CubicPolynomial.constant(
                    sign * maximum
                )
            _valid(road)
            # Canonical points still fit. Only the necessary outward proposal
            # padding exceeds one selected Float32 face.
            var point = _point(road, 0, 1.0)
            assert_true(
                isfinite(point.x) and isfinite(point.y) and isfinite(point.z)
            )
            with assert_raises(
                contains="Junction proposal is not finite in public storage"
            ):
                _ = _lane_section_box(road, 0, 0)


def test_centered_reexpansion_overflow_keeps_the_original_finite_bound() raises:
    var road = _line()
    road.info.elevations[0].polynomial = CubicPolynomial(
        0.0, 1e308, -8e307, 0.0, 0.0
    )
    _valid(road)
    # The original Horner value at s=2 is finite. Its centered derivative
    # expansion forms 2*c and then combines it with m, which can enlarge
    # intermediate intervals even though the original value remains bounded.
    var point = _lane_value_bound(road, 0, 0, 2.0, 2.0)
    var original = point[2].rounded_value()
    assert_true(original.is_finite())
    var work = _MapBuildWork(MapBuildBudget())
    var bound = _centered_elevation_enclosure(
        road, 2.0, 2.0, original, point[2].error, work
    )
    assert_equal(bound.low, original.low)
    assert_equal(bound.high, original.high)
    assert_true(
        bound.contains(road.info.elevations[0].polynomial.evaluate(2.0))
    )
    assert_equal(work.terms, 128)


def test_finite_polynomial_overflow_exhausts_numerical_certification() raises:
    var road = _line()
    road.info.elevations[0].polynomial = CubicPolynomial(
        -1.7e308, 1.7e308, 1e307, 0.0, 0.0
    )
    _valid(road)
    var box = Box3(Vector3(-100, -100, -100), Vector3(100, 100, 100))
    var work = _MapBuildWork(MapBuildBudget())
    with assert_raises(contains="exhausted its numerical subdivision limit"):
        _certify_junction_span(road, 0, 0, 2.0, 2.01, box, work)
    assert_false(work.exhausted)
    assert_true(work.steps > 24)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
