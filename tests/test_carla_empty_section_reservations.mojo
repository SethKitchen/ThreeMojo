# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reservation and Road metadata producers on valid empty lane sections.

Current Map callers already selected an existing lane. These controls instead
exercise the broader section-only Road operation contracts: an empty section
still has record boundaries and a well-defined straightness result.
"""

from extensions.carla.geometry import LINE, RoadGeometry
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.map_validation import (
    _reserve_lane_boundaries,
    _reserve_straightness,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    NO_JUNCTION,
    RoadId,
    RoadInfoElevation,
    RoadInfoGeometry,
    RoadInfoLaneOffset,
    SectionId,
)
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _empty_section() raises -> Road:
    var road = Road(
        RoadId(1), "empty section", 4.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = road.add_section(SectionId(0), 0.0)
    road.info.geometries.append(
        RoadInfoGeometry(0.0, RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 4.0))
    )
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial.constant(0.0))
    )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(0.0, CubicPolynomial.constant(0.0))
    )
    return road^


def test_empty_section_boundaries_keep_records_and_exact_reservation() raises:
    var road = _empty_section()
    assert_equal(len(road.sections[0].lanes), 0)
    var exact = _MapBuildWork(MapBuildBudget(0, 3, 0, 0))
    _reserve_lane_boundaries(road, 0, exact)
    var boundaries = road._lane_record_boundaries(0)
    # The real producer retains the geometry, elevation and offset records,
    # including their duplicate station values, despite having no lanes.
    var expected: List[Float64] = [0.0, 0.0, 0.0]
    assert_equal(boundaries, expected)
    assert_equal(exact.steps, len(boundaries))
    assert_equal(exact.records, 0)
    assert_false(exact.exhausted)
    var short = _MapBuildWork(MapBuildBudget(0, 2, 0, 0))
    with assert_raises(contains="step budget"):
        _reserve_lane_boundaries(road, 0, short)
    assert_equal(short.steps, 2)
    assert_true(short.exhausted)
    assert_equal(road._lane_record_boundaries(0), boundaries)


def test_empty_section_straightness_has_exact_reservation() raises:
    var road = _empty_section()
    assert_equal(len(road.sections[0].lanes), 0)
    var exact = _MapBuildWork(MapBuildBudget(0, 3, 0, 0))
    _reserve_straightness(road, 0, exact)
    # The public section-only producer admits this ordinarily constructed
    # empty section and still checks its line/elevation/offset records.
    assert_true(road.lane_is_straight(0))
    assert_equal(exact.steps, 3)
    assert_equal(exact.records, 0)
    assert_false(exact.exhausted)
    var short = _MapBuildWork(MapBuildBudget(0, 2, 0, 0))
    with assert_raises(contains="step budget"):
        _reserve_straightness(road, 0, short)
    assert_equal(short.steps, 2)
    assert_true(short.exhausted)
    assert_true(road.lane_is_straight(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
