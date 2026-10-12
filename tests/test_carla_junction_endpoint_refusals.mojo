# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Genuine direct-helper first/last endpoint fallback controls.

The first mode4 vector always runs. Last-end DAZ vectors require the
unchanged fixture to expose x86 modes5/6; unavailable capability is reported
explicitly. No ordinary public Map reachability is claimed.

Link only the unchanged tools/fixtures/carla_sum2_fp_state.c test fixture.
No quadrature executes: actual unsupported-state producers return unknown
plan coordinates, while an independent elevation remains finite.
"""
from extensions.carla.curve_bounds import _reference_work
from extensions.carla.curve_interval import _Interval, _next_down, _next_up
from extensions.carla.curve_sum2 import _sum2_supported_environment
from extensions.carla.geometry import SPIRAL, RoadGeometry
from extensions.carla.junction_bounds import _monotone_junction_enclosure
from extensions.carla.lane_value_bounds import _lane_value_bound
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.map_validation import _preflight_road_records
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    LANE_DRIVING,
    NO_JUNCTION,
    LaneId,
    RoadId,
    RoadInfoElevation,
    RoadInfoGeometry,
    RoadInfoLaneOffset,
    RoadInfoLaneWidth,
    SectionId,
)
from math.bounds import Box3
from math.vector3 import Vector3
from std.ffi import external_call
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
    assert_raises,
)


def _first_road() raises -> Road:
    var curvature = Float64(1e9 - 1)
    for _ in range(6):
        curvature = _next_down(curvature)
    var geometry = RoadGeometry(SPIRAL, 0, 0, 0, 0, 2)
    geometry.curvature_start = curvature
    geometry.curvature_end = curvature
    var road = Road(
        RoadId(1),
        "direct junction helper refusal",
        2.0,
        NO_JUNCTION,
        RoadId(0),
        RoadId(0),
        True,
    )
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(-1.0, CubicPolynomial.constant(2.0))
    )
    road.info.geometries.append(RoadInfoGeometry(-1.0, geometry^))
    road.info.elevations.append(
        RoadInfoElevation(-1.0, CubicPolynomial(2.0, 1.0, 0.0, 0.0, 0.0))
    )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(-1.0, CubicPolynomial.constant(1.0))
    )
    var validation = _MapBuildWork(MapBuildBudget())
    _preflight_road_records(road, validation)
    assert_false(validation.exhausted)
    return road^


def _same(one: _Interval, two: _Interval) raises:
    assert_equal(bitcast[DType.uint64](one.low), bitcast[DType.uint64](two.low))
    assert_equal(
        bitcast[DType.uint64](one.high), bitcast[DType.uint64](two.high)
    )


def _first_endpoint_control() raises:
    var road = _first_road()
    var low = -bitcast[DType.float64](UInt64(622) << UInt64(52))
    var high = Float64(0)
    # The finite proposal leaves elevation at its public Float32 value2.
    # Its broad XY extent is an ordinary proposal, not an injected Jet.
    var proposal = Box3(Vector3(-2, -2, 2), Vector3(2, 2, 2))
    assert_true(_sum2_supported_environment())
    var original = external_call["sum2_test_set_mode", UInt64](Int32(4))
    try:
        var mask = external_call["sum2_test_control_mask", UInt64]()
        var actual = external_call["sum2_test_get_state", UInt64]()
        var expected = external_call["sum2_test_mode_bits", UInt64](Int32(4))
        assert_equal(actual & mask, expected)
        assert_false(_sum2_supported_environment())
        var terms = _reference_work(road, low, high)
        assert_equal(terms, 5000000005)
        assert_equal(_reference_work(road, low, low), -1)
        assert_equal(_reference_work(road, high, high), 5000000005)
        var point = _lane_value_bound(road, 0, 0, low, high)
        var x = point[0].rounded_value()
        var y = -point[1].rounded_value()
        var z = point[2].rounded_value()
        assert_false(x.is_finite())
        assert_false(y.is_finite())
        assert_true(z.is_finite())
        assert_true(z.low < 2.0 or z.high > 2.0)
        var work = _MapBuildWork(MapBuildBudget(0, 5, terms, 0))
        var result = _monotone_junction_enclosure(
            road, 0, 0, low, high, terms, proposal, x, y, z, work
        )
        _same(result[0], x)
        _same(result[1], y)
        _same(result[2], z)
        assert_equal(work.steps, 5)
        assert_equal(work.terms, terms)
        assert_false(work.exhausted)
        var short = _MapBuildWork(MapBuildBudget(0, 5, terms - 1, 0))
        with assert_raises(contains="global term budget"):
            _ = _monotone_junction_enclosure(
                road, 0, 0, low, high, terms, proposal, x, y, z, short
            )
        assert_equal(short.steps, 1)
        assert_equal(short.terms, 0)
        assert_true(short.exhausted)
        print(
            "REFUSAL_LEDGER", work.steps, work.terms, short.steps, short.terms
        )
    except error:
        external_call["sum2_test_restore_mode", NoneType](original)
        raise error
    external_call["sum2_test_restore_mode", NoneType](original)
    assert_equal(external_call["sum2_test_get_state", UInt64](), original)
    assert_true(_sum2_supported_environment())


def _last_road() raises -> Road:
    var curvature = bitcast[DType.float64](UInt64(13965043853212778490))
    var length = bitcast[DType.float64](UInt64(2022) << UInt64(52))
    var geometry = RoadGeometry(SPIRAL, 0, 0, 0, 0, length)
    geometry.curvature_start = curvature
    geometry.curvature_end = _next_up(curvature)
    var road = Road(
        RoadId(1),
        "direct last-end junction helper refusal",
        2.0,
        NO_JUNCTION,
        RoadId(0),
        RoadId(0),
        True,
    )
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(0.0, CubicPolynomial.constant(2.0))
    )
    road.info.geometries.append(RoadInfoGeometry(0.0, geometry^))
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial(2.0, 1.0, 0.0, 0.0, 0.0))
    )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(0.0, CubicPolynomial.constant(1.0))
    )
    var validation = _MapBuildWork(MapBuildBudget())
    _preflight_road_records(road, validation)
    assert_false(validation.exhausted)
    return road^


def _last_endpoint_control(mode: Int32) raises:
    var road = _last_road()
    var low = bitcast[DType.float64](UInt64(4607182418800017407))
    var high = bitcast[DType.float64](UInt64(4607182418800017409))
    # The finite proposal leaves elevation at its public Float32 value3.
    # Its broad XY extent is an ordinary proposal, not an injected Jet.
    var proposal = Box3(Vector3(-2, -2, 3), Vector3(2, 2, 3))
    assert_true(_sum2_supported_environment())
    var original = external_call["sum2_test_set_mode", UInt64](mode)
    try:
        var mask = external_call["sum2_test_control_mask", UInt64]()
        var actual = external_call["sum2_test_get_state", UInt64]()
        var expected = external_call["sum2_test_mode_bits", UInt64](mode)
        assert_equal(actual & mask, expected)
        assert_false(_sum2_supported_environment())
        var terms = _reference_work(road, low, high)
        assert_equal(terms, 5000000005)
        assert_equal(_reference_work(road, low, low), 5000000005)
        assert_equal(_reference_work(road, high, high), -1)
        var point = _lane_value_bound(road, 0, 0, low, high)
        var x = point[0].rounded_value()
        var y = -point[1].rounded_value()
        var z = point[2].rounded_value()
        assert_false(x.is_finite())
        assert_false(y.is_finite())
        assert_true(z.is_finite())
        assert_true(z.low < 3.0 or z.high > 3.0)
        var work = _MapBuildWork(MapBuildBudget(0, 5, terms, 0))
        var result = _monotone_junction_enclosure(
            road, 0, 0, low, high, terms, proposal, x, y, z, work
        )
        _same(result[0], x)
        _same(result[1], y)
        _same(result[2], z)
        assert_equal(work.steps, 5)
        assert_equal(work.terms, terms)
        assert_false(work.exhausted)
        var short = _MapBuildWork(MapBuildBudget(0, 5, terms - 1, 0))
        with assert_raises(contains="global term budget"):
            _ = _monotone_junction_enclosure(
                road, 0, 0, low, high, terms, proposal, x, y, z, short
            )
        assert_equal(short.steps, 1)
        assert_equal(short.terms, 0)
        assert_true(short.exhausted)
        print(
            "LAST_REFUSAL_LEDGER",
            mode,
            work.steps,
            work.terms,
            short.steps,
            short.terms,
        )
    except error:
        external_call["sum2_test_restore_mode", NoneType](original)
        raise error
    external_call["sum2_test_restore_mode", NoneType](original)
    assert_equal(external_call["sum2_test_get_state", UInt64](), original)
    assert_true(_sum2_supported_environment())


def test_genuine_endpoint_refusals_keep_bounds_ledgers_and_state() raises:
    _first_endpoint_control()
    var modes = external_call["sum2_test_mode_count", Int32]()
    assert_true(modes == 5 or modes == 7)
    if modes == 7:
        _last_endpoint_control(Int32(5))
        _last_endpoint_control(Int32(6))
    else:
        print(
            "LAST_DAZ_CAPABILITY_UNAVAILABLE: fixture exposes Arm modes0..4;"
            " first-end FTZ control executed"
        )


def test_real_junction_admitted_endpoints_charge_both_traversals() raises:
    var road = _first_road()
    road.info.geometries[0].geometry.curvature_start = 0.0
    road.info.geometries[0].geometry.curvature_end = 0.0
    var low = Float64(0)
    var high = Float64(0.125)
    var terms = _reference_work(road, low, high)
    var first_terms = _reference_work(road, low, low)
    var last_terms = _reference_work(road, high, high)
    assert_true(terms >= 0)
    assert_true(first_terms >= 0)
    assert_true(last_terms >= 0)
    var point = _lane_value_bound(road, 0, 0, low, high)
    var work = _MapBuildWork(
        MapBuildBudget(0, 9, terms + first_terms + last_terms, 0)
    )
    var result = _monotone_junction_enclosure(
        road,
        0,
        0,
        low,
        high,
        terms,
        Box3(Vector3(-2, -2, 2), Vector3(2, 2, 2)),
        point[0].rounded_value(),
        -point[1].rounded_value(),
        point[2].rounded_value(),
        work,
    )
    assert_equal(work.steps, 9)
    assert_equal(work.terms, terms + first_terms + last_terms)
    assert_false(work.exhausted)
    for station in [low, high]:
        var actual = road._lane_center(0, 0, station)
        assert_true(result[0].contains(actual[0]))
        assert_true(result[1].contains(actual[1]))
        assert_true(result[2].contains(actual[2]))
    print("ADMITTED_LEDGER", work.steps, work.terms)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
