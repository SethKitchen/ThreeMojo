# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent malformed-record controls for spatial map preflight.

Public geometry and sample fields can change after construction. Each
malformed fixture starts from an accepted generated geometry, changes one
field, and checks refusal on the next operation. Exact-budget controls
check record and scan admission without constructing or changing a Map.
"""

from extensions.carla.geometry import RoadGeometryKind
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.map_validation import (
    _count_information,
    _preflight_road_records,
    _reserve_lane_boundaries,
    _reserve_road_scan,
    _reserve_straightness,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    InformationSet,
    LANE_DRIVING,
    LaneId,
    NO_JUNCTION,
    RoadId,
    RoadInfoElevation,
    RoadInfoGeometry,
    RoadInfoLaneOffset,
    RoadInfoLaneWidth,
    SectionId,
)
from std.math import inf
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.carla_fixed_s_fixture import _fixed_geometry


def _information(kind: Int = 4) raises -> InformationSet:
    var info = InformationSet()
    info.geometries.append(
        RoadInfoGeometry(0.0, _fixed_geometry(kind, 0.0, 0.0))
    )
    return info^


def _assert_information_accepted(info: InformationSet) raises:
    # This fixture has one geometry record and its generated sample table.
    var entries = 1 + len(info.geometries[0].geometry.samples)
    var work = _MapBuildWork(MapBuildBudget(0, entries, 0, entries))
    _count_information(info, work)
    assert_equal(work.records, entries)
    assert_equal(work.steps, entries)
    assert_equal(work.segments, 0)
    assert_equal(work.terms, 0)
    assert_false(work.exhausted)


def _assert_geometry_refused(info: InformationSet) raises:
    # A geometry-domain error must precede its sample-table reservation.
    # The table cannot fit this budget, so the message pins guard ordering.
    assert_true(len(info.geometries[0].geometry.samples) >= 3)
    var work = _MapBuildWork(MapBuildBudget(0, 1, 0, 1))
    with assert_raises(contains="geometry has an invalid finite domain"):
        _count_information(info, work)
    assert_equal(work.records, 1)
    assert_equal(work.steps, 1)
    assert_false(work.exhausted)


def _assert_sample_refused(info: InformationSet) raises:
    var entries = 1 + len(info.geometries[0].geometry.samples)
    var work = _MapBuildWork(MapBuildBudget(0, entries, 0, entries))
    with assert_raises(contains="geometry has an invalid sample domain"):
        _count_information(info, work)
    # Storage and sample-scan work are admitted before sample validation.
    assert_equal(work.records, entries)
    assert_equal(work.steps, entries)
    assert_false(work.exhausted)


def _empty_road(length: Float64 = 10.0) raises -> Road:
    return Road(
        RoadId(1),
        "validation records",
        length,
        NO_JUNCTION,
        RoadId(0),
        RoadId(0),
        True,
    )


def _populated_road() raises -> Road:
    var road = _empty_road()
    road.info = _information()
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial.constant(0.0))
    )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(0.0, CubicPolynomial.constant(0.0))
    )
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    _ = road.sections[0].add_lane(LaneId(1))
    for lane in range(2):
        road.sections[0].lanes[lane].type = LANE_DRIVING
        road.sections[0].lanes[lane].info.widths.append(
            RoadInfoLaneWidth(0.0, CubicPolynomial.constant(2.0))
        )
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth(5.0, CubicPolynomial.constant(3.0))
    )
    return road^


def test_all_generated_geometry_kinds_pass_exact_record_admission() raises:
    for kind in range(5):
        var info = _information(kind)
        _assert_information_accepted(info)


def test_nonfinite_geometry_fields_are_independently_rejected() raises:
    var nan = bitcast[DType.float64](UInt64(0x7FF8000000000001))
    for value in [inf[DType.float64](), -inf[DType.float64](), nan]:
        # Leaf indexes at map_validation:38. Leaf 2 is the positive-length
        # comparison; leaf 3 checks the typed kind in separate controls.
        for field in [0, 1, 4, 5, 6, 7, 8]:
            var info = _information()
            _assert_information_accepted(info)
            if field == 0:
                info.geometries[0].s = value
            elif field == 1:
                info.geometries[0].geometry.length = value
            elif field == 4:
                info.geometries[0].geometry.x = value
            elif field == 5:
                info.geometries[0].geometry.y = value
            elif field == 6:
                info.geometries[0].geometry.heading = value
            elif field == 7:
                info.geometries[0].geometry.curvature_start = value
            else:
                info.geometries[0].geometry.curvature_end = value
            _assert_geometry_refused(info)


def test_zero_and_negative_geometry_lengths_are_refused() raises:
    for length in [Float64(0.0), Float64(-1.0)]:
        var info = _information()
        _assert_information_accepted(info)
        info.geometries[0].geometry.length = length
        _assert_geometry_refused(info)


def test_mutated_geometry_kind_is_refused_on_both_sides() raises:
    for kind in [-1, 5]:
        var info = _information()
        _assert_information_accepted(info)
        info.geometries[0].geometry.kind = RoadGeometryKind(kind)
        _assert_geometry_refused(info)


def test_nonfinite_sample_fields_are_independently_rejected() raises:
    var nan = bitcast[DType.float64](UInt64(0x7FF8000000000001))
    for value in [inf[DType.float64](), -inf[DType.float64](), nan]:
        # Change only the second generated sample. The first accepted
        # sample gives the monotonicity check a real predecessor.
        for field in [0, 3, 4, 5, 6]:
            var info = _information()
            _assert_information_accepted(info)
            if field == 0:
                info.geometries[0].geometry.samples[1].s = value
            elif field == 3:
                info.geometries[0].geometry.samples[1].u = value
            elif field == 4:
                info.geometries[0].geometry.samples[1].v = value
            elif field == 5:
                info.geometries[0].geometry.samples[1].tu = value
            else:
                info.geometries[0].geometry.samples[1].tv = value
            _assert_sample_refused(info)


def test_negative_sample_station_is_independent_of_order() raises:
    var info = _information()
    _assert_information_accepted(info)
    # -0.5 is above the initial predecessor -1.0. Only the nonnegative
    # station requirement fails, independently of the order comparison.
    info.geometries[0].geometry.samples[0].s = -0.5
    _assert_sample_refused(info)


def test_duplicate_and_decreasing_nonnegative_stations_are_refused() raises:
    for duplicate in [False, True]:
        var info = _information()
        _assert_information_accepted(info)
        if duplicate:
            info.geometries[0].geometry.samples[1].s = 0.0
        else:
            info.geometries[0].geometry.samples[2].s = (
                info.geometries[0].geometry.samples[1].s * 0.5
            )
        _assert_sample_refused(info)


def test_repaired_sample_is_revalidated_on_the_next_operation() raises:
    var info = _information()
    _assert_information_accepted(info)
    var original = info.geometries[0].geometry.samples[1].tv
    info.geometries[0].geometry.samples[1].tv = inf[DType.float64]()
    _assert_sample_refused(info)
    info.geometries[0].geometry.samples[1].tv = original
    _assert_information_accepted(info)


def test_sample_storage_and_scan_are_admitted_before_iteration() raises:
    var info = _information()
    var entries = 1 + len(info.geometries[0].geometry.samples)
    var records = _MapBuildWork(MapBuildBudget(0, entries, 0, entries - 1))
    with assert_raises(contains="source record budget"):
        _count_information(info, records)
    assert_equal(records.records, 1)
    assert_equal(records.steps, 1)
    assert_true(records.exhausted)
    var steps = _MapBuildWork(MapBuildBudget(0, entries - 1, 0, entries))
    with assert_raises(contains="step budget"):
        _count_information(info, steps)
    assert_equal(steps.records, entries)
    assert_equal(steps.steps, 1)
    assert_true(steps.exhausted)
    _assert_information_accepted(info)


def test_road_length_requires_finite_nonnegative_values() raises:
    for length in [Float64(0.0), Float64(10.0)]:
        var road = _empty_road(length)
        var work = _MapBuildWork(MapBuildBudget(0, 1, 0, 0))
        _preflight_road_records(road, work)
        assert_equal(work.steps, 1)
        assert_equal(work.records, 0)
        assert_false(work.exhausted)
    var nan = bitcast[DType.float64](UInt64(0x7FF8000000000001))
    for length in [
        Float64(-1.0),
        inf[DType.float64](),
        -inf[DType.float64](),
        nan,
    ]:
        var road = _empty_road(length)
        var work = _MapBuildWork(MapBuildBudget(0, 1, 0, 0))
        with assert_raises(contains="road has an invalid finite domain"):
            _preflight_road_records(road, work)
        assert_equal(work.steps, 1)
        assert_equal(work.records, 0)
        assert_false(work.exhausted)


def test_road_scan_handles_empty_sections_and_exact_nonempty_work() raises:
    # An edge-lane lookup can target a Road with no sections. It reserves
    # this scan before start_section/end_section reports the absent lane.
    var empty = _empty_road()
    var zero = _MapBuildWork(MapBuildBudget(0, 0, 0, 0))
    _reserve_road_scan(empty, zero)
    assert_equal(zero.steps, 0)
    assert_false(zero.exhausted)
    var road = _populated_road()
    var exact = _MapBuildWork(MapBuildBudget(0, 4, 0, 0))
    _reserve_road_scan(road, exact, section_passes=2)
    assert_equal(exact.steps, 4)
    assert_equal(exact.records, 0)
    assert_false(exact.exhausted)
    var short = _MapBuildWork(MapBuildBudget(0, 3, 0, 0))
    with assert_raises(contains="step budget"):
        _reserve_road_scan(road, short, section_passes=2)
    assert_equal(short.steps, 2)
    assert_true(short.exhausted)


def test_lane_boundaries_admit_generated_samples_and_all_widths() raises:
    var road = _populated_road()
    # One geometry, one elevation, one offset, two lanes, three widths.
    var expected = 8 + len(road.info.geometries[0].geometry.samples)
    var exact = _MapBuildWork(MapBuildBudget(0, expected, 0, 0))
    _reserve_lane_boundaries(road, 0, exact)
    assert_equal(exact.steps, expected)
    assert_equal(exact.records, 0)
    assert_false(exact.exhausted)
    var short = _MapBuildWork(MapBuildBudget(0, expected - 1, 0, 0))
    with assert_raises(contains="step budget"):
        _reserve_lane_boundaries(road, 0, short)
    assert_equal(short.steps, expected - 1)
    assert_true(short.exhausted)


def test_straightness_admits_all_section_lane_and_width_scans() raises:
    var road = _populated_road()
    # One section, one elevation, one offset, two lanes, three widths.
    var exact = _MapBuildWork(MapBuildBudget(0, 8, 0, 0))
    _reserve_straightness(road, 0, exact)
    assert_equal(exact.steps, 8)
    assert_equal(exact.records, 0)
    assert_false(exact.exhausted)
    var short = _MapBuildWork(MapBuildBudget(0, 7, 0, 0))
    with assert_raises(contains="step budget"):
        _reserve_straightness(road, 0, short)
    assert_equal(short.steps, 7)
    assert_true(short.exhausted)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
